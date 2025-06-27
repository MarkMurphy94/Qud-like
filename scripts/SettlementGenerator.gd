@tool
extends Node2D

const BUILDINGTYPE = GlobalGameState.BuildingType
const SETTLEMENTTYPE = GlobalGameState.SettlementType

var BuildingTypeStrings = {
	BUILDINGTYPE.HOUSE: "house",
	BUILDINGTYPE.TAVERN: "tavern",
	BUILDINGTYPE.SHOP: "shop",
	BUILDINGTYPE.MANOR: "manor",
	BUILDINGTYPE.BARRACKS: "barracks",
	BUILDINGTYPE.CHURCH: "church",
	BUILDINGTYPE.KEEP: "keep"
}
@onready var tilemaps = {
	"GROUND": $ground,
	"INTERIOR_FLOOR": $interior_floor,
	"WALLS": $walls,
	"FURNITURE": $furniture,
	"ITEMS": $items,
	"DOORS": $doors,
	"ROOF": $roof
}

# Layer definitions for proper organization
const LAYERS = {
	"GROUND": 0,
	"INTERIOR_FLOOR": 1,
	"WALLS": 2,
	"FURNITURE": 3,
	"ITEMS": 4,
	"DOORS": 5,
	"ROOF": 6
}

# Terrain sets for better tile transitions
const TERRAINS = {
	"stone": 0, # Stone paths and plazas
	"grass": 1, # Natural grass areas
	"dirt": 2, # Dirt paths and yards
	"water": 3,
	"wheat_field": 4,
}

# Default terrain type for each settlement type
const SETTLEMENT_TERRAIN = {
	SETTLEMENTTYPE.TOWN: {
		"primary": "grass",
		"secondary": "grass",
		"paths": "dirt"
	},
	SETTLEMENTTYPE.CITY: {
		"primary": "grass",
		"secondary": "dirt",
		"paths": "stone"
	},
	SETTLEMENTTYPE.CASTLE: {
		"primary": "stone",
		"secondary": "dirt",
		"paths": "stone"
	}
}

# Terrain cells for batch processing
var terrain_cells = {
	"stone": [],
	"grass": [],
	"dirt": []
}

# Road generation parameters
const ROAD_WIDTH = 2
const PLAZA_MIN_SIZE = 4
const PLAZA_MAX_SIZE = 8
const PLAZA_DISTANCE_THRESHOLD = 10 # Maximum distance between buildings to consider a plaza

# Tile definitions for building elements
const STRUCTURE_TILES = {
	"FLOOR_WOOD": Vector2i(67, 10),
	"FLOOR_STONE": Vector2i(7, 10),
	"FLOOR_TILE": Vector2i(93, 10),
	"GROUND": Vector2i(0, 0), # Base ground tile
	"STONE_WALL_H": Vector2i(6, 19), # Horizontal wall
	"STONE_WALL_H_INT": Vector2i(6, 19), # Interior horizontal wall
	"STONE_WALL_V_LEFT": Vector2i(9, 20), # Left-facing vertical wall
	"STONE_WALL_V_RIGHT": Vector2i(4, 19), # Right-facing vertical wall
	"STONE_WALL_CORNER_NW": Vector2i(5, 19),
	"STONE_WALL_CORNER_NE": Vector2i(7, 19),
	"STONE_WALL_CORNER_SW": Vector2i(5, 20),
	"STONE_WALL_CORNER_SE": Vector2i(7, 20),
	"RED_BRICK_WALL_H": Vector2i(31, 20), # Horizontal wall
	"RED_BRICK_WALL_H_INT": Vector2i(31, 20), # Interior horizontal wall
	"RED_BRICK_WALL_V_LEFT": Vector2i(28, 20), # Left-facing vertical wall
	"RED_BRICK_WALL_V_RIGHT": Vector2i(28, 19), # Right-facing vertical wall
	"RED_BRICK_WALL_CORNER_NW": Vector2i(30, 19),
	"RED_BRICK_WALL_CORNER_NE": Vector2i(32, 19),
	"RED_BRICK_WALL_CORNER_SW": Vector2i(30, 20),
	"RED_BRICK_WALL_CORNER_SE": Vector2i(32, 20),
	"DOOR": Vector2i(5, 21),
	"FANCY_DOOR": Vector2i(5, 21),
	"ROOF_RED": Vector2i(69, 10),
	"ROOF_DARK_RED_TRIM": Vector2i(32, 18),
	"ROOF_BLACK": Vector2i(65, 10),
	"ROOF_DARK_GREEN": Vector2i(92, 10),
	"ROOF_DARK_BLUE": Vector2i(91, 10),
	"WELL_RED_ROOF": Vector2i(6, 22),
	# "WALL_H_INT_FIREPLACE": Vector2i(6, 19), # Horizontal wall
}

