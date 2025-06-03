extends Node2D

enum Terrain {
	NONE = -1,
	WATER, # Deep and shallow water combined
	BEACH, # Coastal and sand areas
	GRASS, # Plains and grasslands
	MOUNTAIN # Hills and peaks
}

enum Settlement {
	NONE = -1,
	TOWN,
	CITY,
	CASTLE
}

class CustomTileData:
	var terrain: int = Terrain.NONE
	var settlement: int = Settlement.NONE
	var is_walkable: bool = true
	
	func _init(t: int, s: int = Settlement.NONE):
		terrain = t
		settlement = s
		is_walkable = t != Terrain.WATER

@onready var tilemap: TileMap = $TileMap
var map_data: Array[Array] = []
const WIDTH = 80
const HEIGHT = 60
const TILE_SIZE = 16 # Size of each tile in pixels

func _ready() -> void:
	if not tilemap:
		push_error("TileMap node not found!")
		return
	
	initialize_map_data()

# Initialize the map data from the TileMap
func initialize_map_data() -> void:
	map_data.clear()
	
	# Initialize 2D array
	for y in HEIGHT:
		var row: Array = []
		for x in WIDTH:
			row.append(null)
		map_data.append(row)
	
	# Read data from tilemap
	for y in HEIGHT:
		for x in WIDTH:
			var pos = Vector2i(x, y)
			var tile_data = tilemap.get_cell_tile_data(0, pos)
			if tile_data == null:
				map_data[y][x] = CustomTileData.new(Terrain.NONE)
				continue
			
			# Get terrain from tile's terrain set
			var terrain_id = tile_data.terrain
			var terrain = get_terrain_from_id(terrain_id)
			
			# Check for settlements (these are in atlas coordinates)
			var atlas_coords = tilemap.get_cell_atlas_coords(0, pos)
			var settlement = get_settlement_from_coords(atlas_coords)
			
			map_data[y][x] = CustomTileData.new(terrain, settlement)

func get_terrain_from_id(terrain_id: int) -> int:
	match terrain_id:
		0: return Terrain.GRASS
		1: return Terrain.WATER
		2: return Terrain.BEACH
		3: return Terrain.MOUNTAIN
		_: return Terrain.NONE

func get_settlement_from_coords(coords: Vector2i) -> int:
	# These coords should match your tileset
	match coords:
		Vector2i(4, 17): return Settlement.TOWN
		Vector2i(6, 18): return Settlement.CITY
		Vector2i(5, 18): return Settlement.CASTLE
		_: return Settlement.NONE

func world_to_map(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / TILE_SIZE)

func map_to_world(map_pos: Vector2i) -> Vector2:
	return Vector2(map_pos * TILE_SIZE)

# Public methods for querying map data

func get_tile_data(pos: Vector2i) -> CustomTileData:
	if is_valid_position(pos):
		return map_data[pos.y][pos.x]
	return CustomTileData.new(Terrain.NONE)

func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func is_walkable(pos: Vector2i) -> bool:
	if not is_valid_position(pos):
		return false
	return map_data[pos.y][pos.x].is_walkable

func has_settlement(pos: Vector2i) -> bool:
	if not is_valid_position(pos):
		return false
	return map_data[pos.y][pos.x].settlement != Settlement.NONE

func get_terrain(pos: Vector2i) -> int:
	if not is_valid_position(pos):
		return Terrain.NONE
	return map_data[pos.y][pos.x].terrain

func get_settlement(pos: Vector2i) -> int:
	if not is_valid_position(pos):
		return Settlement.NONE
	return map_data[pos.y][pos.x].settlement
