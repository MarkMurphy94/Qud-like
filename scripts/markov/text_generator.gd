extends Node
# ==========
# TextGenerator — the single entry point for procedurally written text: place
# names, NPC names, book prose, dialogue barks.
#
#   TextGenerator.generate("place_name")                                # random
#   TextGenerator.generate("place_name", TextGenerator.seed_from(tile)) # stable
#   TextGenerator.generate("tavern_bark", -1, {"place_name": "Ashmoor"})
#
# Profiles in resources/markov/profiles/ carry everything domain-specific, so
# adding a naming style is two .tres files rather than a script change.
#
# Models are derived artefacts. A profile with none assigned trains its corpus
# the first time it is asked for and keeps it for the session, so the system
# works before anything has been baked; bake only once a corpus is big enough
# for that to be a visible pause (scripts/tools/bake_markov_models.gd).
# ==========

const PROFILE_DIR := "res://resources/markov/profiles/"
const MODEL_DIR := "res://resources/markov/models/"
const MAX_TEMPLATE_DEPTH := 4

## Profile id -> MarkovProfile.
var profiles: Dictionary = {}

var _models: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _slot_regex := RegEx.new()


func _ready() -> void:
	_rng.randomize()
	_slot_regex.compile("\\{([A-Za-z0-9_]+)\\}")
	_load_profiles()
	print("[TextGenerator] Loaded %d profiles" % profiles.size())