const FURNITURE_TILES = {
	"CHAIR": Vector2i(6, 24), # Placeholder for chair tile
	"TABLE": Vector2i(7, 24), # Placeholder for table tile
	"BARREL_OPEN": Vector2i(66, 22), # Placeholder for shelf tile
	"BARREL_CLOSED": Vector2i(65, 22), # Placeholder for shelf tile
	"BED": Vector2i(88, 24), # Placeholder for bed tile
	"SHELF": Vector2i(4, 24), # Placeholder for shelf tile
	"CABINET": Vector2i(5, 24), # Placeholder for shelf tile
	"CHEST_YELLOW": Vector2i(8, 24), # Placeholder for shelf tile
	"CHEST_YELLOW_OPEN": Vector2i(9, 24), # Placeholder for shelf tile
	"CHEST_BLUE": Vector2i(10, 24), # Placeholder for shelf tile
	"CHEST_BLUE_OPEN": Vector2i(11, 24), # Placeholder for shelf tile
	"CHEST_GOLD_TRIM_CLOSED": Vector2i(65, 24), # Placeholder for shelf tile
	# "CHEST_GOLD_TRIM_OPEN_TREASURE": Vector2i(10, 21), # Placeholder for shelf tile
	"POTTED_PLANT_GREY": Vector2i(12, 24), # Placeholder for shelf tile
	"POTTED_PLANT_DARK_RED": Vector2i(16, 24), # Placeholder for shelf tile
	"POT_GREY": Vector2i(13, 24), # Placeholder for shelf tile
	# "POT_DARK_RED": Vector2i(10, 21), # Placeholder for shelf tile
	"VASE_GREY_TOP": Vector2i(18, 24), # Placeholder for shelf tile
	"VASE_HANDLES": Vector2i(19, 24), # Placeholder for shelf tile

}

const ITEM_TILES = {
	"STEW_ORANGE": Vector2i(72, 39), # Placeholder for shelf tile
	"STEW_ORANGE_CHICKEN": Vector2i(75, 39), # Placeholder for shelf tile
	"STEW_GREEN": Vector2i(10, 21), # Placeholder for shelf tile
	"STEW_BLUE_CHICKEN": Vector2i(74, 39), # Placeholder for shelf tile
	"BANANA_BUNCH": Vector2i(69, 39), # Placeholder for shelf tile
	"POTATOES": Vector2i(68, 39), # Placeholder for shelf tile
	"BEER_STEIN": Vector2i(67, 39), # Placeholder for shelf tile
	"POTION_RED": Vector2i(65, 39), # Placeholder for shelf tile
	"POTION_GREEN": Vector2i(66, 39), # Placeholder for shelf tile
	"POTION_BLACK": Vector2i(59, 36), # Placeholder for shelf tile
	"POTION_PINK": Vector2i(58, 36), # Placeholder for shelf tile
	"POTION_YELLOW": Vector2i(57, 36), # Placeholder for shelf tile
	"SCROLL_BLANK": Vector2i(79, 36), # Placeholder for shelf tile
	"SCROLL_WRITTEN": Vector2i(80, 36), # Placeholder for shelf tile
	"SMALL_STATUE": Vector2i(16, 26), # Placeholder for shelf tile
}

