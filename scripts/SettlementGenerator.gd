extends Node2D

# Types of settlements
enum SettlementType {TOWN, CITY, CASTLE}
# Types of buildings
enum BuildingType {HOUSE, TAVERN, SHOP, MANOR}
@onready var tilemap = $TileMap

# Tile definitions for building elements
const TILES = {
	"FLOOR_WOOD": Vector2i(33, 14),
	"FLOOR_STONE": Vector2i(33, 9),
	"WALL_H": Vector2i(6, 43), # Horizontal wall
	"WALL_V": Vector2i(4, 43), # Vertical wall
	"CORNER_NW": Vector2i(5, 43),
	"CORNER_NE": Vector2i(7, 43),
	"CORNER_SW": Vector2i(5, 44),
	"CORNER_SE": Vector2i(7, 44),
	"DOOR": Vector2i(5, 45),
	"GROUND": Vector2i(4, 5) # Default ground tile
}

# Building templates
const BUILDING_TEMPLATES = {
	BuildingType.HOUSE: {
		"min_size": Vector2i(4, 4),
		"max_size": Vector2i(6, 6),
		"floor": "FLOOR_WOOD",
		"spacing": 1 # Minimum space between houses
	},
	BuildingType.TAVERN: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(8, 8),
		"floor": "FLOOR_WOOD",
		"spacing": 2 # More space for taverns
	},
	BuildingType.SHOP: {
		"min_size": Vector2i(5, 5),
		"max_size": Vector2i(7, 7),
		"floor": "FLOOR_STONE",
		"spacing": 2
	},
	BuildingType.MANOR: {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"floor": "FLOOR_STONE",
		"spacing": 3 # Manors need more space
	}
}

const WIDTH = 40 # Local area is more detailed, so larger
const HEIGHT = 40
const TILE_SIZE = 16 # Size of each tile in pixels
const TILE_SOURCE_ID = 3 # The ID of the TileSetAtlasSource in the tileset

func _ready() -> void:
	if not tilemap:
		push_error("TileMap node not found!")
		return
	
	# Generate a settlement of type TOWN for demonstration
	var rng = RandomNumberGenerator.new()
	rng.seed = randi() # Random seed for this example
	generate_settlement(SettlementType.TOWN, rng)

func generate_settlement(settlement_type: int, rng: RandomNumberGenerator) -> void:
	var area_size = Vector2i(40, 40)
	var building_counts = {
		SettlementType.TOWN: {
			BuildingType.HOUSE: rng.randi_range(6, 10),
			BuildingType.TAVERN: 1,
			BuildingType.SHOP: rng.randi_range(1, 2),
			BuildingType.MANOR: 0
		},
		SettlementType.CITY: {
			BuildingType.HOUSE: rng.randi_range(12, 20),
			BuildingType.TAVERN: rng.randi_range(2, 3),
			BuildingType.SHOP: rng.randi_range(3, 5),
			BuildingType.MANOR: rng.randi_range(1, 2)
		},
		SettlementType.CASTLE: {
			BuildingType.HOUSE: rng.randi_range(2, 4),
			BuildingType.TAVERN: 0,
			BuildingType.SHOP: 0,
			BuildingType.MANOR: 1
		}
	}

	# Clear and initialize with ground tiles
	tilemap.clear()
	for y in area_size.y:
		for x in area_size.x:
			tilemap.set_cell(0, Vector2i(x, y), TILE_SOURCE_ID, TILES["GROUND"])

	# Create occupation grid
	var occupation_grid = []
	for y in area_size.y:
		occupation_grid.append([])
		for x in area_size.x:
			occupation_grid[y].append(false)

	var placed_buildings = []
	# Place buildings in order: Manor first, then Taverns, Shops, and finally Houses
	var building_order = [BuildingType.MANOR, BuildingType.TAVERN, BuildingType.SHOP, BuildingType.HOUSE]
	
	for building_type in building_order:
		var count = building_counts[settlement_type][building_type]
		for _i in count:
			var size = Vector2i(
				rng.randi_range(BUILDING_TEMPLATES[building_type]["min_size"].x, BUILDING_TEMPLATES[building_type]["max_size"].x),
				rng.randi_range(BUILDING_TEMPLATES[building_type]["min_size"].y, BUILDING_TEMPLATES[building_type]["max_size"].y)
			)
			var pos = find_valid_building_position(area_size, size, occupation_grid, rng, building_type)
			if pos.x != -1: # Valid position found
				place_building(pos, size, building_type)
				mark_occupied(occupation_grid, pos, size)
				placed_buildings.append({"type": building_type, "pos": pos, "size": size})

	# Optionally: add roads, walls, etc.

func find_valid_building_position(area_size: Vector2i, size: Vector2i, occupation_grid: Array, rng: RandomNumberGenerator, building_type: int) -> Vector2i:
	var template = BUILDING_TEMPLATES[building_type]
	var spacing = template["spacing"]
	var attempts = 0
	
	while attempts < 100:
		var x = rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = rng.randi_range(spacing, area_size.y - size.y - spacing)
		var valid = true
		
		# Check the building area plus spacing
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x = x + dx
				var check_y = y + dy
				
				# Skip checks outside the map
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
					
				# Check if space is already occupied
				if occupation_grid[check_y][check_x]:
					valid = false
					break
					
			if not valid:
				break
				
		if valid:
			return Vector2i(x, y)
			
		attempts += 1
		
	return Vector2i(-1, -1) # Return invalid position if no space found

func mark_occupied(occupation_grid: Array, pos: Vector2i, size: Vector2i) -> void:
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			occupation_grid[y][x] = true

func place_building(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var template = BUILDING_TEMPLATES[building_type]
	
	# Place floor
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemap.set_cell(0, Vector2i(x, y), TILE_SOURCE_ID, TILES[template["floor"]])
	
	# Place walls
	for x in range(pos.x, pos.x + size.x):
		# Top and bottom walls
		tilemap.set_cell(1, Vector2i(x, pos.y), TILE_SOURCE_ID, TILES["WALL_H"])
		tilemap.set_cell(1, Vector2i(x, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["WALL_H"])
	
	for y in range(pos.y, pos.y + size.y):
		# Left and right walls
		tilemap.set_cell(1, Vector2i(pos.x, y), TILE_SOURCE_ID, TILES["WALL_V"])
		tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, y), TILE_SOURCE_ID, TILES["WALL_V"])
	
	# Place corners
	tilemap.set_cell(1, pos, TILE_SOURCE_ID, TILES["CORNER_NW"])
	tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, pos.y), TILE_SOURCE_ID, TILES["CORNER_NE"])
	tilemap.set_cell(1, Vector2i(pos.x, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["CORNER_SW"])
	tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["CORNER_SE"])
	
	# Place door on the south wall
	var door_x = pos.x + size.x / 2
	var door_y = pos.y + size.y - 1
	tilemap.set_cell(1, Vector2i(door_x, door_y), TILE_SOURCE_ID, TILES["DOOR"])