func _load_profiles() -> void:
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		push_warning("[TextGenerator] No profile folder at %s" % PROFILE_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var profile := load(PROFILE_DIR + file_name) as MarkovProfile
			if profile == null:
				push_warning("[TextGenerator] %s is not a MarkovProfile" % file_name)
			else:
				var key := profile.id if profile.id != "" else file_name.get_basename()
				profiles[key] = profile
		file_name = dir.get_next()
	dir.list_dir_end()


func has_profile(profile_id: String) -> bool:
	return profiles.has(profile_id)


## `seed_value` below zero draws from the shared RNG; anything else reproduces
## exactly. `slots` supplies template slot values, overriding profile lookup.
func generate(profile_id: String, seed_value: int = -1, slots: Dictionary = {}) -> String:
	var profile: MarkovProfile = profiles.get(profile_id)
	if profile == null:
		push_warning("[TextGenerator] Unknown profile: %s" % profile_id)
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value >= 0 else _rng.randi()
	return _render(profile, rng, slots, 0)


## `count` results from one seeded stream — the whole batch is reproducible,
## the entries within it differ.
func generate_many(profile_id: String, count: int, seed_value: int = -1, slots: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var profile: MarkovProfile = profiles.get(profile_id)
	if profile == null:
		push_warning("[TextGenerator] Unknown profile: %s" % profile_id)
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value >= 0 else _rng.randi()
	for _i in maxi(0, count):
		out.append(_render(profile, rng, slots, 0))
	return out


## Stable seed from whatever identifies the thing being named — a tile, an
## npc_id, an item id. Same key, same text, forever, which is why generated
## names never need saving.
func seed_from(key: Variant) -> int:
	if key is int:
		return absi(key)
	if key is Vector2i:
		var v: Vector2i = key
		return absi((v.x * 73856093) ^ (v.y * 19349663))
	return absi(hash(str(key)))


## Drop cached models so the next call retrains — for corpus editing in-editor.
func clear_cache() -> void:
	_models.clear()


# ═══════════════════════════════════════════════════════════════════════
#  RENDERING
# ═══════════════════════════════════════════════════════════════════════

func _render(profile: MarkovProfile, rng: RandomNumberGenerator, slots: Dictionary, depth: int) -> String:
	if profile.template.is_empty():
		return _decorate(_chain(profile, rng), profile, rng)
	if depth >= MAX_TEMPLATE_DEPTH:
		push_warning("[TextGenerator] Template recursion too deep at '%s'" % profile.id)
		return ""
	var out := profile.template
	for m in _slot_regex.search_all(profile.template):
		var slot := m.get_string(1)
		var value := ""
		if slots.has(slot):
			value = str(slots[slot])
		elif profiles.has(slot):
			value = _render(profiles[slot], rng, slots, depth + 1)
		else:
			push_warning("[TextGenerator] '%s' has no source for slot {%s}" % [profile.id, slot])
		out = out.replace(m.get_string(0), value)
	return _decorate(out, profile, rng)


## Rejection sampling: draw until something clears the length floor, stops on
## its own END rather than being cut off at the ceiling, and is not a verbatim
## training sample. The first draw is kept as a fallback so a thin corpus still
## returns something rather than nothing.
func _chain(profile: MarkovProfile, rng: RandomNumberGenerator) -> String:
	var model := _model_for(profile)
	if model.is_empty():
		return ""
	var fallback := ""
	for _attempt in maxi(1, profile.max_attempts):
		# One token of headroom, so a walk that would have kept going is
		# distinguishable from one that ended cleanly on the cap.
		var toks := _walk(model, rng, profile.max_length + 1)
		if toks.is_empty():
			continue
		var text := MarkovTrainer.join(toks, model.mode)
		if fallback.is_empty():
			fallback = text
		if toks.size() < profile.min_length or toks.size() > profile.max_length:
			continue
		if profile.reject_source_forms and model.is_source_form(text):
			continue
		return text
	return fallback


func _walk(model: MarkovModel, rng: RandomNumberGenerator, max_tokens: int) -> PackedStringArray:
	var out := PackedStringArray()
	var window := PackedStringArray()
	for _i in model.order:
		window.append(MarkovModel.START)
	var limit := maxi(1, max_tokens)
	while out.size() < limit:
		var next := _sample_backoff(model, window, rng)
		if next.is_empty() or next == MarkovModel.END:
			break
		out.append(next)
		window.append(next)
		window.remove_at(0)
	return out


## Longest known context wins; failing that, shorten it a token at a time. The
## zero-length context is the unigram row, which always exists, so this cannot
## dead-end on a non-empty model.
func _sample_backoff(model: MarkovModel, window: PackedStringArray, rng: RandomNumberGenerator) -> String:
	for n in range(model.order, -1, -1):
		var ctx := MarkovModel.make_context(window, window.size() - n, n)
		if model.has_context(ctx):
			var tok := model.sample(ctx, rng)
			if not tok.is_empty():
				return tok
	return ""


func _model_for(profile: MarkovProfile) -> MarkovModel:
	if profile.model != null and not profile.model.is_empty():
		return profile.model
	if _models.has(profile.id):
		return _models[profile.id]

	var model: MarkovModel = null
	if profile.corpus != null:
		var baked := "%s%s.tres" % [MODEL_DIR, profile.corpus.id]
		if ResourceLoader.exists(baked):
			model = load(baked) as MarkovModel
		if model == null or model.is_empty():
			model = MarkovTrainer.train(profile.corpus)
	else:
		push_warning("[TextGenerator] Profile '%s' has neither a model nor a corpus" % profile.id)
	if model == null:
		model = MarkovModel.new()
	_models[profile.id] = model
	return model


## Casing runs before affixes: affixes are authored already-cased, and the
## chain's own output is what needs fixing up.
func _decorate(text: String, profile: MarkovProfile, rng: RandomNumberGenerator) -> String:
	if text.is_empty():
		return text
	match profile.casing:
		MarkovProfile.Casing.CAPITALIZE:
			text = text.substr(0, 1).to_upper() + text.substr(1)
		MarkovProfile.Casing.TITLE_CASE:
			var parts := text.split(" ")
			for i in parts.size():
				if not parts[i].is_empty():
					parts[i] = parts[i].substr(0, 1).to_upper() + parts[i].substr(1)
			text = " ".join(parts)
		MarkovProfile.Casing.SENTENCE_CASE:
			text = text.substr(0, 1).to_upper() + text.substr(1)
			if not (text.right(1) in [".", "!", "?"]):
				text += "."

	if profile.affix_chance > 0.0 and rng.randf() < profile.affix_chance:
		var can_prefix := not profile.prefixes.is_empty()
		var can_suffix := not profile.suffixes.is_empty()
		if can_prefix and (not can_suffix or rng.randf() < 0.5):
			text = profile.prefixes[rng.randi() % profile.prefixes.size()] + text
		elif can_suffix:
			text += profile.suffixes[rng.randi() % profile.suffixes.size()]
	return text