const BUILDING_TEMPLATES = {
	# TODO: add different wall type entries for different structures
	BUILDINGTYPE.HOUSE: {
		"min_size": Vector2i(4, 4),
		"max_size": Vector2i(6, 6),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_BLACK",
		"walls": {
			"left": "STONE_WALL_V_LEFT",
			"right": "STONE_WALL_V_RIGHT",
			"top": "STONE_WALL_H",
			"bottom": "STONE_WALL_H",
			"corner_nw": "STONE_WALL_CORNER_NW",
			"corner_ne": "STONE_WALL_CORNER_NE",
			"corner_sw": "STONE_WALL_CORNER_SW",
			"corner_se": "STONE_WALL_CORNER_SE",
		},
		"ground": "DIRT", # Houses tend to have dirt yards
		"spacing": 1 # Minimum space between houses
	},
	BUILDINGTYPE.TAVERN: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(8, 8),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_DARK_BLUE",
		"walls": {
			"left": "STONE_WALL_V_LEFT",
			"right": "STONE_WALL_V_RIGHT",
			"top": "STONE_WALL_H",
			"bottom": "STONE_WALL_H",
			"corner_nw": "STONE_WALL_CORNER_NW",
			"corner_ne": "STONE_WALL_CORNER_NE",
			"corner_sw": "STONE_WALL_CORNER_SW",
			"corner_se": "STONE_WALL_CORNER_SE",
		},
		"ground": "STONE", # Stone paths around taverns
		"spacing": 2 # More space for taverns
	},
	BUILDINGTYPE.SHOP: {
		"min_size": Vector2i(5, 5),
		"max_size": Vector2i(7, 7),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_DARK_GREEN",
		"walls": {
			"left": "STONE_WALL_V_LEFT",
			"right": "STONE_WALL_V_RIGHT",
			"top": "STONE_WALL_H",
			"bottom": "STONE_WALL_H",
			"corner_nw": "STONE_WALL_CORNER_NW",
			"corner_ne": "STONE_WALL_CORNER_NE",
			"corner_sw": "STONE_WALL_CORNER_SW",
			"corner_se": "STONE_WALL_CORNER_SE",
		},
		"ground": "STONE", # Stone paths around shops
		"spacing": 2
	},
	BUILDINGTYPE.MANOR: {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"floor": "FLOOR_TILE",
		"roof": "ROOF_RED",
		"walls": {
			"left": "RED_BRICK_WALL_V_LEFT",
			"right": "RED_BRICK_WALL_V_RIGHT",
			"top": "RED_BRICK_WALL_H",
			"bottom": "RED_BRICK_WALL_H",
			"corner_nw": "RED_BRICK_WALL_CORNER_NW",
			"corner_ne": "RED_BRICK_WALL_CORNER_NE",
			"corner_sw": "RED_BRICK_WALL_CORNER_SW",
			"corner_se": "RED_BRICK_WALL_CORNER_SE",
		},
		"ground": "STONE", # Stone surroundings for manors
		"spacing": 3 # Manors need more space
	},
	BUILDINGTYPE.BARRACKS: {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_RED",
		"ground": "STONE",
		"spacing": 3
	},
	BUILDINGTYPE.CHURCH: {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_RED",
		"ground": "GRASS",
		"spacing": 3
	}
}

# Add these new constants after the existing ITEM_TILES definition
const ROOM_ZONES = {
	"SLEEPING": 0,
	"DINING": 1,
	"STORAGE": 2,
	"WORKSHOP": 3
}

const BUILDING_LAYOUTS = {
	BUILDINGTYPE.HOUSE: {
		"zones": ["SLEEPING", "DINING", "STORAGE"],
		"furniture": {
			"SLEEPING": ["BED", "SHELF"],
			"DINING": ["TABLE", "CHAIR"],
			"STORAGE": ["SHELF", "CHEST_YELLOW", "BARREL_CLOSED"]
		},
		"items": {
			"SLEEPING": [],
			"DINING": ["STEW_ORANGE", "BEER_STEIN", "POTATOES"],
			"STORAGE": []
		}
	},
	BUILDINGTYPE.TAVERN: {
		"zones": ["DINING", "STORAGE", "SLEEPING"],
		"furniture": {
			"DINING": ["TABLE", "CHAIR", "SHELF"],
			"STORAGE": ["BARREL_CLOSED", "SHELF"],
			"SLEEPING": ["BED"]
		},
		"items": {
			"DINING": ["BEER_STEIN", "STEW_ORANGE", "STEW_BLUE"],
			"STORAGE": ["POTATOES"],
			"SLEEPING": []
		}
	},
	BUILDINGTYPE.SHOP: {
		"zones": ["WORKSHOP", "STORAGE", "DINING"],
		"furniture": {
			"WORKSHOP": ["TABLE", "CHAIR", "SHELF"],
			"STORAGE": ["SHELF", "CHEST_YELLOW", "CHEST_YELLOW_OPEN", "BARREL_CLOSED"],
			"DINING": ["TABLE", "CHAIR"]
		},
		"items": {
			"WORKSHOP": ["POTION_RED", "POTION_GREEN", "SCROLL_WRITTEN"],
			"STORAGE": [],
			"DINING": ["STEW_ORANGE"]
		}
	},
	BUILDINGTYPE.MANOR: {
		"zones": ["SLEEPING", "DINING", "STORAGE", "WORKSHOP"],
		"furniture": {
			"SLEEPING": ["BED", "SHELF", "CHEST_GOLD_TRIM_CLOSED", "POTTED_PLANT_GREY"],
			"DINING": ["TABLE", "CHAIR", "SHELF", "POTTED_PLANT_DARK_RED"],
			"STORAGE": ["SHELF", "CHEST_BLUE", "BARREL_CLOSED", "CHEST_BLUE_OPEN"],
			"WORKSHOP": ["TABLE", "CHAIR", "SHELF"]
		},
		"items": {
			"SLEEPING": [],
			"DINING": ["STEW_ORANGE_CHICKEN", "BEER_STEIN"],
			"STORAGE": [],
			"WORKSHOP": ["SCROLL_WRITTEN", "POTION_BLACK"]
		}
	}
}

