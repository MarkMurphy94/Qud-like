extends RefCounted
class_name FactionPalette

## Faction colours, and the ShaderMaterials that apply them.
##
## Several NPC variants share one cell of the roguelike master sheet, so faction
## identity is painted on at runtime by faction_recolor.gdshader rather than by
## authoring a separate sprite per faction. See NPC._apply_faction_recolor().
##
## TWO SEPARATE PIECES OF DATA, deliberately kept apart:
##   • the hue *window* describes the source art — "which of this sprite's
##     pixels are dyeable cloth". It lives with the sprite, so an NPC profile
##     can override it with a `recolor_hue_window` key when its art needs one.
##   • the target *colour* describes the faction, and is not authored here at
##     all: it is the `color` on the Faction resource (resources/faction.gd),
##     the same colour that faction flies on the world map overlay. Livery and
##     map colour being one value is the point — a blue banner in the field is
##     the blue province on the map.
##
## Keys are `faction_id` ("house_auberne"), matched case-insensitively.

const SHADER: Shader = preload("res://shaders/faction_recolor.gdshader")

## Scanned for Faction resources when no FactionMap has registered its own —
## test scenes, editor tools, and anything that runs without the world map.
const FACTION_DIR := "res://resources/factions/"

## The hue band treated as recolourable cloth on the roguelike sheet.
##
## Measured off the sheet rather than guessed. The NPC cells have no single
## garment hue to key on — there are blue tunics, green ones, maroon ones, grey
## and undyed robes — so this is stated the other way round, as everything
## EXCEPT skin and bare wood. Those sit in a tight band around hue 0.02–0.11
## (skin ≈ 0.05, staff and bow wood ≈ 0.08), and the window wraps past 0 to
## exclude it: start > end means "h >= start OR h <= end".
##
## What keeps this from repainting the whole sprite is the pair of floors in the
## shader: `sat_floor` spares greys, white linen and steel, and `value_floor`
## spares the darkest shade, which is the outline the silhouette needs at 16px.
## Verify any change with the shader's `debug_mask` uniform.
const DEFAULT_HUE_WINDOW := Vector2(0.11, 0.02)

## Brightness of lit cloth on the source sheet. A faction colour this bright
## leaves the art's own lightness alone; darker or brighter ones scale it. Only
## an assumption about the art, so it lives next to DEFAULT_HUE_WINDOW and gets
## verified the same way.
const SOURCE_VALUE := 0.75

## ── SKIN ──────────────────────────────────────────────────────────────────
## Flesh tones on the sheet, which are never dyed however well they fit the hue
## window. This is the exact guard that the window can only approximate: hue
## cannot reliably separate a cheek from tan leather, but an exact colour can.
##
## HOW TO FILL THIS IN
##  1. Eyedropper the face and hands of a few NPC cells. Take every step of each
##     ramp, not just the lit tone — the shadow and highlight steps are separate
##     colours and each needs a line here.
##  2. Run with the shader's `debug_mask` on. Green is a pixel this list is
##     protecting, magenta is one about to be dyed. Any magenta on a face means
##     a tone is still missing.
##
## Written as hex because that is what an image editor hands you. The entries
## below are the five commonest flesh-looking tones measured across the sheet's
## NPC cells — a starting point to correct, not a verified list.
static var SKIN_TONES: Array[Color] = [
	Color("cd8668"),  # 205,134,104 — by far the commonest, the lit tone
	Color("f1ab7a"),  # 241,171,122 — highlight
	# Color("b07d6a"),  # 176,125,106 — shadow
	# Color("b38a6b"),  # 179,138,107
	# Color("ba866a"),  # 186,134,106
]

## How near a pixel must sit to a SKIN_TONES entry, as a distance in RGB space.
## Tight on purpose: the sheet's tan leather (193,160,111) is only about 0.12
## from the nearest flesh tone, so a loose match would spare that too. Nearest
## filtering means pixels arrive exact, so this only has to absorb rounding.
const SKIN_TOLERANCE := 0.04

## Mirrors MAX_SKIN_TONES in faction_recolor.gdshader — a shader array is fixed
## length, and entries past it would be dropped in silence.
const MAX_SKIN_TONES := 8

## faction_id → colour, filled by register() or by scanning FACTION_DIR.
static var _colors: Dictionary = {}
static var _loaded: bool = false

## One material per faction+window combination, shared by every NPC that needs
## it. Duplicating a material per NPC would break draw-call batching for no
## benefit, since faction colour almost never changes at runtime.
static var _cache: Dictionary = {}

## Faction keys already complained about, so an unknown one warns once instead of
## once per NPC in a crowded settlement.
static var _warned: Dictionary = {}

## SKIN_TONES converted for the shader once. See _skin_tone_vectors().
static var _skin_vectors: PackedVector3Array = PackedVector3Array()

