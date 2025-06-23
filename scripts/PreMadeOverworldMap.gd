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
	GROUND = 0, # Base terrain layer
	MOUNTAINS = 1, # Mountains layer
	SETTLEMENTS = 2, # Geography layer for settlements
}

const GEOGRAPHY_TILES = {
	"MOUNTAIN": Vector2i(9, 14), # Mountain tile coordinates
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
const TILE_SIZE = 16 # Size of each tile in pixels
const WIDTH = 2096.0 / TILE_SIZE
const HEIGHT = 1296.0 / TILE_SIZE

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
			var ground_data = tilemap.get_cell_tile_data(Layer.GROUND, pos)
			if ground_data != null:
				# Get terrain from terrain set first
				if ground_data.terrain_set >= 0:
					terrain = get_terrain_from_terrain_set(ground_data.terrain)
				else:
					# Fallback to checking tile ID if no terrain set
					terrain = get_terrain_from_id(ground_data.terrain)
			
			# Check geography layer (3) for mountains
			var geo_data = tilemap.get_cell_tile_data(Layer.MOUNTAINS, pos)
			if geo_data != null:
				var atlas_coords = tilemap.get_cell_atlas_coords(Layer.MOUNTAINS, pos)
				if atlas_coords == GEOGRAPHY_TILES.MOUNTAIN: # Mountain tile coordinates
					terrain = Terrain.MOUNTAIN
			
			# Check settlements layer (2)
			var settlement_data = tilemap.get_cell_tile_data(Layer.SETTLEMENTS, pos)
			if settlement_data != null:
				var atlas_coords = tilemap.get_cell_atlas_coords(Layer.SETTLEMENTS, pos)
				settlement = get_settlement_from_coords(atlas_coords)
			
			map_data[y][x] = CustomTileData.new(terrain, settlement)

# New function to handle terrain sets
func get_terrain_from_terrain_set(terrain_id: int) -> Terrain:
	match terrain_id:
		0: return Terrain.GRASS # Grass terrain set
		1: return Terrain.WATER # Water terrain set
		_: return Terrain.NONE

func get_terrain_from_id(terrain_id: int) -> Terrain:
	# This is for non-terrain-set tiles
	if terrain_id < 0:
		return Terrain.NONE
		
	# These are tile-based terrain IDs, only used if terrain sets are not available
	match terrain_id:
		0: return Terrain.GRASS
		1: return Terrain.WATER
		2: return Terrain.MOUNTAIN
		_: return Terrain.NONE

func get_settlement_from_coords(coords: Vector2i) -> Settlement: # return type changed to Settlement from int
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

func get_settlement_type(pos: Vector2i) -> int:
	if not is_valid_position(pos):
		return Settlement.NONE
	return map_data[pos.y][pos.x].settlement

func get_settlement_from_seed(pos: Vector2i):
	var settlement_seed = null
	for town in GlobalGameState.settlements:
		if GlobalGameState.settlements[town]["pos"] == pos:
			settlement_seed = GlobalGameState.settlements[town]["seed"]
			break
	if settlement_seed:
		print("Identified settlement from settlement_seed: ", settlement_seed)
		return settlement_seed
	else:
		print("No settlement found for settlement_seed: ", settlement_seed)

func debug_print_tile(pos: Vector2i) -> void:
	if not is_valid_position(pos):
		print("Invalid position: ", pos)
		return
	
	var tile = map_data[pos.y][pos.x]
	print("Position: ", pos)
	
	# Print terrain info with layer source
	var terrain_str = Terrain.keys()[tile.terrain]
	var terrain_source = ""
	
	# Check which layer the terrain comes from
	if tilemap.get_cell_tile_data(Layer.MOUNTAINS, pos) != null:
		terrain_source = " (from mountains layer)"
	elif tilemap.get_cell_tile_data(Layer.GROUND, pos) != null:
		var ground_data = tilemap.get_cell_tile_data(Layer.GROUND, pos)
		terrain_source = " (from ground layer, terrain set: " + str(ground_data.terrain_set) + ")"
	
	print("Terrain: ", terrain_str, terrain_source)
	print("Settlement: ", Settlement.keys()[tile.settlement])
	print("Walkable: ", tile.is_walkable, " (blocked by: ", "water" if tile.terrain == Terrain.WATER else "mountain" if tile.terrain == Terrain.MOUNTAIN else "none", ")")
