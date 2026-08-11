extends Node2D
class_name CultureMap

# region NOTES:
## Division of the overworld into cultures — the peoples who live on the land,
## as opposed to the factions who rule it (see province_map.gd).
##
## Cultures grow exactly the way provinces do, through the shared flood in
## region_growth.gd, with one deliberate difference: the seeds are not found on
## the map, they are authored. Every culture is a Culture .tres you wrote by
## hand, with its homeland set as `origin_tile`.
##
## That is the point. Provinces are an emergent consequence of where towns
## happen to be, so it is right that they generate themselves. A people is not
## emergent — you decide the Vareshi exist and come from the eastern marshes —
## but where they end up should still answer to the terrain, and the flood is
## what makes it do that.
##
## Culture borders have nothing to do with province borders. They cross freely,
## and a province holding two cultures is the normal, interesting case.
##
## USAGE
##   1. Make a .tres of resources/culture.gd, set `display_name` and
##      `origin_tile`, optionally `spread` and `color`.
##   2. Add it to this node's `culture_defs` array in the Inspector. Array order
##      assigns culture ids.
##   3. culture_at(tile) / culture_for_tile(tile) / culture_id_at(tile)
##      toggle_overlay()  — culture map on/off, bound to "toggle_cultures"
# endregion

const CultureDef := preload("res://resources/culture.gd")
const Growth = preload("res://scripts/alternate_mode/region_growth.gd")

const NO_CULTURE := Growth.NO_REGION

## Just under the province overlay, so turning both on reads as peoples washed
## under political borders rather than the other way round.
const OVERLAY_Z := 99

@export_group("Overlay")
@export_range(0.0, 1.0) var overlay_alpha: float = 0.30
@export_range(0.0, 1.0) var border_alpha: float = 0.85
@export var overlay_visible_on_start: bool = false

@export_group("Authoring")
@export var culture_defs: Array[Culture] = []

## Working copies of the authored .tres files, indexed by id, so build-time
## fields (`id`, `tile_count`) never write back to disk.
var cultures: Array[CultureDef] = []

## Untyped so the calls below resolve against qud_like_world_map's actual API
## rather than Node2D's.
var _world_map = null
var _overlay: Sprite2D = null

# Flat arrays rather than a Dictionary keyed by Vector2i: the flood touches
# every land tile four times over, and a packed array turns that inner loop
# from hashing into arithmetic.
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

## Called from qud_like_world_map._ready(); safe to call again after editing
## `culture_defs`.
func build(map) -> void:
	_world_map = map
	cultures.clear()
	_ids = PackedInt32Array()

	var bounds: Rect2i = map.bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_warning("[Cultures] World map has no painted extent — nothing to cover.")
		return
	_origin = bounds.position
	_w = bounds.size.x
	_h = bounds.size.y

	var started := Time.get_ticks_msec()
	var homelands := _collect_homelands()
	if homelands.is_empty():
		print("[Cultures] No cultures defined — culture map is empty.")
		return

	var reach := PackedInt32Array()
	for culture in cultures:
		reach.append(culture.spread)

	var cost := Growth.build_cost_field(map, _origin, _w, _h)
	_ids = Growth.grow(homelands, reach, cost, _origin, _w, _h)
	var claimed := _count_tiles()
	refresh_overlay()

	print("[Cultures] %d cultures over %d land tiles in %d ms"
		% [cultures.size(), claimed, Time.get_ticks_msec() - started])


## Fills `cultures` with validated working copies and returns their homelands,
## so ids, homelands and reach all stay in the same order.
func _collect_homelands() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for def: Resource in culture_defs:
		if def == null:
			continue
		if not (def is CultureDef):
			push_warning("[Cultures] '%s' is not a Culture resource — skipped." % def.resource_path)
			continue
		var culture := (def as CultureDef).duplicate() as CultureDef
		# A homeland in the sea would seed nothing and shift every later id, so
		# it is dropped here rather than quietly producing an empty culture.
		if not _world_map.is_land(culture.origin_tile):
			push_warning("[Cultures] '%s' has its origin_tile %s on water or off the map — skipped."
				% [culture.display_name, culture.origin_tile])
			continue
		culture.id = cultures.size()
		if culture.display_name == "":
			culture.display_name = "Culture %d" % culture.id
		if culture.culture_id == "":
			culture.culture_id = _slug(culture.display_name)
		# Cultures are drawn paler than provinces so the two overlays are told
		# apart at a glance.
		if culture.color == Color.WHITE:
			culture.color = Growth.generated_color(culture.id, 0.40, 1.0)
		cultures.append(culture)
		out.append(culture.origin_tile)
	return out


## "Vareshi Highlanders" → "vareshi_highlanders".
func _slug(text: String) -> String:
	var slug := ""
	for character in text.to_lower():
		if (character >= "a" and character <= "z") or character.is_valid_int():
			slug += character
		elif slug != "" and not slug.ends_with("_"):
			slug += "_"
	return slug.trim_suffix("_")


## Tally each culture's size, and report how much land was covered in total.
func _count_tiles() -> int:
	var counts := Growth.count_tiles(_ids, cultures.size())
	var claimed := 0
	for i in cultures.size():
		cultures[i].tile_count = counts[i]
		claimed += counts[i]
	return claimed


# ═══════════════════════════════════════════════════════════════════════
#  QUERIES
# ═══════════════════════════════════════════════════════════════════════

func _index(tile: Vector2i) -> int:
	return (tile.y - _origin.y) * _w + (tile.x - _origin.x)


func _in_grid(tile: Vector2i) -> bool:
	var x := tile.x - _origin.x
	var y := tile.y - _origin.y
	return x >= 0 and y >= 0 and x < _w and y < _h


## Which culture lives on this tile, or NO_CULTURE for sea, void and land no
## culture reached.
func culture_at(tile: Vector2i) -> int:
	if _ids.is_empty() or not _in_grid(tile):
		return NO_CULTURE
	return _ids[_index(tile)]


func get_culture(id: int) -> CultureDef:
	return cultures[id] if id >= 0 and id < cultures.size() else null


func culture_for_tile(tile: Vector2i) -> CultureDef:
	return get_culture(culture_at(tile))


## The string key content should branch on (name lists, architecture sets), or
## "" where nobody lives.
func culture_id_at(tile: Vector2i) -> String:
	var culture := culture_for_tile(tile)
	return culture.culture_id if culture else ""


func find_by_key(key: String) -> CultureDef:
	for culture in cultures:
		if culture.culture_id == key:
			return culture
	return null


# ══════════════════════════════════════════════════════════════════════
#  CULTURE MAP OVERLAY
# ══════════════════════════════════════════════════════════════════════

func refresh_overlay() -> void:
	if _overlay == null or _ids.is_empty():
		return
	var colors := PackedColorArray()
	for culture in cultures:
		colors.append(culture.color)
	Growth.paint_overlay(_overlay, _ids, _w, _h, colors,
		_world_map.bounds_px(), overlay_alpha, border_alpha)


func is_overlay_visible() -> bool:
	return _overlay != null and _overlay.visible


func set_overlay_visible(value: bool) -> void:
	if _overlay:
		_overlay.visible = value


## Flip the culture map and report the new state, so the caller can say so.
func toggle_overlay() -> bool:
	set_overlay_visible(not is_overlay_visible())
	return is_overlay_visible()
