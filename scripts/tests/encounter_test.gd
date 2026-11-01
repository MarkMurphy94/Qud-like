extends Node

## Encounter spawning checks. Open scenes/tests/encounter_test.tscn and press
## F6; results go to the Output panel. Extended phase by phase.

const STARTER_IDS: Array[String] = [
	"wolf_pack", "deer_herd", "boar", "giant_spider", "bandit_ambush", "traveler", "cave_crawler",
]
const SEEDS := 200

var _failures: int = 0


func _ready() -> void:
	_check_database()
	_check_conditions()
	_check_determinism()
	_check_time_gating()
	_check_biome_gating()
	_check_budget()
	print("[EncounterTest] Done — %d failure(s)" % _failures)


func _check_database() -> void:
	for entry_id in STARTER_IDS:
		_expect(EncounterDatabase.get_entry(entry_id) != null, "starter entry %s loaded" % entry_id)
	for entry: EncounterEntry in EncounterDatabase.entries.values():
		_expect(NPCSpawner.ENCOUNTER_NPC_TYPES.has(entry.npc_type), "%s has a known npc_type" % entry.id)
		var known: Array = NPC.variants_for(NPCSpawner.ENCOUNTER_NPC_TYPES[entry.npc_type])
		for variant in entry.variants:
			_expect(variant in known, "%s variant %s exists" % [entry.id, variant])


func _check_conditions() -> void:
	var cond := EncounterCondition.new()
	cond.require_all = ["time.night"]
	cond.require_any = ["place.forest", "biome.jungle"]
	cond.forbid = ["near.settlement"]
	cond.min_difficulty = 2
	_expect(cond.matches(_ctx(["time.night", "biome.jungle"], 1, 2)), "require_all + one of require_any matches")
	_expect(not cond.matches(_ctx(["time.night"], 1, 2)), "no require_any tag fails")
	_expect(not cond.matches(_ctx(["time.day", "place.forest"], 1, 2)), "missing require_all fails")
	_expect(not cond.matches(_ctx(["time.night", "place.forest", "near.settlement"], 1, 2)), "forbidden tag fails")
	_expect(not cond.matches(_ctx(["time.night", "place.forest"], 1, 1)), "difficulty below min fails")
	_expect(EncounterCondition.new().matches(_ctx([], 1, 1)), "empty condition always matches")


func _check_determinism() -> void:
	var tags := ["biome.temperate", "place.forest", "time.day", "near.road", "control.none"]
	var first := _summary(EncounterResolver.resolve(_ctx(tags, 4242, 3), EncounterDatabase.ambient_entries()))
	var second := _summary(EncounterResolver.resolve(_ctx(tags, 4242, 3), EncounterDatabase.ambient_entries()))
	_expect(not first.is_empty(), "a temperate forest by day spawns something")
	_expect(first == second, "same seed and context give identical requests")
	var other := _summary(EncounterResolver.resolve(_ctx(tags, 4243, 3), EncounterDatabase.ambient_entries()))
	print("[EncounterTest] seed 4242 -> %s" % [first])
	print("[EncounterTest] seed 4243 -> %s" % [other])


func _check_time_gating() -> void:
	var night := ["biome.temperate", "place.forest", "time.night", "near.road", "control.none"]
	var seen_spider := false
	for seed_value in SEEDS:
		for request in EncounterResolver.resolve(_ctx(night, seed_value, 3), EncounterDatabase.ambient_entries()):
			var entry_id: String = request["entry"].id
			_expect(entry_id != "traveler" and entry_id != "deer_herd", "forest at night never yields %s (seed %d)" % [entry_id, seed_value])
			seen_spider = seen_spider or entry_id == "giant_spider"
	_expect(seen_spider, "giant_spider appears in a forest at night")

	var day := ["biome.temperate", "place.forest", "time.day"]
	for seed_value in SEEDS:
		for request in EncounterResolver.resolve(_ctx(day, seed_value, 3), EncounterDatabase.ambient_entries()):
			_expect(request["entry"].id != "giant_spider", "giant_spider never appears by day (seed %d)" % seed_value)


func _check_biome_gating() -> void:
	var desert := ["biome.desert", "time.day", "control.none"]
	var seen_vermin := false
	for seed_value in SEEDS:
		for request in EncounterResolver.resolve(_ctx(desert, seed_value, 2), EncounterDatabase.ambient_entries()):
			var entry_id: String = request["entry"].id
			_expect(entry_id != "wolf_pack" and entry_id != "deer_herd", "desert never yields %s" % entry_id)
			_expect(entry_id != "bandit_ambush", "bandits need a road")
			seen_vermin = seen_vermin or entry_id == "desert_vermin"
	_expect(seen_vermin, "desert_vermin appears in the desert")


func _check_budget() -> void:
	var tags := ["biome.temperate", "place.forest", "time.day", "near.road", "control.none"]
	for difficulty in [1, 2, 3, 4]:
		for seed_value in SEEDS:
			var ctx := _ctx(tags, seed_value, difficulty)
			var requests := EncounterResolver.resolve(ctx, EncounterDatabase.ambient_entries())
			var spent := 0
			var groups := {}
			var tiles := {}
			for request in requests:
				spent += (request["entry"] as EncounterEntry).budget_cost
				groups[request["group"]] = true
				tiles[request["tile"]] = true
			_expect(spent <= ctx.budget, "difficulty %d seed %d stays within budget (%d/%d)" % [difficulty, seed_value, spent, ctx.budget])
			_expect(groups.size() <= EncounterResolver.MAX_GROUPS, "at most MAX_GROUPS groups")
			_expect(tiles.size() == requests.size(), "no two spawns share a tile")


func _ctx(tags: Array, seed_value: int, difficulty: int) -> EncounterContext:
	var ctx := EncounterContext.new()
	ctx.difficulty = difficulty
	ctx.budget = EncounterContext.budget_for(difficulty)
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = seed_value
	for tag: String in tags:
		ctx.add_tag(tag)
	return ctx


func _summary(requests: Array[Dictionary]) -> Array:
	var out: Array = []
	for request in requests:
		out.append([request["entry"].id, request["variant"], request["tile"], request["group"]])
	return out


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[EncounterTest] FAIL: %s" % label)