const WIDTH = 80 # Local area is more detailed, so larger
const HEIGHT = 80
const TILE_SIZE = 16 # Size of each tile in pixels
const TILE_SOURCE_ID = 5 # The ID of the TileSetAtlasSource in the tileset
const TERRAIN_SET_ID = 0 # The ID of the TerrainSetAtlasSource in the tileset
var SETTLEMENT_TYPE: int = SETTLEMENTTYPE.TOWN # Default settlement type
var SEED = null

# TODO: buildings with multiple floors
# TODO: floors with multiple rooms
# TODO: interior features like furniture, decorations, etc.

# Registry for all buildings in the settlement
var building_registry := {}

func _ready() -> void:
	# Check all tilemaps exist
	for layer in LAYERS:
		if not tilemaps.has(layer) or not tilemaps[layer]:
			push_error("TileMapLayer node for %s not found!" % layer)
			return
	# Clear and initialize all layers
	for layer in LAYERS:
		tilemaps[layer].clear()
	
	# Generate a settlement of type TOWN for demonstration
	var rng = RandomNumberGenerator.new()
	if not SEED:
		# If no seed is provided, generate a random one
		rng.seed = randi()
	else:
		rng.seed = SEED
	generate_settlement(SETTLEMENT_TYPE, rng)
	print("settlement seed is: ", rng.seed)

func generate_settlement(settlement_type: int, rng: RandomNumberGenerator) -> void:
	var area_size = Vector2i(WIDTH, HEIGHT)
	var building_counts = {
		SETTLEMENTTYPE.TOWN: {
			BUILDINGTYPE.HOUSE: 10,
			BUILDINGTYPE.TAVERN: 1,
			BUILDINGTYPE.SHOP: 1, # rng.randi_range(1, 2),
			BUILDINGTYPE.MANOR: 0
		},
		SETTLEMENTTYPE.CITY: {
			BUILDINGTYPE.HOUSE: 20, # rng.randi_range(12, 20),
			BUILDINGTYPE.TAVERN: 3, # rng.randi_range(2, 3),
			BUILDINGTYPE.SHOP: 3, # rng.randi_range(3, 5),
			BUILDINGTYPE.MANOR: 4 # rng.randi_range(1, 2)
		},
		SETTLEMENTTYPE.CASTLE: {
			BUILDINGTYPE.HOUSE: rng.randi_range(2, 4),
			BUILDINGTYPE.TAVERN: 0,
			BUILDINGTYPE.SHOP: 0,
			BUILDINGTYPE.MANOR: 1
		}
	}
	print("Generating settlement of type ", settlement_type, " with counts: ", building_counts[settlement_type])

	# Clear and initialize all layers
	for layer in LAYERS:
		tilemaps[layer].clear()
	
	# Initialize base layer with appropriate terrain based on settlement type
	var settlement_terrain = SETTLEMENT_TERRAIN[settlement_type]
	
	# Initialize terrain cells for each type
	for terrain in terrain_cells:
		terrain_cells[terrain].clear()

	# Set initial terrain and collect cells for each terrain type
	for y in area_size.y:
		for x in area_size.x:
			var terrain_type: String
			var rand = rng.randf()
			if rand < 0.7:
				terrain_type = settlement_terrain["primary"]
			elif rand < 0.9:
				terrain_type = settlement_terrain["secondary"]
			else:
				terrain_type = "grass" # Always have some grass patches
			
			terrain_cells[terrain_type].append(Vector2i(x, y))
	
	# Apply all terrains using terrain sets for proper transitions
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			tilemaps["GROUND"].set_cells_terrain_connect(
				terrain_cells[terrain],
				TERRAIN_SET_ID,
				TERRAINS[terrain],
				false
			)
		else:
			print("No cells for terrain type: ", terrain)

	# Create occupation grid
	var occupied_space_grid = []
	for y in area_size.y:
		occupied_space_grid.append([])
		for x in area_size.x:
			occupied_space_grid[y].append(false)

	# Place buildings in order: Manor first, then Taverns, Shops, and finally Houses
	var placed_buildings = []
	var building_order = [BUILDINGTYPE.MANOR, BUILDINGTYPE.TAVERN, BUILDINGTYPE.SHOP, BUILDINGTYPE.HOUSE]
	
	for building_type in building_order:
		var count = building_counts[settlement_type][building_type]
		for _i in count:
			var size = Vector2i(
				rng.randi_range(BUILDING_TEMPLATES[building_type]["min_size"].x, BUILDING_TEMPLATES[building_type]["max_size"].x),
				rng.randi_range(BUILDING_TEMPLATES[building_type]["min_size"].y, BUILDING_TEMPLATES[building_type]["max_size"].y)
			)
			var pos = find_valid_building_position(area_size, size, occupied_space_grid, rng, building_type, settlement_type)
			if pos.x != -1:
				place_building(pos, size, building_type)
				mark_occupied(occupied_space_grid, pos, size)
				var building_interior_size = size - Vector2i(2, 2) # Interior is 1 tile inset on all sides, i.e without walls
				var building_name = BuildingTypeStrings[building_type]
				placed_buildings.append({"type": building_type, "pos": pos, "size": size})
				# Register building
				var building_id = "%s_at_%d_%d" % [building_name, pos.x, pos.y]
				building_registry[building_id] = {
					"type": building_type,
					"pos": pos,
					"size": size,
					"interior_size": building_interior_size,
					"zones": [],
					"inhabitants": [],
					"interior_features": {},
					"scripted_content": null
				}
	# Generate roads between buildings and connect terrain
	generate_roads(placed_buildings, rng, settlement_type)
	
	# Generate wheat fields based on settlement type
	var num_wheat_fields = 0
	if settlement_type == SETTLEMENTTYPE.TOWN:
		num_wheat_fields = rng.randi_range(2, 4)
		for _i in range(num_wheat_fields):
			generate_wheat_field(area_size, occupied_space_grid, rng)
	connect_terrain()

	var spawner = NPCSpawner.new()
	spawner.spawn_settlement_npcs(GlobalGameState.settlements, self)
	print_rich(get_settlement_details())