## Take colours from the factions FactionMap actually built, which is the
## authoritative set: it has already validated `faction_defs`, dropped the
## unusable entries and filled in a generated colour for anyone who authored
## none. Called from FactionMap.build().
static func register(factions: Array) -> void:
	_colors.clear()
	_cache.clear()
	_warned.clear()
	for faction in factions:
		if faction is Faction and faction.faction_id != "":
			_colors[faction.faction_id.to_lower()] = faction.color
	_loaded = true


## The faction's colour, or Color.WHITE when it has none. Callers that need to
## tell "white" from "absent" should ask has_faction() first.
static func color_for(faction: String) -> Color:
	_ensure_loaded()
	return _colors.get(faction.to_lower(), Color.WHITE)


static func has_faction(faction: String) -> bool:
	_ensure_loaded()
	return _colors.has(faction.to_lower())


## Every faction_id the palette knows a colour for.
static func known_factions() -> Array:
	_ensure_loaded()
	return _colors.keys()


## The material that paints `faction` onto art whose recolourable cloth sits in
## `hue_window`, or null when the faction has no colour. Null is the right
## default for ordinary townsfolk: they keep their original art and pay no
## material cost at all.
static func material_for(faction: String, hue_window: Vector2 = DEFAULT_HUE_WINDOW) -> ShaderMaterial:
	if not has_faction(faction):
		# "" is ordinary — most people belong to nobody. A name the palette has
		# never heard of is a typo or a missing .tres, and silently drawing that
		# NPC in plain art is exactly the bug that hides it.
		if faction != "" and not _warned.has(faction):
			_warned[faction] = true
			push_warning("[FactionPalette] No colour for faction '%s' — known: %s"
				% [faction, str(known_factions())])
		return null
	var key := "%s|%.3f,%.3f" % [faction.to_lower(), hue_window.x, hue_window.y]
	if _cache.has(key):
		return _cache[key]

	var color := color_for(faction)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("hue_window", hue_window)
	mat.set_shader_parameter("target_hue", color.h)
	# The colour supplies the hue outright; its saturation and value become
	# multipliers on whatever the source pixel already had, so the shading ramp
	# survives. Value is measured against SOURCE_VALUE so a faction colour of
	# ordinary brightness leaves the art's lightness where the artist put it.
	mat.set_shader_parameter("sat_scale", color.s)
	mat.set_shader_parameter("value_scale", clampf(color.v / SOURCE_VALUE, 0.0, 2.0))
	mat.set_shader_parameter("skin_tones", _skin_tone_vectors())
	mat.set_shader_parameter("skin_tone_count", mini(SKIN_TONES.size(), MAX_SKIN_TONES))
	mat.set_shader_parameter("skin_tolerance", SKIN_TOLERANCE)
	_cache[key] = mat
	return mat


## SKIN_TONES as the shader wants them. Built once — the list does not change at
## runtime, and every faction's material carries the same copy.
##
## Always exactly MAX_SKIN_TONES long, because the shader's array is fixed
## length. Unused slots hold a colour no pixel can be within reach of, so the
## padding is inert even before `skin_tone_count` stops the loop reaching it.
static func _skin_tone_vectors() -> PackedVector3Array:
	if not _skin_vectors.is_empty():
		return _skin_vectors
	if SKIN_TONES.size() > MAX_SKIN_TONES:
		push_warning("[FactionPalette] %d skin tones listed but the shader holds %d — the rest are ignored."
			% [SKIN_TONES.size(), MAX_SKIN_TONES])
	_skin_vectors.resize(MAX_SKIN_TONES)
	_skin_vectors.fill(Vector3(-1.0, -1.0, -1.0))
	for i in mini(SKIN_TONES.size(), MAX_SKIN_TONES):
		var tone: Color = SKIN_TONES[i]
		_skin_vectors[i] = Vector3(tone.r, tone.g, tone.b)
	return _skin_vectors


## Drop everything, so the next lookup re-reads from disk and rebuilds its
## materials. Needed after the .tres files or SKIN_TONES change under a running
## editor — cached materials hold the old values otherwise.
static func reload() -> void:
	_colors.clear()
	_cache.clear()
	_warned.clear()
	_skin_vectors.clear()
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	# Set before the scan so a failed one is not retried on every NPC.
	_loaded = true
	if not DirAccess.dir_exists_absolute(FACTION_DIR):
		push_warning("[FactionPalette] %s does not exist — nothing will be recoloured." % FACTION_DIR)
		return
	var dir := DirAccess.open(FACTION_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res := load(FACTION_DIR + file_name)
			# A faction that authored no colour is left out rather than given a
			# generated one: generated colours are handed out in `faction_defs`
			# order, which a directory listing cannot reproduce, so inventing one
			# here would disagree with the map overlay.
			if res is Faction and res.faction_id != "" and res.color != Color.WHITE:
				_colors[res.faction_id.to_lower()] = res.color
		file_name = dir.get_next()
	dir.list_dir_end()
