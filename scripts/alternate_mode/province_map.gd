extends Node2D
class_name ProvinceMap

## Political division of the overworld into provinces — the territory factions
## own, fight over and tax.
##
## HOW PROVINCES ARE MADE
## Nothing is painted by hand. Every settlement icon already on the world map's
## `locations` layer is taken as a provincial capital, and the land is handed
## out by a multi-source Dijkstra flood from all of them at once: a tile joins
## whichever capital can reach it for the least travel effort.
##
## That single rule buys the two things a hand-drawn map is usually needed for:
##   • Borders follow the terrain. Mountains and forest cost several times what
##     open ground does, so the fill flows around a range rather than over it
##     and the frontier settles on the ridge — which is where real borders sit.
##   • The map stays editable. Move, add or delete a settlement icon and the
##     provinces redraw themselves; there is no second map to keep in sync.
##
## The fill is deterministic (fixed seed order, fixed neighbour order, integer
## costs), so it is recomputed on load rather than saved. Only `faction` — the
## one thing play changes — goes into the save file, keyed by province id.
##
## USAGE
##   province_at(tile) -> int        province id, or NO_PROVINCE for sea/void
##   province_for_tile(tile)         the Province resource, or null
##   toggle_overlay()                political map on/off (bound to "toggle_provinces")
##
## Authored overrides: put Province .tres files in `province_defs` with their
## `capital_tile` set to a settlement's coords to replace that province's
## generated name / faction / colour. Everything else keeps its generated ones.

const ProvinceDef := preload("res://resources/province.gd")

## Returned by province_at() for water, unpainted void, and land no capital
## could reach (an island with no settlement on it).
const NO_PROVINCE := -1

# ── Travel cost of entering a tile, in tenths of a plains step ───────────
# The ratios are what shape the borders, not the absolute numbers. Forest is
# expensive enough that a province stops at a large wood rather than absorbing
# it whole; mountains are dear enough that a range almost always ends up as a
# frontier, but not infinite — a ridge still belongs to somebody.
const COST_PLAIN := 10
const COST_FOREST := 18
const COST_MOUNTAIN := 45
## Marks a tile provinces cannot spread through at all (sea, void).
const COST_IMPASSABLE := 0

## Four-way, matching how the world is actually walked (the A* grid runs with
## DIAGONAL_MODE_NEVER). Fixed order so the fill is reproducible.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

## Sentinel distance for "not reached yet".
const UNREACHED := 0x7FFFFFFF

## Tile category on the `locations` layer that counts as a settlement. That
## layer also carries roads (category "road"), which must not seed provinces.
const CAPITAL_CATEGORY := "building"

@export_group("Overlay")
## Opacity of a province's interior on the political map.
@export_range(0.0, 1.0) var overlay_alpha: float = 0.30
## Opacity of tiles that touch another province, the sea or the void. Drawing
## these stronger is what makes the regions read as outlined territories rather
## than a wash of colour.
@export_range(0.0, 1.0) var border_alpha: float = 0.85
## Starts hidden — the political map is a thing the player asks for.
@export var overlay_visible_on_start: bool = false

@export_group("Authoring")
## Optional Province resources that override generated data, matched to a grown
## province by `capital_tile`. Anything not listed here is fully generated.
@export var province_defs: Array[Resource] = []

## Every province, indexed by id.
var provinces: Array[ProvinceDef] = []

## The qud_like_world_map this divides up. Untyped so the calls below resolve
## against its actual API rather than Node2D's.
var _world_map = null
var _overlay: Sprite2D = null

# Province data is held in flat arrays indexed by `_index(tile)` rather than in
# a Dictionary keyed by Vector2i: the flood touches every land tile four times
# over, and a packed array turns that inner loop from hashing into arithmetic.
var _origin: Vector2i = Vector2i.ZERO
var _w: int = 0
var _h: int = 0
var _ids := PackedInt32Array()
var _cost := PackedInt32Array()


func _ready() -> void:
	_overlay = Sprite2D.new()
	_overlay.name = "overlay"
	_overlay.centered = false
	# One pixel per tile, blown up to tile size — so the political map must not
	# be smoothed or every border would blur across its neighbours.
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Above the tile layers, which sit at the default z.
	_overlay.z_index = 100
	_overlay.visible = overlay_visible_on_start
	add_child(_overlay)


# ═══════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════

## Grow the provinces for `map` (a qud_like_world_map). Called from that map's
## _ready(); safe to call again after editing the locations layer.
func build(map) -> void:
	_world_map = map
	provinces.clear()
	_ids = PackedInt32Array()

	var bounds: Rect2i = map.bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_warning("[Provinces] World map has no painted extent — nothing to divide.")
		return
	_origin = bounds.position
	_w = bounds.size.x
	_h = bounds.size.y

	var started := Time.get_ticks_msec()
	var capitals := _collect_capitals()
	if capitals.is_empty():
		push_warning("[Provinces] No settlement icons on the locations layer — no capitals to grow from.")
		return

	_build_cost_field()
	for i in capitals.size():
		provinces.append(_make_province(i, capitals[i]))
	_grow(capitals)
	var claimed := _count_tiles()
	refresh_overlay()

	print("[Provinces] %d provinces over %d land tiles in %d ms"
		% [provinces.size(), claimed, Time.get_ticks_msec() - started])


