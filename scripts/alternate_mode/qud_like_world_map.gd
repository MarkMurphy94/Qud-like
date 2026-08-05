extends Node2D
## Overworld map for the stripped-back "Qud-like" mode.
##
## Everything is read straight off the TileMapLayers through Godot's own
## TileMapLayer API — there is no mirrored 2D array of tile data to keep in
## sync (that was the main source of drift in the old OverworldMap).
##
## Tile semantics come from the shared row/column bands in
## resources/tileset_layout.gd. Both atlas sheets used here
## ("The Roguelike 1-15-1.png" and "overworld_roguelike_merged.png") are the
## same 109-column grid, so one band table resolves tiles from either source.

const Layout := preload("res://resources/tileset_layout.gd")

@onready var base: TileMapLayer = $base
@onready var land_features: TileMapLayer = $land_features
@onready var forests: TileMapLayer = $forests
@onready var mountains: TileMapLayer = $mountains
@onready var locations: TileMapLayer = $locations
## Political division of the map into faction territory. Grown from the
## settlement icons on `locations` — see scripts/alternate_mode/province_map.gd.
## Untyped like the other cross-script references in this project, so the map
## still loads if the node is missing or its script has not been scanned yet.
@onready var provinces = get_node_or_null("provinces")

## Tile categories that block movement when painted on the base layer.
const BLOCKING_BASE_CATEGORIES: Array[String] = ["liquid"]

## Painted extent of the whole map, in tiles. Set in _ready().
var bounds: Rect2i = Rect2i()

## Index of the tileset's "category" custom-data layer, or -1 when the tileset
## has not been stamped yet (see scripts/tools/stamp_roguelike_metadata.gd).
## Looked up once because TileData.get_custom_data() errors on unknown names.
var _category_layer: int = -1


func _ready() -> void:
	bounds = _compute_bounds()
	var tile_set: TileSet = base.tile_set
	if tile_set:
		_category_layer = tile_set.get_custom_data_layer_by_name("category")
	# Provinces are grown from this map, so they can only be built once the
	# bounds and the category lookup above are in place.
	if provinces:
		provinces.build(self)


## Merge the used-rects of every layer so the bounds always cover what is
## actually painted, no matter where painting started.
func _compute_bounds() -> Rect2i:
	var rect := Rect2i()
	for layer: TileMapLayer in _all_layers():
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		rect = used if rect.size == Vector2i.ZERO else rect.merge(used)
	return rect


func _all_layers() -> Array[TileMapLayer]:
	return [base, land_features, forests, mountains, locations]


# ═══════════════════════════════════════════════════════════════════════
#  COORDINATES
# ═══════════════════════════════════════════════════════════════════════

## World position → tile. Delegates to TileMapLayer so the grid origin and
## cell size live in one place (the tileset) rather than being duplicated.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	return base.local_to_map(base.to_local(world_pos))


## Tile → world position at the tile's centre.
func tile_to_world(tile: Vector2i) -> Vector2:
	return base.to_global(base.map_to_local(tile))


## Painted extent in pixels — used to clamp the camera.
func bounds_px() -> Rect2:
	var cell: Vector2 = Vector2(base.tile_set.tile_size) if base.tile_set else Vector2(16, 16)
	return Rect2(Vector2(bounds.position) * cell, Vector2(bounds.size) * cell)


# ═══════════════════════════════════════════════════════════════════════
#  WALKABILITY
# ═══════════════════════════════════════════════════════════════════════

func is_in_bounds(tile: Vector2i) -> bool:
	return bounds.has_point(tile)


## Can something walk onto this tile? Terrain only — physics bodies (NPCs and
## the like) are the caller's problem, and CharacterBody2D.test_move() already
## answers that question for them.
func is_walkable(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	# Nothing painted on the base layer means off-map void, not open ground.
	if base.get_cell_source_id(tile) == -1:
		return false
	if category_at(base, tile) in BLOCKING_BASE_CATEGORIES:
		return false
	if mountains.get_cell_source_id(tile) != -1:
		return false
	return true


## Resolve a tile's category on the given layer. Prefers the tileset's stamped
## "category" custom data and falls back to the row bands in tileset_layout.gd,
## so walkability works whether or not the stamper has been run.
func category_at(layer: TileMapLayer, tile: Vector2i) -> String:
	var data: TileData = layer.get_cell_tile_data(tile)
	if data == null:
		return ""
	if _category_layer >= 0:
		var stamped: Variant = data.get_custom_data_by_layer_id(_category_layer)
		if stamped is String and stamped != "":
			return stamped
	var band: Dictionary = Layout.category_band_for_row(layer.get_cell_atlas_coords(tile).y)
	return band.get("category", "")


## The biome a tile's art is drawn for, as the lowercase name the band table
## uses ("temperate", "desert", "arctic", …). Empty when nothing painted here
## comes from the fantasy block, which leaves the local generator on its
## configured default.
##
## Biome is not a separate piece of data on the overworld — inside the
## medieval_fantasy block each column IS one biome (Layout.BIOME_COLUMNS), so
## painting a desert ground tile already says "desert" and there is nothing
## extra to stamp. The ground answers first because it is what the environment
## actually is; the overlays are consulted only when the ground is biome-neutral
## (open water, a non-fantasy theme), where a desert palm or dune still names
## the tile's environment.
func biome_at(tile: Vector2i) -> String:
	for layer: TileMapLayer in [base, land_features, forests, mountains]:
		if layer == null or layer.get_cell_source_id(tile) == -1:
			continue
		var coord: Vector2i = layer.get_cell_atlas_coords(tile)
		if Layout.theme_for_col(coord.x) != Layout.BIOME_THEME:
			continue
		var biome: String = Layout.BIOME_COLUMNS.get(coord.x, "")
		if biome != "":
			return biome
	return ""


# ═══════════════════════════════════════════════════════════════════════
#  QUERIES
# ═══════════════════════════════════════════════════════════════════════

## True when a settlement / point-of-interest marker sits on this tile.
func has_location(tile: Vector2i) -> bool:
	return locations.get_cell_source_id(tile) != -1


## Which province holds this tile (ProvinceMap.NO_PROVINCE for sea and void).
func province_at(tile: Vector2i) -> int:
	if provinces == null:
		return -1
	return int(provinces.province_at(tile))


## Land tile = painted base ground that is not liquid. Mountains and forests
## count as land; open water and unpainted void do not.
func is_land(tile: Vector2i) -> bool:
	if not is_in_bounds(tile):
		return false
	if base.get_cell_source_id(tile) == -1:
		return false
	return category_at(base, tile) not in BLOCKING_BASE_CATEGORIES


## Nearest walkable tile to `from`, searched outward in rings up to
## `max_radius`. Returns `from` unchanged if nothing walkable is in range —
## used to rescue a spawn point that lands in water or off the map.
func nearest_walkable(from: Vector2i, max_radius: int = 64) -> Vector2i:
	if is_walkable(from):
		return from
	for radius in range(1, max_radius + 1):
		var best := Vector2i.MAX
		var best_dist := INF
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				# Ring only — the interior was covered by a smaller radius.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := from + Vector2i(dx, dy)
				if not is_walkable(candidate):
					continue
				var dist := Vector2(candidate - from).length_squared()
				if dist < best_dist:
					best_dist = dist
					best = candidate
		if best != Vector2i.MAX:
			return best
	return from
