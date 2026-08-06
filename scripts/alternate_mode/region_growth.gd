extends RefCounted
class_name RegionGrowth

# region NOTES:
## Shared machinery for carving the overworld into regions that grow outward
## from seed tiles.
##
## Provinces (province_map.gd) and cultures (culture_map.gd) are the same idea
## with different seeds: pick some origin tiles, hand every land tile to
## whichever origin can reach it for the least travel effort, and paint the
## result as a single overlay texture. The only thing that differs is where the
## seeds come from — settlement icons for provinces, hand-authored coordinates
## for cultures — so that is the only part each of them writes itself.
##
## Growing rather than painting buys two things: borders follow the terrain
## (mountains and forest cost several times what open ground does, so a fill
## flows around a range and the frontier settles on the ridge), and the map
## stays editable (move a seed and the regions redraw themselves).
##
## Everything here is static and stateless — the region maps own their data.
## The fill is deterministic (fixed seed order, fixed neighbour order, integer
## costs), so results are recomputed on load rather than saved.
# endregion

const NO_REGION := -1

# Travel cost of entering a tile, in tenths of a plains step. The ratios are
# what shape the borders, not the absolute numbers.
const COST_PLAIN := 10
const COST_FOREST := 18
const COST_MOUNTAIN := 45
const COST_IMPASSABLE := 0

## Four-way, matching how the world is actually walked (the A* grid runs with
## DIAGONAL_MODE_NEVER). Fixed order so the fill is reproducible.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

const UNREACHED := 0x7FFFFFFF

## Reach of a seed with no special pull, as a percentage. 200 crosses ground at
## half the cost and so claims roughly twice as far; 50 is hemmed in.
const NORMAL_REACH := 100


static func build_cost_field(map, origin: Vector2i, w: int, h: int) -> PackedInt32Array:
	var cost := PackedInt32Array()
	cost.resize(w * h)
	var mountains: TileMapLayer = map.mountains
	var forests: TileMapLayer = map.forests
	for y in h:
		for x in w:
			var tile := origin + Vector2i(x, y)
			var value := COST_IMPASSABLE
			if map.is_land(tile):
				if mountains.get_cell_source_id(tile) != -1:
					value = COST_MOUNTAIN
				elif forests.get_cell_source_id(tile) != -1:
					value = COST_FOREST
				else:
					value = COST_PLAIN
			cost[y * w + x] = value
	return cost


## Multi-source Dijkstra from every seed at once, returning a region id per
## cell. `reach` is one percentage per seed (see NORMAL_REACH); pass an empty
## array to give every seed the same pull.
##
## The queue is a bucket queue rather than a heap: costs are small integers and
## the frontier only ever moves outward, so "the cheapest tile still waiting" is
## just the next non-empty bucket, and the scan never rewinds.
static func grow(seeds: Array[Vector2i], reach: PackedInt32Array, cost: PackedInt32Array,
		origin: Vector2i, w: int, h: int) -> PackedInt32Array:
	var cell_count := w * h
	var ids := PackedInt32Array()
	ids.resize(cell_count)
	ids.fill(NO_REGION)
	if seeds.is_empty() or cost.size() != cell_count:
		return ids

	var dist := PackedInt32Array()
	dist.resize(cell_count)
	dist.fill(UNREACHED)

	var pull := PackedInt32Array()
	pull.resize(seeds.size())
	for i in seeds.size():
		pull[i] = maxi(1, reach[i]) if i < reach.size() else NORMAL_REACH

	var buckets: Dictionary = {}
	for i in seeds.size():
		var idx := (seeds[i].y - origin.y) * w + (seeds[i].x - origin.x)
		if idx < 0 or idx >= cell_count:
			push_warning("[RegionGrowth] Seed %s is outside the map — skipped." % seeds[i])
			continue
		dist[idx] = 0
		ids[idx] = i
		_push(buckets, 0, idx)

	var step_cost := 0
	var max_cost := 0
	while step_cost <= max_cost:
		if not buckets.has(step_cost):
			step_cost += 1
			continue
		var bucket: Array = buckets[step_cost]
		buckets.erase(step_cost)
		for idx: int in bucket:
			# A cheaper route reached this tile after it was queued.
			if dist[idx] != step_cost:
				continue
			var id := ids[idx]
			var x := idx % w
			var y := idx / w
			for dir: Vector2i in NEIGHBOURS:
				var nx := x + dir.x
				var ny := y + dir.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var terrain := cost[n]
				if terrain == COST_IMPASSABLE:
					continue
				# Never free, or a far-reaching seed would swallow the world in
				# a single bucket and the queue would stop being ordered.
				var next_cost := step_cost + maxi(1, terrain * NORMAL_REACH / pull[id])
				# `>=` keeps the first claimant on a tie, which is what makes
				# the result depend only on seed order and not on timing.
				if next_cost >= dist[n]:
					continue
				dist[n] = next_cost
				ids[n] = id
				_push(buckets, next_cost, n)
				if next_cost > max_cost:
					max_cost = next_cost
		step_cost += 1
	return ids


static func _push(buckets: Dictionary, cost: int, idx: int) -> void:
	# Untyped Array on purpose: it is a reference, so appending does not copy
	# the bucket back into the dictionary the way a packed array would.
	var bucket: Array = buckets.get(cost, [])
	if bucket.is_empty():
		buckets[cost] = bucket
	bucket.append(idx)


## Tally how many cells each region ended up with, indexed by region id.
static func count_tiles(ids: PackedInt32Array, region_count: int) -> PackedInt32Array:	
	var counts := PackedInt32Array()
	counts.resize(region_count)
	counts.fill(0)
	for id in ids:
		if id != NO_REGION:
			counts[id] += 1
	return counts


## One pixel per tile blown up to tile size, so a whole overlay is a single
## texture instead of thousands of draw calls — which is also why it must not be
## filtered, or every border would blur across its neighbours.
static func make_overlay_sprite(z: int, start_visible: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "overlay"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = z
	sprite.visible = start_visible
	return sprite


## `rect` is the map's painted extent in pixels. Border cells are drawn more
## strongly so regions read as outlined territories rather than a wash of colour.
static func paint_overlay(sprite: Sprite2D, ids: PackedInt32Array, w: int, h: int,
		colors: PackedColorArray, rect: Rect2,
		interior_alpha: float, border_alpha: float) -> void:
	if sprite == null or ids.is_empty() or w <= 0 or h <= 0:
		return
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var id := ids[y * w + x]
			if id == NO_REGION or id >= colors.size():
				continue
			var color: Color = colors[id]
			color.a = border_alpha if is_border(ids, w, h, x, y, id) else interior_alpha
			image.set_pixel(x, y, color)
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.position = rect.position
	sprite.scale = rect.size / Vector2(w, h)


## Border = touches anything that is not this region, coastline included.
static func is_border(ids: PackedInt32Array, w: int, h: int, x: int, y: int, id: int) -> bool:
	for dir: Vector2i in NEIGHBOURS:
		var nx := x + dir.x
		var ny := y + dir.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			return true
		if ids[ny * w + nx] != id:
			return true
	return false


# ═══════════════════════════════════════════════════════════════════════


## Hues walked by the golden ratio, which spreads any number of neighbouring
## ids as far apart on the colour wheel as they can get.
static func generated_color(id: int, saturation: float = 0.55, value: float = 0.95) -> Color:
	return Color.from_hsv(fposmod(id * 0.6180339887, 1.0), saturation, value)