## Settlement tiles, sorted so province ids are stable between runs (used-cell
## order is an implementation detail of the tilemap, province ids are saved).
func _collect_capitals() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var layer: TileMapLayer = _world_map.locations
	for tile: Vector2i in layer.get_used_cells():
		# The locations layer doubles as the road layer, so a marker only counts
		# as a capital if its art is actually a building.
		if _world_map.category_at(layer, tile) != CAPITAL_CATEGORY:
			continue
		if not _world_map.is_land(tile):
			continue
		out.append(tile)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


## One pass over the map turning terrain into travel cost, so the flood itself
## never has to touch a tilemap again.
func _build_cost_field() -> void:
	_cost = PackedInt32Array()
	_cost.resize(_w * _h)
	var mountains: TileMapLayer = _world_map.mountains
	var forests: TileMapLayer = _world_map.forests
	for y in _h:
		for x in _w:
			var tile := _origin + Vector2i(x, y)
			var value := COST_IMPASSABLE
			if _world_map.is_land(tile):
				if mountains.get_cell_source_id(tile) != -1:
					value = COST_MOUNTAIN
				elif forests.get_cell_source_id(tile) != -1:
					value = COST_FOREST
				else:
					value = COST_PLAIN
			_cost[y * _w + x] = value


## Multi-source Dijkstra from every capital at once.
##
## The queue is a bucket queue rather than a heap: costs are small integers and
## the frontier only ever moves outward, so "the cheapest tile still waiting"
## is just the next non-empty bucket, and the scan over `cost` never rewinds.
func _grow(capitals: Array[Vector2i]) -> void:
	var cell_count := _w * _h
	_ids.resize(cell_count)
	_ids.fill(NO_PROVINCE)
	var dist := PackedInt32Array()
	dist.resize(cell_count)
	dist.fill(UNREACHED)

	var buckets: Dictionary = {}
	for i in capitals.size():
		var idx := _index(capitals[i])
		dist[idx] = 0
		_ids[idx] = i
		_push(buckets, 0, idx)

	var cost := 0
	var max_cost := 0
	while cost <= max_cost:
		if not buckets.has(cost):
			cost += 1
			continue
		var bucket: Array = buckets[cost]
		buckets.erase(cost)
		for idx: int in bucket:
			# A cheaper route reached this tile after it was queued.
			if dist[idx] != cost:
				continue
			var id := _ids[idx]
			var x := idx % _w
			var y := idx / _w
			for dir: Vector2i in NEIGHBOURS:
				var nx := x + dir.x
				var ny := y + dir.y
				if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
					continue
				var n := ny * _w + nx
				var step := _cost[n]
				if step == COST_IMPASSABLE:
					continue
				var next_cost := cost + step
				# `>=` keeps the first claimant on a tie, which is what makes
				# the result depend only on capital order and not on timing.
				if next_cost >= dist[n]:
					continue
				dist[n] = next_cost
				_ids[n] = id
				_push(buckets, next_cost, n)
				if next_cost > max_cost:
					max_cost = next_cost
		cost += 1


func _push(buckets: Dictionary, cost: int, idx: int) -> void:
	# Untyped Array on purpose: it is a reference, so appending does not copy
	# the bucket back into the dictionary the way a packed array would.
	var bucket: Array = buckets.get(cost, [])
	if bucket.is_empty():
		buckets[cost] = bucket
	bucket.append(idx)


func _make_province(id: int, capital: Vector2i) -> ProvinceDef:
	for def: Resource in province_defs:
		if def is ProvinceDef and (def as ProvinceDef).capital_tile == capital:
			var authored := (def as ProvinceDef).duplicate() as ProvinceDef
			authored.id = id
			if authored.display_name == "":
				authored.display_name = _generated_name(capital)
			# An untouched colour means the author cared about the name or the
			# faction, not the swatch — give it a distinct generated one rather
			# than leaving every authored province white.
			if authored.color == Color.WHITE:
				authored.color = _generated_color(id)
			return authored
	var province := ProvinceDef.new()
	province.id = id
	province.capital_tile = capital
	province.display_name = _generated_name(capital)
	province.color = _generated_color(id)
	return province


## Tally each province's size, and report how much land was claimed in total.
func _count_tiles() -> int:
	var claimed := 0
	for id in _ids:
		if id != NO_PROVINCE:
			provinces[id].tile_count += 1
			claimed += 1
	return claimed


