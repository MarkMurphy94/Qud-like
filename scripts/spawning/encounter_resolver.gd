extends RefCounted
class_name EncounterResolver

## Decides who is on a wilderness tile, without instancing anyone: resolve()
## returns spawn requests that NPCSpawner turns into NPCs. Keeping the two apart
## lets the whole algorithm run in a test scene with no map loaded.
##
## A request is {entry: EncounterEntry, variant: String, tile: Vector2i,
## group: int, index: int, restored: bool}. An empty variant leaves the pick to
## the spawner; restored requests come back from a survivor snapshot.
##
## Tiers resolve in order: a recent snapshot replaces everything, then the
## tile's camp anchor (guaranteed, may overspend the budget), then ambient fill
## for whatever budget is left. Persistent agents (tier 1) are not built yet.

const MAX_GROUPS := 4
const CLUSTER_RADIUS := 3
const EDGE_DEPTH := 3
const MARGIN := 2
## Attempts to find a free walkable tile before settling for the last one tried.
const PLACEMENT_TRIES := 24
## Camp size bands, from TileMetadata.camp.size.
const CAMP_SIZES := {"small": Vector2i(2, 3), "medium": Vector2i(4, 6), "large": Vector2i(7, 10)}
## Anchors may spend up to this many times the tile's budget.
const ANCHOR_BUDGET_MULT := 2


## `entries` are the ambient candidates and `anchors` the camp entries
## (normally EncounterDatabase.ambient_entries() / anchor_entries()).
## `walkable(tile) -> bool` guards placement; an empty Callable accepts any tile.
static func resolve(ctx: EncounterContext, entries: Array, walkable: Callable = Callable(),
		map_size: Vector2i = Vector2i(MapGenerator.WIDTH, MapGenerator.HEIGHT), anchors: Array = []) -> Array[Dictionary]:
	if not ctx.snapshot.is_empty():
		return _from_snapshot(ctx)
	var requests: Array[Dictionary] = []
	var taken: Dictionary = {}
	var budget := ctx.budget
	var groups := 0

	var anchor_spent := _resolve_anchor(ctx, anchors, walkable, map_size, taken, requests)
	if anchor_spent >= 0:
		budget -= anchor_spent
		groups += 1

	var candidates := _ambient_candidates(ctx, entries)
	while budget > 0 and not candidates.is_empty() and groups < MAX_GROUPS:
		var entry := _pick_weighted(candidates, ctx)
		candidates.erase(entry)
		var largest := mini(entry.group_max, budget / entry.budget_cost)
		largest = mini(largest, _pool_limit(ctx, entry))
		if largest < entry.group_min:
			continue
		var size := ctx.rng.randi_range(entry.group_min, largest)
		var tiles := _place_group(entry, size, ctx, walkable, map_size, taken)
		for i in size:
			var variant := ""
			if not entry.variants.is_empty():
				variant = entry.variants[ctx.rng.randi() % entry.variants.size()]
			requests.append({"entry": entry, "variant": variant, "tile": tiles[i], "group": groups, "index": i, "restored": false})
		budget -= size * entry.budget_cost
		groups += 1
	return requests


## The survivors of the last visit, where they stood. Entries that no longer
## exist are skipped rather than guessed at.
static func _from_snapshot(ctx: EncounterContext) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for survivor: Dictionary in ctx.snapshot.get("survivors", []):
		var entry: EncounterEntry = EncounterDatabase.get_entry(str(survivor.get("entry_id", "")))
		if entry == null:
			continue
		requests.append({
			"entry": entry,
			"variant": str(survivor.get("variant", "")),
			"tile": survivor.get("tile", Vector2i.ZERO),
			"group": int(survivor.get("group", 0)),
			"index": int(survivor.get("index", 0)),
			"restored": true,
		})
	return requests


## Fill the tile's camp from the best matching anchor entry. Returns the budget
## spent, or -1 when there is no camp or nothing to fill it with. A camp whose
## pool is empty is abandoned: it spawns nobody and tags the context so.
static func _resolve_anchor(ctx: EncounterContext, anchors: Array, walkable: Callable, map_size: Vector2i,
		taken: Dictionary, requests: Array[Dictionary]) -> int:
	var camp = ctx.metadata.get("camp", {})
	if not camp is Dictionary or not bool(camp.get("exists", false)):
		return -1
	var key := "camp.%s" % str(camp.get("owner", ""))
	var best: EncounterEntry = null
	for entry: EncounterEntry in anchors:
		if entry.kind != "anchor" or not key in entry.anchor_match:
			continue
		if entry.condition and not entry.condition.matches(ctx):
			continue
		if best == null or entry.base_weight > best.base_weight:
			best = entry
	if best == null:
		return -1
	var band: Vector2i = CAMP_SIZES.get(str(camp.get("size", "")), CAMP_SIZES["small"])
	var size := ctx.rng.randi_range(band.x, band.y)
	size = mini(size, ANCHOR_BUDGET_MULT * ctx.budget / best.budget_cost)
	size = mini(size, _pool_limit(ctx, best))
	if size <= 0:
		ctx.add_tag("flag.camp_abandoned")
		return -1
	var tiles := _place_group(best, size, ctx, walkable, map_size, taken)
	for i in size:
		var variant := ""
		if not best.variants.is_empty():
			variant = best.variants[ctx.rng.randi() % best.variants.size()]
		requests.append({"entry": best, "variant": variant, "tile": tiles[i], "group": 0, "index": i, "restored": false})
	return size * best.budget_cost


