extends RefCounted
class_name EncounterResolver

## Decides who is on a wilderness tile, without instancing anyone: resolve()
## returns spawn requests that NPCSpawner turns into NPCs. Keeping the two apart
## lets the whole algorithm run in a test scene with no map loaded.
##
## A request is {entry: EncounterEntry, variant: String, tile: Vector2i,
## group: int, index: int}. An empty variant leaves the pick to the spawner.

const MAX_GROUPS := 4
const CLUSTER_RADIUS := 3
const EDGE_DEPTH := 3
const MARGIN := 2
## Attempts to find a free walkable tile before settling for the last one tried.
const PLACEMENT_TRIES := 24


## `entries` are the candidates (normally EncounterDatabase.ambient_entries()).
## `walkable(tile) -> bool` guards placement; an empty Callable accepts any tile.
static func resolve(ctx: EncounterContext, entries: Array, walkable: Callable = Callable(),
		map_size: Vector2i = Vector2i(MapGenerator.WIDTH, MapGenerator.HEIGHT)) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var taken: Dictionary = {}
	var budget := ctx.budget
	var candidates := _ambient_candidates(ctx, entries)
	var groups := 0
	while budget > 0 and not candidates.is_empty() and groups < MAX_GROUPS:
		var entry := _pick_weighted(candidates, ctx)
		candidates.erase(entry)
		var largest := mini(entry.group_max, budget / entry.budget_cost)
		if largest < entry.group_min:
			continue
		var size := ctx.rng.randi_range(entry.group_min, largest)
		var tiles := _place_group(entry, size, ctx, walkable, map_size, taken)
		for i in size:
			var variant := ""
			if not entry.variants.is_empty():
				variant = entry.variants[ctx.rng.randi() % entry.variants.size()]
			requests.append({"entry": entry, "variant": variant, "tile": tiles[i], "group": groups, "index": i})
		budget -= size * entry.budget_cost
		groups += 1
	return requests


static func _ambient_candidates(ctx: EncounterContext, entries: Array) -> Array[EncounterEntry]:
	var out: Array[EncounterEntry] = []
	for entry: EncounterEntry in entries:
		if entry.kind != "ambient" or entry.base_weight <= 0.0:
			continue
		if entry.condition and not entry.condition.matches(ctx):
			continue
		out.append(entry)
	return out


static func entry_weight(entry: EncounterEntry, _ctx: EncounterContext) -> float:
	return entry.base_weight


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
