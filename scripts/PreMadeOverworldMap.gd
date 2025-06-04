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
	
	# Read data from tilemap layers
	for y in HEIGHT:
		for x in WIDTH:
			var pos = Vector2i(x, y)
			var terrain = Terrain.NONE
			var settlement = Settlement.NONE
			
			# Check ground layer (0) for base terrain
			var ground_data = tilemap.get_cell_tile_data(0, pos)
			if ground_data != null:
				terrain = get_terrain_from_id(ground_data.terrain)
			
			# Check geography layer (3) for mountains
			var geo_data = tilemap.get_cell_tile_data(3, pos)
			if geo_data != null:
				# If there's a mountain tile, override the terrain
				var atlas_coords = tilemap.get_cell_atlas_coords(3, pos)
				if atlas_coords == Vector2i(4, 0): # Mountain tile coordinates
					terrain = Terrain.MOUNTAIN
			
			# Check settlements layer (2)
			var settlement_data = tilemap.get_cell_tile_data(2, pos)
			if settlement_data != null:
				var atlas_coords = tilemap.get_cell_atlas_coords(2, pos)
				settlement = get_settlement_from_coords(atlas_coords)
			
			map_data[y][x] = CustomTileData.new(terrain, settlement)

func get_terrain_from_id(terrain_id: int) -> Terrain:
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
	debug_print_tile(pos)
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

func debug_print_tile(pos: Vector2i) -> void:
	if not is_valid_position(pos):
		print("Invalid position: ", pos)
		return
	
	var tile = map_data[pos.y][pos.x]
	print("Position: ", pos)
	print("Terrain: ", Terrain.keys()[tile.terrain])
	print("Settlement: ", Settlement.keys()[tile.settlement])
	print("Walkable: ", tile.is_walkable)