func find_valid_building_position(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, rng: RandomNumberGenerator, building_type: int, settlement_type: int = SETTLEMENTTYPE.TOWN) -> Vector2i:
	var template = BUILDING_TEMPLATES[building_type]
	var spacing = template["spacing"]
	var attempts = 0
	var best_pos = Vector2i(-1, -1)
	var best_score = -1.0
	var center = Vector2(area_size.x / 2.0, area_size.y / 2.0)
	var max_distance = center.length() # Maximum possible distance from center
	
	# For towns, we'll try multiple positions and pick the best one
	var positions_to_try = 10 if settlement_type == SETTLEMENTTYPE.TOWN else 1
	
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
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
					
			if not valid:
				break
		
		if valid:
			if settlement_type != SETTLEMENTTYPE.TOWN:
				return Vector2i(x, y)
			
			# For towns, calculate score based on distance from center
			var pos_center = Vector2(x + size.x / 2.0, y + size.y / 2.0)
			var distance = pos_center.distance_to(center)
			var score = 1.0 - (distance / max_distance) # Score from 0 to 1, higher for positions closer to center
			
			# Add some randomness to avoid perfect circles
			score += rng.randf_range(-0.1, 0.1)
			
			if score > best_score:
				best_score = score
				best_pos = Vector2i(x, y)
			
			# If we've found enough positions, return the best one
			positions_to_try -= 1
			if positions_to_try <= 0:
				return best_pos
		
		attempts += 1
	
	return best_pos if best_pos.x != -1 else Vector2i(-1, -1) # Return best position found or invalid position

func mark_occupied(occupied_space_grid: Array, pos: Vector2i, size: Vector2i) -> void:
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			occupied_space_grid[y][x] = true

func place_building(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var template = BUILDING_TEMPLATES[building_type]
	print("Placing building of type ", building_type, " at ", pos, " with size ", size)
	
	# Set base terrain for the building footprint and surroundings
	var building_cells = []
	for y in range(pos.y - 1, pos.y + size.y + 1):
		for x in range(pos.x - 1, pos.x + size.x + 1):
			building_cells.append(Vector2i(x, y))
	
	# Apply terrain using set_cells_terrain_connect for proper transitions
	var ground_terrain = template["ground"].to_lower()
	tilemaps["GROUND"].set_cells_terrain_connect(
		building_cells,
		TERRAIN_SET_ID,
		TERRAINS[ground_terrain]
	)
	
	# Place floor tiles on the interior floor layer
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemaps["INTERIOR_FLOOR"].set_cell(Vector2i(x, y), TILE_SOURCE_ID, STRUCTURE_TILES[template["floor"]])

	# Place walls on walls layer
	for x in range(pos.x, pos.x + size.x):
		# Top and bottom walls
		tilemaps["WALLS"].set_cell(Vector2i(x, pos.y), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["top"]])
		tilemaps["WALLS"].set_cell(Vector2i(x, pos.y + size.y - 1), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["bottom"]])
		# place roof trim on roof layer above H walls
		tilemaps["ROOF"].set_cell(Vector2i(x, pos.y + size.y - 1), TILE_SOURCE_ID, STRUCTURE_TILES["ROOF_DARK_RED_TRIM"])

	# place roof tiles on roof layer
	for y in range(pos.y, pos.y + size.y - 1):
		for x in range(pos.x, pos.x + size.x):
			tilemaps["ROOF"].set_cell(Vector2i(x, y), TILE_SOURCE_ID, STRUCTURE_TILES[template["roof"]])
	
	for y in range(pos.y, pos.y + size.y):
		# Left and right walls with proper facing
		tilemaps["WALLS"].set_cell(Vector2i(pos.x, y), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["right"]])
		tilemaps["WALLS"].set_cell(Vector2i(pos.x + size.x - 1, y), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["left"]])

	# Place corners
	tilemaps["WALLS"].set_cell(pos, TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["corner_nw"]])
	tilemaps["WALLS"].set_cell(Vector2i(pos.x + size.x - 1, pos.y), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["corner_ne"]])
	tilemaps["WALLS"].set_cell(Vector2i(pos.x, pos.y + size.y - 1), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["corner_sw"]])
	tilemaps["WALLS"].set_cell(Vector2i(pos.x + size.x - 1, pos.y + size.y - 1), TILE_SOURCE_ID, STRUCTURE_TILES[template["walls"]["corner_se"]])

	# Place door on the south wall
	var door_x = pos.x + (size.x >> 1) # Use bit shift for integer division
	var door_y = pos.y + size.y - 1
	# Clear any wall at the door position before placing the door
	tilemaps["WALLS"].set_cell(Vector2i(door_x, door_y), -1)
	tilemaps["DOORS"].set_cell(Vector2i(door_x, door_y), TILE_SOURCE_ID, STRUCTURE_TILES["DOOR"])

	place_furniture_and_items_inside_building(pos, size, building_type)

