extends Node2D

enum Terrain {
	NONE = -1,
	WATER, # Deep and shallow water combined
	GRASS, # Plains and grasslands
	MOUNTAIN # Hills and peaks
}

enum Settlement {
	NONE = -1,
	TOWN,
	CITY,
	CASTLE
}

enum Layer {
	BASE = 0, # Ground + water terrain layer (terrain_set 0)
	LAND_FEATURES = 1, # Decorative ground overlays (sand, rocks, etc.)
	MOUNTAINS = 2, # Mountain prop overlay layer
	FORESTS = 3, # Tree group overlay layer
	LOCATIONS = 4, # Settlement/building icon layer
}

class CustomTileData:
	var terrain: int = Terrain.NONE
	var settlement: int = Settlement.NONE
	var is_walkable: bool = true
	var tile_position: Vector2i = Vector2i.ZERO
	var tile_coordinates: Vector2i = Vector2i.ZERO
	
	func _init(t: int, s: int = Settlement.NONE, p: Vector2i = Vector2i.ZERO):
		terrain = t
		settlement = s
		is_walkable = t != Terrain.WATER
		tile_position = p
		tile_coordinates = Vector2i(p / TILE_SIZE)
		
## Ground + water terrain (terrain_set 0: water/grasslandland/road/mountain).
## Mixes both land and water tiles, so terrain must be read via terrain_set,
## not by layer presence alone.
@onready var base: TileMapLayer = $base
## Decorative overlays on top of the base terrain (sand, rocks, etc.) - cosmetic only.
@onready var land_features: TileMapLayer = $land_features
## Mountain prop overlay - any tile placed here marks that position as impassable mountain.
@onready var mountains: TileMapLayer = $mountains
## Tree group overlay - cosmetic only, does not currently affect walkability.
@onready var forests: TileMapLayer = $forests
## Settlement/building icons - paired with settlements_list to resolve a Settlement type.
@onready var locations: TileMapLayer = $locations

@export var settlements_list: Dictionary[Vector2i, String]

var map_data: Array[Array] = []
const TILE_SIZE = 16 # Size of each tile in pixels
## Grid dimensions (in tiles), computed at runtime from the actual painted tile
## layers (see _compute_map_bounds). These used to be hardcoded from an old,
## unrelated reference image size (2096x1296) which no longer matches the
## current, much larger worldmap_tile_set_new-based map — that mismatch made
## is_valid_position()/is_walkable() reject most of the real map (and clamped
## the camera far away from the player), so they must be derived, not fixed.
var WIDTH: int = 0
var HEIGHT: int = 0

func _ready() -> void:
	# if not tilemap:
	# 	push_error("TileMap node not found!")
	# 	return
	_compute_map_bounds()
	initialize_map_data()

## Determine the full tile-space extent of the map by merging the used-rects
## of every layer, so WIDTH/HEIGHT always cover the actual painted content
## regardless of how large the map is or where painting started.
func _compute_map_bounds() -> void:
	var rect: Rect2i = base.get_used_rect()
	rect = rect.merge(land_features.get_used_rect())
	rect = rect.merge(mountains.get_used_rect())
	rect = rect.merge(forests.get_used_rect())
	rect = rect.merge(locations.get_used_rect())
	WIDTH = max(0, rect.end.x)
	HEIGHT = max(0, rect.end.y)

# Initialize the map data from the TileMap
func initialize_map_data() -> void:
	map_data.clear()
	
	# Initialize 2D array
	for y in HEIGHT:
		var row: Array = []
		for x in WIDTH:
			row.append(null)
		map_data.append(row)
	
	# Read data from tilemap layers
	for y in HEIGHT:
		for x in WIDTH:
			var tile_pos = Vector2i(x, y)
			var terrain = Terrain.NONE
			var settlement = Settlement.NONE
			
			# Base layer holds both land AND water tiles, painted with terrain_set 0
			# (0=water, 1=grasslandland, 2=road, 3=mountain). Water tiles are the only
			# ones that block movement (see CustomTileData.is_walkable).
			var base_data = base.get_cell_tile_data(tile_pos)
			if base_data != null and base_data.terrain_set >= 0:
				terrain = get_terrain_from_terrain_set(base_data.terrain)
			
			# Mountain prop layer overrides base terrain: any tile placed here marks
			# the position as impassable mountain, regardless of the base paint.
			if mountains.get_cell_tile_data(tile_pos) != null:
				terrain = Terrain.MOUNTAIN
			
			# Settlement/building icons live on the locations layer; resolve the
			# actual settlement type via the registered settlements_list name.
			if locations.get_cell_tile_data(tile_pos) != null:
				settlement = get_settlement_from_position(tile_pos)
			
			map_data[y][x] = CustomTileData.new(terrain, settlement)