# ═══════════════════════════════════════════════════════════════════════
#  GENERATED NAME / COLOUR
# ═══════════════════════════════════════════════════════════════════════

const NAME_HEADS: Array[String] = [
	"Var", "Kel", "Thra", "Mor", "Dun", "Esh", "Bran", "Cal",
	"Ost", "Ryn", "Hal", "Vek", "Aer", "Gor", "Sil", "Tor",
]
const NAME_TAILS: Array[String] = [
	"mark", "dale", "holt", "fell", "reach", "moor", "wold",
	"gard", "shire", "vale", "stead", "hollow", "crest", "mere",
]

## Named from its capital's coordinates, using the same mixing constants as
## main_game._deterministic_seed — so a province keeps its name for as long as
## its capital stays put, with nothing stored anywhere.
func _generated_name(capital: Vector2i) -> String:
	var hash_value := absi((capital.x * 73856093) ^ (capital.y * 19349663))
	var head: String = NAME_HEADS[hash_value % NAME_HEADS.size()]
	var tail: String = NAME_TAILS[(hash_value / NAME_HEADS.size()) % NAME_TAILS.size()]
	return head + tail


## Hues walked by the golden ratio, which spreads any number of neighbouring
## ids as far apart on the colour wheel as they can get.
func _generated_color(id: int) -> Color:
	return Color.from_hsv(fposmod(id * 0.6180339887, 1.0), 0.55, 0.95)


# ═══════════════════════════════════════════════════════════════════════
#  QUERIES
# ═══════════════════════════════════════════════════════════════════════

func _index(tile: Vector2i) -> int:
	return (tile.y - _origin.y) * _w + (tile.x - _origin.x)


func _in_grid(tile: Vector2i) -> bool:
	var x := tile.x - _origin.x
	var y := tile.y - _origin.y
	return x >= 0 and y >= 0 and x < _w and y < _h


## Which province holds this tile, or NO_PROVINCE for sea, void and unclaimed
## land.
func province_at(tile: Vector2i) -> int:
	if _ids.is_empty() or not _in_grid(tile):
		return NO_PROVINCE
	return _ids[_index(tile)]


func get_province(id: int) -> ProvinceDef:
	return provinces[id] if id >= 0 and id < provinces.size() else null


func province_for_tile(tile: Vector2i) -> ProvinceDef:
	return get_province(province_at(tile))


## The faction holding a tile, or "" where nobody does.
func faction_at(tile: Vector2i) -> String:
	var province := province_for_tile(tile)
	return province.faction if province else ""


# ═══════════════════════════════════════════════════════════════════════
#  OWNERSHIP  (the only part play changes, and so the only part saved)
# ═══════════════════════════════════════════════════════════════════════

func set_faction(id: int, faction: String) -> void:
	var province := get_province(id)
	if province:
		province.faction = faction


## Snapshot for the save file: province id (as a String key, because that is
## what survives resource serialisation) → faction.
func ownership_dict() -> Dictionary:
	var out: Dictionary = {}
	for province in provinces:
		out[str(province.id)] = province.faction
	return out


func apply_ownership(data: Dictionary) -> void:
	for key: String in data:
		var province := get_province(int(key))
		if province:
			province.faction = str(data[key])


# ═══════════════════════════════════════════════════════════════════════
#  POLITICAL MAP OVERLAY
# ═══════════════════════════════════════════════════════════════════════

## Repaint the overlay from the current provinces. One pixel per tile, scaled
## up to tile size, so the whole political map is a single texture instead of
## thousands of draw calls.
func refresh_overlay() -> void:
	if _overlay == null or _ids.is_empty():
		return
	var image := Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in _h:
		for x in _w:
			var id := _ids[y * _w + x]
			if id == NO_PROVINCE:
				continue
			var color: Color = provinces[id].color
			color.a = border_alpha if _is_border(x, y, id) else overlay_alpha
			image.set_pixel(x, y, color)
	_overlay.texture = ImageTexture.create_from_image(image)

	var rect: Rect2 = _world_map.bounds_px()
	_overlay.position = rect.position
	_overlay.scale = rect.size / Vector2(_w, _h)


## Border = touches anything that is not this province, coastline included.
func _is_border(x: int, y: int, id: int) -> bool:
	for dir: Vector2i in NEIGHBOURS:
		var nx := x + dir.x
		var ny := y + dir.y
		if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
			return true
		if _ids[ny * _w + nx] != id:
			return true
	return false


func is_overlay_visible() -> bool:
	return _overlay != null and _overlay.visible


func set_overlay_visible(value: bool) -> void:
	if _overlay:
		_overlay.visible = value


## Flip the political map and report the new state, so the caller can say so.
func toggle_overlay() -> bool:
	set_overlay_visible(not is_overlay_visible())
	return is_overlay_visible()