func generate_roads(placed_buildings: Array, rng: RandomNumberGenerator, settlement_type: int) -> void:
	# Sort buildings by importance (Manor -> Tavern -> Shop -> House)
	var sorted_buildings = placed_buildings.duplicate()
	sorted_buildings.sort_custom(func(a, b): return a["type"] < b["type"])
	
	# Generate main roads between important buildings
	for i in range(sorted_buildings.size()):
		var building_a = sorted_buildings[i]
		for j in range(i + 1, sorted_buildings.size()):
			var building_b = sorted_buildings[j]
			
			# Skip if buildings are too far apart
			var distance = (building_a["pos"] - building_b["pos"]).length()
			if distance > 20: # Maximum road distance
				continue
			
			# Generate road between buildings
			generate_road_between(building_a, building_b, settlement_type)
			
			# Consider creating a plaza if buildings are close and important
			if distance < PLAZA_DISTANCE_THRESHOLD and (building_a["type"] <= BUILDINGTYPE.SHOP or building_b["type"] <= BUILDINGTYPE.SHOP):
				generate_plaza_between(building_a, building_b, rng, settlement_type)

func generate_road_between(building_a: Dictionary, building_b: Dictionary, settlement_type: int) -> void:
	var start = get_door_position(building_a)
	var end = get_door_position(building_b)
	
	# Use A* or simple line drawing to create road path
	var path = get_path_between(start, end)
	
	# Get appropriate road terrain type for this settlement
	var road_terrain = SETTLEMENT_TERRAIN[settlement_type]["paths"]
	
	# Collect road cells
	var road_cells = []
	var road_half_width = ROAD_WIDTH >> 1 # Use bit shift for integer division
	
	# Generate road positions
	for pos in path:
		for dx in range(-road_half_width, road_half_width + 1):
			for dy in range(-road_half_width, road_half_width + 1):
				road_cells.append(pos + Vector2i(dx, dy))
	
	# Apply terrain change using terrain sets for proper transitions
	tilemaps["GROUND"].set_cells_terrain_connect(
		road_cells,
		TERRAIN_SET_ID,
		TERRAINS[road_terrain]
	)

func generate_plaza_between(building_a: Dictionary, building_b: Dictionary, rng: RandomNumberGenerator, settlement_type: int) -> void:
	# Calculate plaza center
	var center = (building_a["pos"] + building_b["pos"]) / 2
	
	# Randomize plaza size
	var plaza_size = Vector2i(
		rng.randi_range(PLAZA_MIN_SIZE, PLAZA_MAX_SIZE),
		rng.randi_range(PLAZA_MIN_SIZE, PLAZA_MAX_SIZE)
	)
	
	# Get appropriate plaza terrain type for this settlement
	var plaza_terrain = SETTLEMENT_TERRAIN[settlement_type]["paths"]
	
	# Calculate plaza bounds
	var plaza_start = Vector2i(
		center.x - (plaza_size.x >> 1),
		center.y - (plaza_size.y >> 1)
	)
	
	# Collect plaza cells
	var plaza_cells = []
	for y in range(plaza_size.y):
		for x in range(plaza_size.x):
			plaza_cells.append(plaza_start + Vector2i(x, y))
	
	# Apply plaza terrain using terrain sets for proper transitions
	tilemaps["GROUND"].set_cells_terrain_connect(
		plaza_cells,
		TERRAIN_SET_ID,
		TERRAINS[plaza_terrain]
	)
	tilemaps["WALLS"].set_cell(center, TILE_SOURCE_ID, STRUCTURE_TILES["WELL_RED_ROOF"])

