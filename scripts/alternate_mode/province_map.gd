extends Node2D
class_name ProvinceMap

## Political division of the overworld into provinces — the territory factions
## own, fight over and tax.
##
## HOW PROVINCES ARE MADE
## Nothing is painted by hand. Every settlement icon already on the world map's
## `locations` layer is taken as a provincial capital, and the land is handed
## out by a multi-source Dijkstra flood from all of them at once: a tile joins
## whichever capital can reach it for the least travel effort. The flood itself
## lives in scripts/alternate_mode/region_growth.gd, which cultures share — all
## this script decides is where the seeds come from.
##
## The fill is deterministic, so it is recomputed on load rather than saved.
## Only `faction` — the one thing play changes — goes into the save file, keyed
## by province id.
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
const Growth = preload("res://scripts/alternate_mode/region_growth.gd")

## Returned by province_at() for water, unpainted void, and land no capital
## could reach (an island with no settlement on it).
const NO_PROVINCE := Growth.NO_REGION

## Above the culture overlay — with both up, borders should be what you read.
const OVERLAY_Z := 100

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


func _ready() -> void:
	_overlay = Growth.make_overlay_sprite(OVERLAY_Z, overlay_visible_on_start)
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

	for i in capitals.size():
		provinces.append(_make_province(i, capitals[i]))
	var cost := Growth.build_cost_field(map, _origin, _w, _h)
	# Every capital pulls equally hard — hence the empty reach array.
	_ids = Growth.grow(capitals, PackedInt32Array(), cost, _origin, _w, _h)
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
	var counts := Growth.count_tiles(_ids, provinces.size())
	var claimed := 0
	for i in provinces.size():
		provinces[i].tile_count = counts[i]
		claimed += counts[i]
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

## TextGenerator profile consulted before the head/tail table below, for land
## whose culture names no profile of its own.
const NAME_PROFILE := "place_name"

## Named from its capital's coordinates, so a province keeps its name for as
## long as its capital stays put, with nothing stored anywhere. The people
## living around the capital decide which name list it is drawn from, so a
## province in the Hiberno homeland reads differently from one in the south.
##
## The Markov chain is the real generator; the head/tail table is kept as a
## fallback for when the profile is missing (its models are content, and
## content can be absent).
func _generated_name(capital: Vector2i) -> String:
	var profile := _place_name_profile(capital)
	if TextGenerator.has_profile(profile):
		var generated = TextGenerator.generate(profile, TextGenerator.seed_from(capital))
		if not generated.is_empty():
			return generated
	# Same mixing constants as main_game._deterministic_seed.
	var hash_value := absi((capital.x * 73856093) ^ (capital.y * 19349663))
	var head: String = NAME_HEADS[hash_value % NAME_HEADS.size()]
	var tail: String = NAME_TAILS[(hash_value / NAME_HEADS.size()) % NAME_TAILS.size()]
	return head + tail


## Which name list the people at `tile` draw place names from. Falls back to the
## generic profile where no culture reached, and where the map has no culture
## node at all.
func _place_name_profile(tile: Vector2i) -> String:
	var cultures = _world_map.cultures if _world_map else null
	if cultures == null:
		return NAME_PROFILE
	return Culture.profile_for(cultures.culture_for_tile(tile), "place")


## Hues walked by the golden ratio, which spreads any number of neighbouring
## ids as far apart on the colour wheel as they can get.
func _generated_color(id: int) -> Color:
	return Growth.generated_color(id)


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
	return province.ruling_faction if province else ""


# ═══════════════════════════════════════════════════════════════════════
#  OWNERSHIP  (the only part play changes, and so the only part saved)
# ═══════════════════════════════════════════════════════════════════════

func set_faction(id: int, faction: String) -> void:
	var province := get_province(id)
	if province:
		province.ruling_faction = faction


## Snapshot for the save file: province id (as a String key, because that is
## what survives resource serialisation) → faction.
func ownership_dict() -> Dictionary:
	var out: Dictionary = {}
	for province in provinces:
		out[str(province.id)] = province.ruling_faction
	return out


func apply_ownership(data: Dictionary) -> void:
	for key: String in data:
		var province := get_province(int(key))
		if province:
			province.ruling_faction = str(data[key])


# ═══════════════════════════════════════════════════════════════════════
#  POLITICAL MAP OVERLAY
# ═══════════════════════════════════════════════════════════════════════

## Repaint the overlay from the current provinces.
func refresh_overlay() -> void:
	if _overlay == null or _ids.is_empty():
		return
	var colors := PackedColorArray()
	for province in provinces:
		colors.append(province.color)
	Growth.paint_overlay(_overlay, _ids, _w, _h, colors,
		_world_map.bounds_px(), overlay_alpha, border_alpha)


func is_overlay_visible() -> bool:
	return _overlay != null and _overlay.visible


func set_overlay_visible(value: bool) -> void:
	if _overlay:
		_overlay.visible = value


## Flip the political map and report the new state, so the caller can say so.
func toggle_overlay() -> bool:
	set_overlay_visible(not is_overlay_visible())
	return is_overlay_visible()
