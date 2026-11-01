extends RefCounted
class_name EncounterContext

## The facts about one wilderness tile right now, flattened into tags that
## EncounterCondition tests. Separate from SpawnContext, which describes a
## single item slot rather than a whole tile.

var tile_key: String = ""
var region_id: String = ""
var coords: Vector2i = Vector2i.ZERO
var difficulty: int = 1
var budget: int = 2
var now_day: float = 0.0
var now_hour: float = 0.0
## MapConfig.RoadExit bitmask; edge placement prefers these sides.
var road_exits: int = 0
var rng: RandomNumberGenerator
var metadata: Dictionary = {}
var place: Place = null
## True once load_state() has read the region's pools. Until then pools do not
## limit anything, which is what headless tests without a region rely on.
var pools_known: bool = false
## pool_id -> {count, capacity} for the pools living in this region.
var pools: Dictionary = {}
## entry_id -> game hour the entry's cooldown on this tile ends.
var cooldowns: Dictionary = {}
## The tile's survivor snapshot if it is recent enough to restore, else {}.
var snapshot: Dictionary = {}
## Live spawn modifiers covering this tile; their context_tags are already in.
var modifiers: Array[SpawnModifier] = []
var _tags: Dictionary = {}


## Context for the local map built from `metadata` (the dict MainGame hands the
## generator). The RNG seed changes every game hour: the same hour rerolls the
## same encounters, a later visit rolls fresh.
static func build(metadata: Dictionary, area_place: Place = null) -> EncounterContext:
	var ctx := EncounterContext.new()
	ctx.metadata = metadata
	ctx.place = area_place
	ctx.coords = metadata.get("coords", Vector2i.ZERO)
	ctx.tile_key = "%d,%d" % [ctx.coords.x, ctx.coords.y]
	ctx.region_id = str(metadata.get("region_id", ""))
	ctx.difficulty = int(metadata.get("encounter_difficulty", 1))
	ctx.budget = budget_for(ctx.difficulty)
	ctx.road_exits = int(metadata.get("road_exits", 0))
	ctx.now_hour = WorldClock.total_hours()
	ctx.now_day = WorldClock.total_days()
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = hash([int(metadata.get("seed", 0)), int(ctx.now_hour)])
	ctx._emit_tags(WorldClock.time_of_day(), WorldClock.season())
	ctx.load_state()
	return ctx


## Catch the region up to now and read its pools, plus the tile's cooldowns,
## snapshot and spawn modifiers. A context with no region_id is left unlimited.
func load_state() -> void:
	if not tile_key.is_empty():
		cooldowns = EncounterState.cooldowns_for(tile_key, now_hour)
		snapshot = EncounterState.snapshot_for(tile_key, now_hour)
	modifiers = EncounterState.live_modifiers_for(tile_key, region_id, now_day)
	for mod in modifiers:
		for tag in mod.context_tags:
			add_tag(tag)
	if region_id.is_empty():
		return
	EncounterState.catch_up_region(region_id, int(now_day))
	pools = EncounterState.region_summary(region_id)
	pools_known = true


## How many of a pool live here; unlimited when pools are not known.
func pool_count(pool_id: String) -> float:
	if pool_id.is_empty() or not pools_known:
		return INF
	return float(pools.get(pool_id, {}).get("count", 0.0))


## Sparse populations show up rarely: count / capacity, floored at 0.1.
func pool_factor(pool_id: String) -> float:
	if pool_id.is_empty() or not pools_known or not pools.has(pool_id):
		return 1.0
	var cap := float(pools[pool_id]["capacity"])
	if cap <= 0.0:
		return 0.1
	return clampf(pool_count(pool_id) / cap, 0.1, 1.0)


## Product of every live modifier's effect on the entry's weight.
func modifier_weight(entry: EncounterEntry) -> float:
	var mult := 1.0
	for mod in modifiers:
		mult *= mod.weight_multiplier(entry.weight_tags, now_day)
	return mult


static func budget_for(difficulty: int) -> int:
	return clampi(2 + (difficulty - 1) * 2, 2, 8)


func add_tag(tag: String) -> void:
	_tags[tag] = true


func has_tag(tag: String) -> bool:
	return _tags.has(tag)


func tags() -> Array:
	return _tags.keys()


func _emit_tags(time_of_day: String, season: String) -> void:
	if place:
		for tag in place.tags:
			add_tag(tag)
	else:
		var biome := str(metadata.get("biome", "")).to_lower()
		if not biome.is_empty():
			add_tag("biome.%s" % biome)
		if bool(metadata.get("is_forest", false)):
			add_tag("place.forest")

	var ruler := str(metadata.get("ruling_faction", ""))
	add_tag("control.none" if ruler.is_empty() else "control.%s" % ruler)

	if road_exits != 0 or bool(metadata.get("near_road", false)):
		add_tag("near.road")
	if bool(metadata.get("near_settlement", false)):
		add_tag("near.settlement")

	for feature: String in ["camp", "dungeon_entrance", "ruins"]:
		var data = metadata.get(feature, {})
		if data is Dictionary and bool(data.get("exists", false)):
			add_tag("feature.%s" % feature)
	var water = metadata.get("water_features", {})
	if water is Dictionary:
		for kind: String in water:
			if bool(water[kind]):
				add_tag("feature.%s" % kind)

	add_tag("time.%s" % time_of_day)
	add_tag("season.%s" % season)

	var flags = metadata.get("flags", {})
	if flags is Dictionary:
		for flag: String in flags:
			if bool(flags[flag]):
				add_tag("flag.%s" % flag)