# When connecting terrain, use the terrain set index (not the tile alternative id)
func connect_terrain() -> void:
	var tiles = tilemaps["GROUND"].get_used_cells()
	var cells_by_terrain = {}
	
	# Group cells by their current terrain type
	for tile_pos in tiles:
		var cell_data = tilemaps["GROUND"].get_cell_tile_data(tile_pos)
		if not cell_data:
			continue
			
		var current_terrain = cell_data.terrain
		if not cells_by_terrain.has(current_terrain):
			cells_by_terrain[current_terrain] = []
		cells_by_terrain[current_terrain].append(tile_pos)
	
	# Apply terrain connections for each group
	for terrain in cells_by_terrain:
		tilemaps["GROUND"].set_cells_terrain_connect(
			cells_by_terrain[terrain],
			TERRAIN_SET_ID,
			terrain
		)

func get_door_position(building: Dictionary) -> Vector2i:
	# Returns the center of the south wall of the building as the door position
	return Vector2i(
		building["pos"].x + (building["size"].x >> 1), # Use bit shift for integer division
		building["pos"].y + building["size"].y - 1
	)

func get_path_between(start: Vector2i, end: Vector2i) -> Array:
	# Simple Manhattan line-drawing path (can be replaced with A* if needed)
	var path = []
	var current = start
	
	while current != end:
		path.append(current)
		var diff = end - current
		if abs(diff.x) > abs(diff.y):
			current.x += sign(diff.x)
		else:
			current.y += sign(diff.y)
			
	path.append(end)
	return path

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = tilemaps["GROUND"].get_cell_tile_data(coords)
	if not tile_data:
		return -1
	var tile_terrain = tile_data.terrain
	# Map terrain back to ground tile type
	for terrain in TERRAINS:
		if tile_terrain == TERRAINS[terrain]:
			return TERRAINS[terrain]
	return -1

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
		
	# Check ground layer first
	var ground_type = get_cell_ground_type(pos)
	var has_wall = tilemaps["WALLS"].get_cell_tile_data(pos)
	if ground_type == TERRAINS["water"] or has_wall:
		return false
	# # Check if there's blocking foliage
	# var foliage_type = get_cell_foliage_type(pos)
	# if foliage_type == FoliageTile.TREE or foliage_type == FoliageTile.ROCK:
	# 	return false
		
	return true

func place_furniture_and_items_inside_building(pos, size, type) -> void:
	var layout = BUILDING_LAYOUTS[type]
	
	# Divide building into zones
	var zones = divide_building_into_zones(pos, size, layout["zones"])
	
	# Place furniture and items in each zone
	for zone_name in zones:
		var zone_rect = zones[zone_name]
		var furniture_list = layout["furniture"][zone_name]
		# var items_list = layout["items"][zone_name]
		
		place_zone_furniture(zone_rect, furniture_list)
		# place_zone_items(zone_rect, items_list)

func divide_building_into_zones(pos: Vector2i, size: Vector2i, zone_types: Array) -> Dictionary:
	var zones = {}
	var zone_count = zone_types.size()
	
	if zone_count == 1:
		# Single zone takes up whole building
		zones[zone_types[0]] = Rect2i(pos.x + 1, pos.y + 1, size.x - 2, size.y - 2)
	elif zone_count == 2:
		# Split vertically
		var half_width = (size.x - 2) >> 1
		zones[zone_types[0]] = Rect2i(pos.x + 1, pos.y + 1, half_width, size.y - 2)
		zones[zone_types[1]] = Rect2i(pos.x + 1 + half_width, pos.y + 1, size.x - 2 - half_width, size.y - 2)
	else:
		# Split into quadrants
		var half_width = (size.x - 2) >> 1
		var half_height = (size.y - 2) >> 1
		
		for i in range(min(zone_count, 4)):
			var zone_x = pos.x + 1 + (i % 2) * half_width
			var zone_y = pos.y + 1 + (i / 2) * half_height
			zones[zone_types[i]] = Rect2i(zone_x, zone_y, half_width, half_height)
	
	return zones

func place_zone_furniture(zone: Rect2i, furniture_list: Array) -> void:
	var placed_positions = []
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(zone.position)
	
	# Place furniture along walls first
	for x in range(zone.position.x, zone.end.x):
		for y in range(zone.position.y, zone.end.y):
			# Skip if too close to other furniture
			if is_near_furniture(Vector2i(x, y), placed_positions):
				continue
			
			# Higher chance to place furniture against walls
			if is_against_wall(Vector2i(x, y)):
				if rng.randf() < 0.4: # 40% chance for wall furniture
					var furniture = furniture_list[rng.randi() % furniture_list.size()]
					tilemaps["FURNITURE"].set_cell(Vector2i(x, y),
								   TILE_SOURCE_ID, FURNITURE_TILES[furniture])
					placed_positions.append(Vector2i(x, y))
	
	# Then place remaining furniture in open spaces
	for x in range(zone.position.x, zone.end.x):
		for y in range(zone.position.y, zone.end.y):
			if is_near_furniture(Vector2i(x, y), placed_positions):
				continue
				
			if rng.randf() < 0.2: # 20% chance for open space furniture
				var furniture = furniture_list[rng.randi() % furniture_list.size()]
				tilemaps["FURNITURE"].set_cell(Vector2i(x, y),
							   TILE_SOURCE_ID, FURNITURE_TILES[furniture])
				placed_positions.append(Vector2i(x, y))

