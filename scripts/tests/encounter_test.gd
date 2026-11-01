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
	_check_ecology()
	_check_camps()
	_check_snapshots()
	_check_cooldowns()
	_check_state_round_trip()
	EncounterState.reset()
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


func _check_ecology() -> void:
	EncounterState.reset()
	for region_id in ["test_cleared", "test_intact"]:
		EncounterState.register_region(region_id, "temperate")
		EncounterState.catch_up_region(region_id, 0)
	var baseline := EncounterState.pool_count("test_intact", "deer")
	_expect(baseline > 0.0, "a temperate region starts with deer")
	_expect(EncounterState.pool_count("test_intact", "wolves") > 0.0, "a temperate region starts with wolves")
	EncounterState.set_pool_count("test_cleared", "wolves", 0.0)

	for region_id in ["test_cleared", "test_intact"]:
		EncounterState.catch_up_region(region_id, 30)
	var cleared_deer := EncounterState.pool_count("test_cleared", "deer")
	var intact_deer := EncounterState.pool_count("test_intact", "deer")
	print("[EncounterTest] deer after 30 days: cleared %.1f, intact %.1f, baseline %.1f" % [cleared_deer, intact_deer, baseline])
	_expect(cleared_deer > baseline, "deer rise above baseline once the wolves are gone")
	_expect(cleared_deer > intact_deer, "deer do better without wolves than with them")
	_expect(EncounterState.pool_count("test_cleared", "wolves") == 0.0, "an emptied pool does not regrow on its own")

	var forest := ["biome.temperate", "place.forest", "time.day"]
	for seed_value in SEEDS:
		var ctx := _ctx(forest, seed_value, 3)
		ctx.region_id = "test_cleared"
		ctx.now_day = 30.0
		ctx.load_state()
		for request in EncounterResolver.resolve(ctx, EncounterDatabase.ambient_entries()):
			_expect(request["entry"].id != "wolf_pack", "no wolf_pack where the wolves were killed (seed %d)" % seed_value)


func _check_camps() -> void:
	EncounterState.reset()
	EncounterState.register_region("test_camp", "temperate")
	var camp := {"exists": true, "owner": "bandit", "size": "medium"}
	var ctx := _camp_ctx(camp)
	var camped := _count_entry(EncounterResolver.resolve(ctx, [], Callable(), Vector2i(80, 80), EncounterDatabase.anchor_entries()), "bandit_camp")
	_expect(camped >= 4 and camped <= 6, "a medium bandit camp holds 4-6 bandits (got %d)" % camped)

	EncounterState.set_pool_count("test_camp", "bandits", 0.0)
	ctx = _camp_ctx(camp)
	camped = _count_entry(EncounterResolver.resolve(ctx, [], Callable(), Vector2i(80, 80), EncounterDatabase.anchor_entries()), "bandit_camp")
	_expect(camped == 0, "a camp whose pool is empty is abandoned")
	_expect(ctx.has_tag("flag.camp_abandoned"), "an abandoned camp tags the context")


func _check_snapshots() -> void:
	EncounterState.reset()
	var survivors := [{"entry_id": "wolf_pack", "variant": "wolf", "group": 1, "index": 0, "tile": Vector2i(5, 5)}]
	EncounterState.store_snapshot("9,9", 100.0, survivors)

	var soon := _ctx(["biome.temperate", "place.forest", "time.day"], 1, 2)
	soon.tile_key = "9,9"
	soon.now_hour = 103.0
	soon.load_state()
	var restored := EncounterResolver.resolve(soon, EncounterDatabase.ambient_entries())
	_expect(restored.size() == 1, "a revisit within REVISIT_HOURS restores exactly the survivors")
	if restored.size() == 1:
		_expect(restored[0]["entry"].id == "wolf_pack" and restored[0]["tile"] == Vector2i(5, 5) and restored[0]["restored"],
			"the survivor comes back as itself, where it stood")

	var late := _ctx(["biome.temperate", "place.forest", "time.day"], 1, 2)
	late.tile_key = "9,9"
	late.now_hour = 107.0
	late.load_state()
	_expect(late.snapshot.is_empty(), "a snapshot older than REVISIT_HOURS is ignored")
	for request in EncounterResolver.resolve(late, EncounterDatabase.ambient_entries()):
		_expect(not request["restored"], "a late revisit rolls fresh")


func _check_cooldowns() -> void:
	EncounterState.reset()
	var ambush := EncounterDatabase.get_entry("bandit_ambush")
	_expect(ambush != null and ambush.cooldown_hours > 0.0, "bandit_ambush has a cooldown")
	if ambush == null:
		return
	EncounterState.start_cooldown("8,8", ambush, 10.0)
	_expect(EncounterState.cooldowns_for("8,8", 20.0).has("bandit_ambush"), "cooldown runs after the ambush")
	_expect(not EncounterState.cooldowns_for("8,8", 10.0 + ambush.cooldown_hours).has("bandit_ambush"), "cooldown ends on time")
	for seed_value in SEEDS:
		var ctx := _ctx(["biome.temperate", "time.day", "near.road", "control.none"], seed_value, 4)
		ctx.tile_key = "8,8"
		ctx.now_hour = 20.0
		ctx.load_state()
		_expect(_count_entry(EncounterResolver.resolve(ctx, EncounterDatabase.ambient_entries()), "bandit_ambush") == 0,
			"a cooling-down ambush does not roll (seed %d)" % seed_value)


func _check_state_round_trip() -> void:
	EncounterState.reset()
	EncounterState.register_region("test_save", "boreal")
	EncounterState.catch_up_region("test_save", 0)
	EncounterState.set_pool_count("test_save", "wolves", 3.5)
	EncounterState.start_cooldown("1,2", EncounterDatabase.get_entry("bandit_ambush"), 0.0)
	EncounterState.store_snapshot("1,2", 0.0, [{"entry_id": "boar", "variant": "boar", "group": 0, "index": 0, "tile": Vector2i(3, 4)}])
	var before := EncounterState.to_dict()
	EncounterState.from_dict(before)
	var after := EncounterState.to_dict()
	_expect(var_to_str(before) == var_to_str(after), "spawn_state survives a to_dict/from_dict round-trip")
	_expect((before["snapshots"] as Dictionary).has("1,2"), "a fresh snapshot is saved")
	EncounterState.from_dict({})
	_expect(EncounterState.pools.is_empty(), "an empty spawn_state starts fresh")


func _camp_ctx(camp: Dictionary) -> EncounterContext:
	var ctx := _ctx(["biome.temperate", "feature.camp"], 7, 2)
	ctx.region_id = "test_camp"
	ctx.metadata = {"camp": camp}
	ctx.load_state()
	return ctx


func _count_entry(requests: Array[Dictionary], entry_id: String) -> int:
	var n := 0
	for request in requests:
		if request["entry"].id == entry_id:
			n += 1
	return n


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