## Largest group a pool can show: everyone alive, floored. Unlimited without one.
static func _pool_limit(ctx: EncounterContext, entry: EncounterEntry) -> int:
	var count := ctx.pool_count(entry.pool_id)
	return 1 << 30 if is_inf(count) else int(floor(count))


static func _ambient_candidates(ctx: EncounterContext, entries: Array) -> Array[EncounterEntry]:
	var out: Array[EncounterEntry] = []
	for entry: EncounterEntry in entries:
		if entry.kind != "ambient" or entry.base_weight <= 0.0:
			continue
		if entry.condition and not entry.condition.matches(ctx):
			continue
		if ctx.cooldowns.has(entry.id):
			continue
		if _pool_limit(ctx, entry) < entry.group_min:
			continue
		out.append(entry)
	return out


static func entry_weight(entry: EncounterEntry, ctx: EncounterContext) -> float:
	return entry.base_weight * ctx.pool_factor(entry.pool_id)


static func _pick_weighted(candidates: Array[EncounterEntry], ctx: EncounterContext) -> EncounterEntry:
	var total := 0.0
	for entry in candidates:
		total += entry_weight(entry, ctx)
	var roll := ctx.rng.randf() * total
	for entry in candidates:
		roll -= entry_weight(entry, ctx)
		if roll < 0.0:
			return entry
	return candidates[-1]


# ─── Placement ─────────────────────────────────────────────────────────────────

static func _place_group(entry: EncounterEntry, size: int, ctx: EncounterContext, walkable: Callable,
		map_size: Vector2i, taken: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var centre := Vector2i.ZERO
	match entry.placement:
		"cluster", "anchor_point":
			centre = _find_tile(func() -> Vector2i: return _random_tile(ctx.rng, map_size), walkable, taken)
		"edge":
			var side := _pick_edge(ctx)
			centre = _find_tile(func() -> Vector2i: return _edge_tile(ctx.rng, map_size, side), walkable, taken)
	for i in size:
		var tile: Vector2i
		if entry.placement == "scatter":
			tile = _find_tile(func() -> Vector2i: return _random_tile(ctx.rng, map_size), walkable, taken)
		elif i == 0:
			tile = centre
		else:
			tile = _find_tile(func() -> Vector2i: return _near(ctx.rng, centre, map_size), walkable, taken)
		taken[tile] = true
		out.append(tile)
	return out


static func _find_tile(propose: Callable, walkable: Callable, taken: Dictionary) -> Vector2i:
	var tile: Vector2i = propose.call()
	for _attempt in PLACEMENT_TRIES:
		if not taken.has(tile) and (not walkable.is_valid() or walkable.call(tile)):
			return tile
		tile = propose.call()
	return tile


static func _random_tile(rng: RandomNumberGenerator, map_size: Vector2i) -> Vector2i:
	return Vector2i(
		rng.randi_range(MARGIN, map_size.x - 1 - MARGIN),
		rng.randi_range(MARGIN, map_size.y - 1 - MARGIN))


static func _near(rng: RandomNumberGenerator, centre: Vector2i, map_size: Vector2i) -> Vector2i:
	var tile := centre + Vector2i(
		rng.randi_range(-CLUSTER_RADIUS, CLUSTER_RADIUS),
		rng.randi_range(-CLUSTER_RADIUS, CLUSTER_RADIUS))
	return tile.clamp(Vector2i(MARGIN, MARGIN), map_size - Vector2i(MARGIN + 1, MARGIN + 1))


## A MapConfig.RoadExit side, preferring sides a road leaves by.
static func _pick_edge(ctx: EncounterContext) -> int:
	var sides: Array[int] = []
	for bit: int in [MapConfig.RoadExit.NORTH, MapConfig.RoadExit.EAST, MapConfig.RoadExit.SOUTH, MapConfig.RoadExit.WEST]:
		if ctx.road_exits & bit:
			sides.append(bit)
	if sides.is_empty():
		sides.assign([MapConfig.RoadExit.NORTH, MapConfig.RoadExit.EAST, MapConfig.RoadExit.SOUTH, MapConfig.RoadExit.WEST])
	return sides[ctx.rng.randi() % sides.size()]


static func _edge_tile(rng: RandomNumberGenerator, map_size: Vector2i, side: int) -> Vector2i:
	var along_x := rng.randi_range(MARGIN, map_size.x - 1 - MARGIN)
	var along_y := rng.randi_range(MARGIN, map_size.y - 1 - MARGIN)
	var depth := rng.randi_range(0, EDGE_DEPTH - 1)
	match side:
		MapConfig.RoadExit.NORTH:
			return Vector2i(along_x, MARGIN + depth)
		MapConfig.RoadExit.SOUTH:
			return Vector2i(along_x, map_size.y - 1 - MARGIN - depth)
		MapConfig.RoadExit.WEST:
			return Vector2i(MARGIN + depth, along_y)
		_:
			return Vector2i(map_size.x - 1 - MARGIN - depth, along_y)