func place_zone_items(zone: Rect2i, items_list: Array) -> void:
	if items_list.is_empty():
		return
		
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(zone.position) + 1
	
	# Place items near related furniture
	for x in range(zone.position.x, zone.end.x):
		for y in range(zone.position.y, zone.end.y):
			var pos = Vector2i(x, y)
			if has_nearby_furniture(pos) and rng.randf() < 0.3: # 30% chance near furniture
				var item = items_list[rng.randi() % items_list.size()]
				tilemaps["ITEMS"].set_cell(pos, TILE_SOURCE_ID, ITEM_TILES[item])

func is_near_furniture(pos: Vector2i, placed_positions: Array) -> bool:
	for placed in placed_positions:
		if (pos - placed).length() < 2:
			return true
	return false

func has_nearby_furniture(pos: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var check_pos = pos + Vector2i(dx, dy)
			if tilemaps["FURNITURE"].get_cell_source_id(check_pos) == TILE_SOURCE_ID:
				return true
	return false

func is_against_wall(pos: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var check_pos = pos + Vector2i(dx, dy)
			if tilemaps["WALLS"].get_cell_source_id(check_pos) == TILE_SOURCE_ID:
				return true
	return false

func generate_wheat_field(area_size: Vector2i, occupied_space_grid: Array, rng: RandomNumberGenerator) -> void:
	const MIN_FIELD_SIZE = Vector2i(4, 4) # Minimum size for a wheat field
	const MAX_FIELD_SIZE = Vector2i(8, 12) # Maximum size for a wheat field
	
	# First, try to find a valid position for the field
	var field_size = Vector2i(
		rng.randi_range(MIN_FIELD_SIZE.x, MAX_FIELD_SIZE.x),
		rng.randi_range(MIN_FIELD_SIZE.y, MAX_FIELD_SIZE.y)
	)
	
	var pos = find_valid_building_position(area_size, field_size, occupied_space_grid, rng, BUILDINGTYPE.HOUSE) # Using HOUSE spacing rules
	if pos.x == -1: # No valid position found
		return
	
	# Check if the area is grass
	var is_grass_area = true
	for y in range(pos.y, pos.y + field_size.y):
		for x in range(pos.x, pos.x + field_size.x):
			var cell = tilemaps["GROUND"].get_cell_tile_data(Vector2i(x, y)).terrain
			if cell == TERRAINS.stone:
				is_grass_area = false
				break
		if not is_grass_area:
			break
	
	if not is_grass_area:
		return
	
	# Place the wheat field
	for y in range(pos.y, pos.y + field_size.y):
		for x in range(pos.x, pos.x + field_size.x):
			tilemaps["GROUND"].set_cells_terrain_connect([Vector2i(x, y)], TERRAIN_SET_ID, TERRAINS.wheat_field)
	
	# Mark the area as occupied
	mark_occupied(occupied_space_grid, pos, field_size)
	terrain_cells["wheat_field"] = terrain_cells.get("wheat_field", [])
	for y in range(pos.y, pos.y + field_size.y):
		for x in range(pos.x, pos.x + field_size.x):
			terrain_cells["wheat_field"].append(Vector2i(x, y))

# Returns a dictionary with all relevant settlement data for global_game_state
func get_settlement_details() -> Dictionary:
	var details = {
		"type": SETTLEMENT_TYPE,
		"seed": SEED,
		"width": WIDTH,
		"height": HEIGHT,
		"buildings": {},
		"npcs": {},
	}
	# Collect building data
	for building_id in building_registry:
		details["buildings"][building_id] = get_building_details(building_id)
	return details

# Returns a dictionary with all relevant building data for a given building_id
func get_building_details(building_id: String) -> Dictionary:
	if not building_registry.has(building_id):
		return {}
	var b = building_registry[building_id]
	return {
		"id": building_id,
		"type": b["type"],
		"pos": (b["pos"]),
		"size": (b["size"]),
		"zones": b.get("zones", []),
		"inhabitants": b.get("inhabitants", []),
		"interior_features": b.get("interior_features", {}),
		"scripted_content": b.get("scripted_content", null)
	}
