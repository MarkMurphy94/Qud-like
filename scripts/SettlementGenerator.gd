extends Node2D

# Types of settlements
enum SettlementType {TOWN, CITY, CASTLE}
# Types of buildings
enum BuildingType {HOUSE, TAVERN, SHOP, MANOR}
@onready var tilemap = $TileMap

# Layer definitions for proper organization
const LAYERS = {
	"BASE": 0, # Ground terrain (grass, dirt, stone)
	"INTERIOR_FLOOR": 1, # Building floors
	"WALLS": 2, # Building walls
	"DOORS": 3 # Building doors
}

# Terrain sets for better tile transitions
const TERRAIN_SETS = {
	"stone": 0, # Stone paths and plazas
	"grass": 1, # Natural grass areas
	"dirt": 2 # Dirt paths and yards
}

# Default terrain type for each settlement type
const SETTLEMENT_TERRAIN = {
	SettlementType.TOWN: {
		"primary": "grass",
		"secondary": "dirt",
		"paths": "dirt"
	},
	SettlementType.CITY: {
		"primary": "stone",
		"secondary": "dirt",
		"paths": "stone"
	},
	SettlementType.CASTLE: {
		"primary": "stone",
		"secondary": "grass",
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
const TILES = {
	"FLOOR_WOOD": Vector2i(67, 10),
	"FLOOR_STONE": Vector2i(7, 10),
	"GROUND": Vector2i(0, 0), # Base ground tile
	"WALL_H": Vector2i(6, 19), # Horizontal wall
	"WALL_H_INT": Vector2i(6, 20), # Interior horizontal wall
	"WALL_V_LEFT": Vector2i(9, 20), # Left-facing vertical wall
	"WALL_V_RIGHT": Vector2i(4, 19), # Right-facing vertical wall
	"CORNER_NW": Vector2i(5, 19),
	"CORNER_NE": Vector2i(7, 19),
	"CORNER_SW": Vector2i(5, 20),
	"CORNER_SE": Vector2i(7, 20),
	"DOOR": Vector2i(5, 21)
}

# Building templates with ground type preferences
const BUILDING_TEMPLATES = {
	BuildingType.HOUSE: {
		"min_size": Vector2i(4, 4),
		"max_size": Vector2i(6, 6),
		"floor": "FLOOR_WOOD",
		"ground": "DIRT", # Houses tend to have dirt yards
		"spacing": 1 # Minimum space between houses
	},
	BuildingType.TAVERN: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(8, 8),
		"floor": "FLOOR_WOOD",
		"ground": "STONE", # Stone paths around taverns
		"spacing": 2 # More space for taverns
	},
	BuildingType.SHOP: {
		"min_size": Vector2i(5, 5),
		"max_size": Vector2i(7, 7),
		"floor": "FLOOR_WOOD",
		"ground": "STONE", # Stone paths around shops
		"spacing": 2
	},
	BuildingType.MANOR: {
		"min_size": Vector2i(8, 8),
		"max_size": Vector2i(12, 12),
		"floor": "FLOOR_WOOD",
		"ground": "STONE", # Stone surroundings for manors
		"spacing": 3 # Manors need more space
	}
}

const WIDTH = 40 # Local area is more detailed, so larger
const HEIGHT = 40
const TILE_SIZE = 16 # Size of each tile in pixels
const TILE_SOURCE_ID = 5 # The ID of the TileSetAtlasSource in the tileset
const TERRAIN_SET_ID = 0 # The ID of the TerrainSetAtlasSource in the tileset

# TODO: dirt trails/stone roads
# TODO: instead of 1 ground tile, use 2x2 tiles for more variety? Need terrain set??
# TODO: patches of grass/dirt
# TODO: buildings with multiple floors
# TODO: interior features like furniture, decorations, etc.

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
	print("Generating settlement of type ", settlement_type, " with counts: ", building_counts[settlement_type])

	# Clear and initialize all layers
	tilemap.clear()
	
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
			tilemap.set_cells_terrain_connect(
				LAYERS.BASE,
				terrain_cells[terrain],
				TERRAIN_SET_ID,
				TERRAIN_SETS[terrain]
			)

	# Create occupation grid
	var occupation_grid = []
	for y in area_size.y:
		occupation_grid.append([])
		for x in area_size.x:
			occupation_grid[y].append(false)

	# Place buildings in order: Manor first, then Taverns, Shops, and finally Houses
	var placed_buildings = []
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

	# Generate roads between buildings and connect terrain
	generate_roads(placed_buildings, rng, settlement_type)
	connect_terrain()

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
	print("Placing building of type ", building_type, " at ", pos, " with size ", size)
	
	# Set base terrain for the building footprint and surroundings
	var building_cells = []
	for y in range(pos.y - 1, pos.y + size.y + 1):
		for x in range(pos.x - 1, pos.x + size.x + 1):
			building_cells.append(Vector2i(x, y))
	
	# Apply terrain using set_cells_terrain_connect for proper transitions
	var ground_terrain = template["ground"].to_lower()
	tilemap.set_cells_terrain_connect(
		LAYERS.BASE,
		building_cells,
		TERRAIN_SET_ID,
		TERRAIN_SETS[ground_terrain]
	)
	
	# Place floor tiles on the interior floor layer
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemap.set_cell(LAYERS.INTERIOR_FLOOR, Vector2i(x, y), TILE_SOURCE_ID, TILES[template["floor"]])
	
	# Place walls on walls layer
	for x in range(pos.x, pos.x + size.x):
		# Top and bottom walls
		tilemap.set_cell(LAYERS.WALLS, Vector2i(x, pos.y), TILE_SOURCE_ID, TILES["WALL_H"])
		tilemap.set_cell(LAYERS.WALLS, Vector2i(x, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["WALL_H"])
		
		# Add an interior horizontal wall if building is large enough
		if size.y > 6 and x > pos.x + 1 and x < pos.x + size.x - 2:
			var mid_y = pos.y + size.y >> 1 # Use bit shift for integer division
			tilemap.set_cell(LAYERS.WALLS, Vector2i(x, mid_y), TILE_SOURCE_ID, TILES["WALL_H_INT"])
	
	for y in range(pos.y, pos.y + size.y):
		# Left and right walls with proper facing
		tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x, y), TILE_SOURCE_ID, TILES["WALL_V_RIGHT"])
		tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, y), TILE_SOURCE_ID, TILES["WALL_V_LEFT"])
	
	# Place corners
	tilemap.set_cell(LAYERS.WALLS, pos, TILE_SOURCE_ID, TILES["CORNER_NW"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, pos.y), TILE_SOURCE_ID, TILES["CORNER_NE"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["CORNER_SW"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, pos.y + size.y - 1), TILE_SOURCE_ID, TILES["CORNER_SE"])
	
	# Place door on the south wall
	var door_x = pos.x + (size.x >> 1) # Use bit shift for integer division
	var door_y = pos.y + size.y - 1
	tilemap.set_cell(LAYERS.DOORS, Vector2i(door_x, door_y), TILE_SOURCE_ID, TILES["DOOR"])

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
			if distance < PLAZA_DISTANCE_THRESHOLD and (building_a["type"] <= BuildingType.SHOP or building_b["type"] <= BuildingType.SHOP):
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
	tilemap.set_cells_terrain_connect(
		LAYERS.BASE,
		road_cells,
		TERRAIN_SET_ID,
		TERRAIN_SETS[road_terrain]
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
	tilemap.set_cells_terrain_connect(
		LAYERS.BASE,
		plaza_cells,
		TERRAIN_SET_ID,
		TERRAIN_SETS[plaza_terrain]
	)

# When connecting terrain, use the terrain set index (not the tile alternative id)
func connect_terrain() -> void:
	var tiles = tilemap.get_used_cells(LAYERS.BASE)
	var cells_by_terrain = {}
	
	# Group cells by their current terrain type
	for tile_pos in tiles:
		var cell_data = tilemap.get_cell_tile_data(LAYERS.BASE, tile_pos)
		if not cell_data:
			continue
			
		var current_terrain = cell_data.terrain
		if not cells_by_terrain.has(current_terrain):
			cells_by_terrain[current_terrain] = []
		cells_by_terrain[current_terrain].append(tile_pos)
	
	# Apply terrain connections for each group
	for terrain in cells_by_terrain:
		tilemap.set_cells_terrain_connect(
			LAYERS.BASE,
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