# Maps base layer terrain_set 0 indices to the Terrain enum.
func get_terrain_from_terrain_set(terrain_id: int) -> Terrain:
	match terrain_id:
		0: return Terrain.WATER # "water" terrain
		1: return Terrain.GRASS # "grasslandland" terrain
		2: return Terrain.GRASS # "road" terrain (walkable ground)
		3: return Terrain.MOUNTAIN # "mountain" terrain
		_: return Terrain.NONE

# Resolves a Settlement type for a tile marked on the locations layer by looking up
# its registered name in settlements_list (e.g. "town_1", "city_2", "castle_1").
func get_settlement_from_position(tile_pos: Vector2i) -> Settlement:
	var settlement_name := settlement_at_tile(tile_pos)
	if settlement_name == "":
		return Settlement.NONE
	var lname := settlement_name.to_lower()
	if "castle" in lname:
		return Settlement.CASTLE
	if "city" in lname:
		return Settlement.CITY
	return Settlement.TOWN

func settlement_at_tile(tile_pos: Vector2i) -> String:
	for s in settlements_list:
		if s == tile_pos:
			return settlements_list[s]
	return ""

func world_to_map(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / TILE_SIZE)

func map_to_world(map_pos: Vector2i) -> Vector2:
	return Vector2(map_pos * TILE_SIZE)

# Public methods for querying map data

func get_tile_data(tile_pos: Vector2i) -> CustomTileData:
	if is_valid_position(tile_pos):
		return map_data[tile_pos.y][tile_pos.x]
	return CustomTileData.new(Terrain.NONE)

func is_valid_position(tile_pos: Vector2i) -> bool:
	return tile_pos.x >= 0 and tile_pos.x < WIDTH and tile_pos.y >= 0 and tile_pos.y < HEIGHT

func is_walkable(tile_pos: Vector2i) -> bool:
	if not is_valid_position(tile_pos):
		return false
	return map_data[tile_pos.y][tile_pos.x].is_walkable

func has_settlement(tile_pos: Vector2i) -> bool:
	debug_print_tile(tile_pos)
	if not is_valid_position(tile_pos):
		return false
	return map_data[tile_pos.y][tile_pos.x].settlement != Settlement.NONE

func get_terrain(tile_pos: Vector2i) -> int:
	if not is_valid_position(tile_pos):
		return Terrain.NONE
	return map_data[tile_pos.y][tile_pos.x].terrain

func get_settlement_type(tile_pos: Vector2i) -> int:
	if not is_valid_position(tile_pos):
		return Settlement.NONE
	return map_data[tile_pos.y][tile_pos.x].settlement

func debug_print_tile(tile_pos: Vector2i) -> void:
	if not is_valid_position(tile_pos):
		print("Invalid position: ", tile_pos)
		return
	
	var tile = map_data[tile_pos.y][tile_pos.x]
	print("Position: ", tile_pos)
	
	# Print terrain info with layer source
	var terrain_str = Terrain.keys()[tile.terrain]
	var terrain_source = ""
	
	# Check which layer the terrain comes from
	if mountains.get_cell_tile_data(tile_pos) != null:
		terrain_source = " (from mountains layer)"
	elif base.get_cell_tile_data(tile_pos) != null:
		var base_data = base.get_cell_tile_data(tile_pos)
		terrain_source = " (from base layer, terrain set: " + str(base_data.terrain_set) + ")"
	
	print("Terrain: ", terrain_str, terrain_source)
	print("Settlement: ", Settlement.keys()[tile.settlement])
	print("Walkable: ", tile.is_walkable, " (blocked by: ", "water" if tile.terrain == Terrain.WATER else "mountain" if tile.terrain == Terrain.MOUNTAIN else "none", ")")
