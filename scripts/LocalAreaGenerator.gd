extends Node2D

# Mirror of OverworldGenerator.Tile for local reference
enum OverworldTile {WATER, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, DIRT, WATER}
enum FoliageTile {TREE, BUSH, ROCK}
enum StructureType {HOUSE, SHOP, TEMPLE, TOWER, WALL}

# Terrain sets for ground tiles
const TERRAINS = {
	"stone": 0, # Stone paths and plazas
	"grass": 1, # Natural grass areas
	"dirt": 2, # Dirt paths and yards
	"water": 3
}

const LAYERS = {
	"GROUND": 0, # Ground terrain (grass, dirt, stone)
	"WALLS": 1, # Building walls
	"DOORS": 2, # Building doors
	"ITEMS": 3 # Foliage and details (trees, bushes, rocks)
}

# Map our enum types to terrain sets
const GROUND_TERRAIN_MAP = {
	GroundTile.STONE: "stone",
	GroundTile.GRASS: "grass",
	GroundTile.DIRT: "dirt",
	GroundTile.WATER: "water"
}

const FOLIAGE_COORDS = {
	FoliageTile.TREE: Vector2i(7, 4), # Tree tile
	FoliageTile.BUSH: Vector2i(8, 6), # Bush/shrub tile
	FoliageTile.ROCK: Vector2i(4, 8) # Boulder/rock tile
}

# Update the STRUCTURE_TILES constant to include directional walls
const STRUCTURE_TILES = {
	# Wall tiles
	"WALL_H": Vector2i(6, 19), # Horizontal wall
	"WALL_V_LEFT": Vector2i(9, 20), # Left-facing vertical wall
	"WALL_V_RIGHT": Vector2i(4, 19), # Right-facing vertical wall
	"CORNER_NW": Vector2i(5, 19),
	"CORNER_NE": Vector2i(7, 19),
	"CORNER_SW": Vector2i(5, 20),
	"CORNER_SE": Vector2i(7, 20),
	# Door tiles
	"DOOR": Vector2i(5, 21),
	# Floor tiles
	"FLOOR_WOOD": Vector2i(67, 10),
	"FLOOR_STONE": Vector2i(53, 10),
}

const STRUCTURE_TEMPLATES = {
	StructureType.HOUSE: {
		"min_size": Vector2i(5, 5),
		"max_size": Vector2i(8, 8),
		"floor": "FLOOR_WOOD",
		"required_space": 2 # Space needed around building
	},
	StructureType.SHOP: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_STONE",
		"required_space": 3
	},
	StructureType.TEMPLE: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_WOOD",
		"required_space": 3
	},
	StructureType.TOWER: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_WOOD",
		"required_space": 3
	},
	StructureType.WALL: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_STONE",
		"required_space": 3
	}
}

const WIDTH = 40 # Local area is more detailed, so larger
const HEIGHT = 40
const TILE_SIZE = 16 # Size of each tile in pixels
const TILE_SOURCE_ID = 5 # The ID of the TileSetAtlasSource in the tileset

@export var noise_scale: float = 20.0
@export var tree_density: float = 0.1
@export var bush_density: float = 0.15
@export var rock_density: float = 0.08
@export var water_level: float = 0.4

@onready var tilemap = $TileMap
var noise: FastNoiseLite
var rng = RandomNumberGenerator.new()
var base_terrain: int # The overworld terrain type this area is based on

# Called when descending from overworld to local area
func initialize(overworld_tile_type: int, world_position: Vector2i) -> void:
	base_terrain = overworld_tile_type
	position = Vector2(world_position)
	print("Initializing local area at position: ", position, " with terrain type: ", base_terrain)
	
	# Set up noise and RNG with deterministic seed
	var map_seed = generate_seed(world_position, overworld_tile_type)
	# var map_seed = 16778390 # fixed seed for testing
	rng.seed = map_seed
	noise.seed = map_seed
	noise.frequency = 1.0 / noise_scale
	print("local area seed: ", map_seed, " for terrain: ", base_terrain)
	
	generate_map()
	
func _ready() -> void:
	if not tilemap:
		push_error("TileMap node not found!")
		return
	noise = FastNoiseLite.new()

func generate_map() -> void:
	# The cells arrays might not include all positions
	var stone_cells = []
	var grass_cells = []
	var dirt_cells = []
	var water_cells = []
	
	# Generate base terrain on ground layer (layer 0)
	for y in HEIGHT:
		for x in WIDTH:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2 # Normalize to 0-1
			
			var ground_tile = get_ground_tile(x, y, height)
			var terrain_type = GROUND_TERRAIN_MAP[ground_tile]
			var pos = Vector2i(x, y)
			
			# Sort cells by terrain type
			match terrain_type:
				"stone": stone_cells.append(pos)
				"grass": grass_cells.append(pos)
				"dirt": dirt_cells.append(pos)
				"water": water_cells.append(pos)
	
	# Apply terrain for each type separately
	if stone_cells:
		tilemap.set_cells_terrain_connect(LAYERS.GROUND, stone_cells, 0, TERRAINS["stone"], false)
	if grass_cells:
		tilemap.set_cells_terrain_connect(LAYERS.GROUND, grass_cells, 0, TERRAINS["grass"], false)
	if dirt_cells:
		tilemap.set_cells_terrain_connect(LAYERS.GROUND, dirt_cells, 0, TERRAINS["dirt"], false)
	# if water_cells:
	# 	tilemap.set_cells_terrain_connect(LAYERS.GROUND, water_cells, 0, TERRAINS["water"])

	# debug_cells(grass_cells, dirt_cells, water_cells)

	# Add water features to appropriate terrains first
	if base_terrain == OverworldTile.GRASS:
		maybe_add_water_features()
	
	# Add foliage and details on foliage layer (layer 1)
	add_foliage()
	
	# Generate small settlement if on appropriate terrain
	if base_terrain == OverworldTile.GRASS:
		if randf() < 0.3: # 30% chance for settlement
			var hamlet_type = "village"
			if randf() < 0.3:
				hamlet_type = "farm"
			generate_hamlet(hamlet_type)
	
	# Print debug visualization of the final map
	# debug_print_terrain_matrix()

func get_ground_tile(_x: int, _y: int, height: float) -> int:
	if base_terrain == OverworldTile.GRASS:
		if height > 0.8: # Small chance for stone patches
			return GroundTile.STONE
		return GroundTile.GRASS
	if base_terrain == OverworldTile.MOUNTAIN:
		if height < 0.4:
			return GroundTile.GRASS
		elif height < 0.7:
			return GroundTile.DIRT
		return GroundTile.STONE
	if base_terrain == OverworldTile.WATER:
		return GroundTile.WATER
	else:
		return GroundTile.GRASS
			
func add_foliage() -> void:
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = rng.randi()
	detail_noise.frequency = 1.0 / (noise_scale * 0.5)
	
	for y in HEIGHT:
		for x in WIDTH:
			var ground_type = get_cell_ground_type(Vector2i(x, y))
			if ground_type == -1: # Invalid tile
				continue
				
			var detail_value = (detail_noise.get_noise_2d(x, y) + 1) / 2
			var pos = Vector2i(x, y)
			
			# Only add foliage on walkable ground tiles
			if ground_type in [GroundTile.GRASS, GroundTile.DIRT, GroundTile.STONE]:
				# Scale densities based on terrain type
				var local_tree_density = tree_density
				var local_bush_density = bush_density
				var local_rock_density = rock_density
				
				match ground_type:
					GroundTile.DIRT:
						local_tree_density *= 0.3 # Fewer trees in sand
						local_bush_density *= 0.5 # Fewer bushes in sand
						local_rock_density *= 1.5 # More rocks in sand
					GroundTile.STONE:
						local_tree_density *= 0.5 # Fewer trees on stone
						local_bush_density *= 0.7 # Fewer bushes on stone
						local_rock_density *= 2.0 # More rocks on stone
				
				# Add foliage based on adjusted densities
				if detail_value < local_tree_density:
					tilemap.set_cell(LAYERS.ITEMS, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.TREE])
				elif detail_value < local_tree_density + local_bush_density:
					tilemap.set_cell(LAYERS.ITEMS, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.BUSH])
				elif detail_value < local_tree_density + local_bush_density + local_rock_density:
					tilemap.set_cell(LAYERS.ITEMS, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.ROCK])

func maybe_add_water_features() -> void:
	# 30% chance to add a water feature
	if randf() > 0.3:
		return
	
	# Decide between lake or river
	if randf() > 0.5:
		generate_lake()
	else:
		generate_river()

func generate_lake() -> void:
	var center = Vector2i(
		rng.randi_range(10, WIDTH - 10),
		rng.randi_range(10, HEIGHT - 10)
	)
	var size = rng.randi_range(3, 8)
	
	var water_cells = []
	
	for y in range(-size, size + 1):
		for x in range(-size, size + 1):
			var pos = center + Vector2i(x, y)
			if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
				continue
			
			var dist = sqrt(x * x + y * y)
			if dist <= size + randf() * 2 - 1: # Irregular edges
				water_cells.append(pos)
	
	# Apply water terrain to all cells at once
	if water_cells.size() > 0:
		tilemap.set_cells_terrain_connect(0, water_cells, 0, TERRAINS["water"])

func generate_river() -> void:
	var start = Vector2i(
		rng.randi_range(0, WIDTH),
		0 if rng.randi() % 2 == 0 else HEIGHT - 1
	)
	var end = Vector2i(
		rng.randi_range(0, WIDTH),
		HEIGHT - 1 if start.y == 0 else 0
	)
	
	var river_cells = []
	var current = start
	while current != end:
		river_cells.append(current)
		
		# Move towards end with some randomness
		var dir = Vector2(end - current).normalized()
		current += Vector2i(
			sign(dir.x) if randf() > 0.3 else rng.randi_range(-1, 1),
			sign(dir.y)
		)
		current.x = clamp(current.x, 0, WIDTH - 1)
		current.y = clamp(current.y, 0, HEIGHT - 1)
	
	# Apply water terrain to all river cells at once
	if river_cells.size() > 0:
		tilemap.set_cells_terrain_connect(0, river_cells, 0, TERRAINS["water"])

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = tilemap.get_cell_tile_data(LAYERS.GROUND, coords)
	if not tile_data:
		return -1
	var terrain = tile_data.terrain
	# Map terrain back to ground tile type
	for tile in GROUND_TERRAIN_MAP:
		if TERRAINS[GROUND_TERRAIN_MAP[tile]] == terrain:
			return tile
	return -1

func get_cell_foliage_type(coords: Vector2i) -> int:
	var atlas_coords = tilemap.get_cell_atlas_coords(1, coords) # Check foliage layer
	for tile in FOLIAGE_COORDS:
		if FOLIAGE_COORDS[tile] == atlas_coords:
			return tile
	return -1

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
		
	# Check ground layer first
	var ground_type = get_cell_ground_type(pos)
	if ground_type == GroundTile.WATER:
		return false
		
	# Check if there's blocking foliage
	var foliage_type = get_cell_foliage_type(pos)
	if foliage_type == FoliageTile.TREE or foliage_type == FoliageTile.ROCK:
		return false
		
	return true

func generate_hamlet(hamlet_type: String) -> void:
	var building_count = 0
	match hamlet_type:
		"village":
			building_count = rng.randi_range(3, 6)
		"farm":
			building_count = rng.randi_range(2, 4)
	
	# Create a grid to track building placement
	var occupation_grid = []
	for y in HEIGHT:
		occupation_grid.append([])
		for x in WIDTH:
			occupation_grid[y].append(false)
	
	# Place buildings
	var buildings_placed = 0
	var attempts = 0
	while buildings_placed < building_count and attempts < 100:
		var building_type = StructureType.values()[rng.randi() % StructureType.size()]
		if try_place_building(building_type, occupation_grid):
			buildings_placed += 1
		attempts += 1

func spawn_dungeon_entrance():
	pass # TODO: Dungeon generation logic would go here

func generate_ruin():
	pass # TODO: Ruin generation logic would go here

func try_place_building(type: int, occupation_grid: Array) -> bool:
	var template = STRUCTURE_TEMPLATES[type]
	var size = Vector2i(
		rng.randi_range(template.min_size.x, template.max_size.x),
		rng.randi_range(template.min_size.y, template.max_size.y)
	)
	
	# Find valid position
	var valid_positions = []
	for y in range(template.required_space, HEIGHT - size.y - template.required_space):
		for x in range(template.required_space, WIDTH - size.x - template.required_space):
			if is_valid_building_position(Vector2i(x, y), size, template.required_space, occupation_grid):
				valid_positions.append(Vector2i(x, y))
	
	if valid_positions == []:
		return false
	
	# Choose random valid position and place building
	var pos = valid_positions[rng.randi() % valid_positions.size()]
	place_building(pos, size, type)
	
	# Mark area as occupied
	for y in range(pos.y - template.required_space, pos.y + size.y + template.required_space):
		for x in range(pos.x - template.required_space, pos.x + size.x + template.required_space):
			occupation_grid[y][x] = true
	
	return true

# Update the place_building function to use directional walls
func place_building(pos: Vector2i, size: Vector2i, type: int) -> void:
	var template = STRUCTURE_TEMPLATES[type]
	print('placing building: ', type, ' at ', pos, ' with size ', size)
	
	# Place floors
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemap.set_cell(LAYERS.GROUND, Vector2i(x, y), TILE_SOURCE_ID,
						   STRUCTURE_TILES[template.floor])
	
	# Place walls
	for x in range(pos.x, pos.x + size.x):
		# Top and bottom horizontal walls
		tilemap.set_cell(LAYERS.WALLS, Vector2i(x, pos.y), TILE_SOURCE_ID,
						STRUCTURE_TILES["WALL_H"]) # Top wall
		tilemap.set_cell(LAYERS.WALLS, Vector2i(x, pos.y + size.y - 1),
						TILE_SOURCE_ID, STRUCTURE_TILES["WALL_H"]) # Bottom wall
	
	for y in range(pos.y, pos.y + size.y):
		# Left and right walls with proper facing
		tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x, y), TILE_SOURCE_ID,
						STRUCTURE_TILES["WALL_V_RIGHT"]) # Right-facing wall on left side
		tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, y),
						TILE_SOURCE_ID, STRUCTURE_TILES["WALL_V_LEFT"]) # Left-facing wall on right side
	
	# Place corners
	tilemap.set_cell(LAYERS.WALLS, pos, TILE_SOURCE_ID,
					 STRUCTURE_TILES["CORNER_NW"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, pos.y), TILE_SOURCE_ID,
					 STRUCTURE_TILES["CORNER_NE"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x, pos.y + size.y - 1), TILE_SOURCE_ID,
					 STRUCTURE_TILES["CORNER_SW"])
	tilemap.set_cell(LAYERS.WALLS, Vector2i(pos.x + size.x - 1, pos.y + size.y - 1),
					 TILE_SOURCE_ID, STRUCTURE_TILES["CORNER_SE"])
	
	# Add door on south wall
	add_door(pos, size)

func is_valid_building_position(pos: Vector2i, size: Vector2i, required_space: int, occupation_grid: Array) -> bool:
	# Check if the area (including required space) is within bounds
	if pos.x - required_space < 0 or pos.x + size.x + required_space >= WIDTH:
		return false
	if pos.y - required_space < 0 or pos.y + size.y + required_space >= HEIGHT:
		return false
	
	# Check if any tile in the area (including required space) is occupied or unwalkable
	for y in range(pos.y - required_space, pos.y + size.y + required_space):
		for x in range(pos.x - required_space, pos.x + size.x + required_space):
			if occupation_grid[y][x]:
				return false
			if not is_walkable(Vector2i(x, y)):
				return false
	
	return true

func add_door(pos: Vector2i, size: Vector2i) -> void:
	var door_pos = Vector2i(
			pos.x + rng.randi_range(1, size.x - 2),
			pos.y + size.y - 1
		)
	tilemap.set_cell(LAYERS.DOORS, door_pos, TILE_SOURCE_ID, STRUCTURE_TILES["DOOR"])

func generate_seed(world_position: Vector2i, terrain_type: int) -> int:
	# Combine position and terrain type into a deterministic seed
	# Using large prime numbers to minimize collisions
	return abs(world_position.x * 16777619 + world_position.y * 65537 + terrain_type * 257)

# Constants for terrain visualization
const TERRAIN_CHARS = {
	GroundTile.GRASS: ",", # Grass as dots
	GroundTile.DIRT: ".", # Dirt as commas
	GroundTile.STONE: "#", # Stone as hash
	GroundTile.WATER: "~", # Water as waves
	-1: " " # Unknown/invalid as space
}

func debug_print_terrain_matrix() -> void:
	print("\nTerrain Matrix:")
	print("Legend: . = Grass, , = Dirt, # = Stone, ~ = Water, T = Tree, R = Rock, B = Bush")
	var border = ""
	for i in WIDTH + 2:
		border += "-"
	print(border) # Top border
	
	for y in HEIGHT:
		var line = "|" # Left border
		for x in WIDTH:
			var pos = Vector2i(x, y)
			var ground_type = get_cell_ground_type(pos)
			var foliage_type = get_cell_foliage_type(pos)

			if ground_type == -1:
				line += " " # Invalid tile
				continue
			
			# Prioritize foliage display over ground
			if foliage_type == FoliageTile.TREE:
				line += "T"
			elif foliage_type == FoliageTile.ROCK:
				line += "R"
			elif foliage_type == FoliageTile.BUSH:
				line += "B"
			else:
				line += TERRAIN_CHARS[ground_type]
		
		line += "|" # Right border
		print(line)
	
	print(border) # Bottom border

func debug_cells(grass_cells, dirt_cells, water_cells):
	# Debug: Count total cells
	var total_cells = grass_cells.size() + dirt_cells.size() + water_cells.size()
	print("Total cells: ", total_cells, " out of ", WIDTH * HEIGHT)
	print("Grass cells: ", grass_cells.size())
	print("Dirt cells: ", dirt_cells.size())
	print("Water cells: ", water_cells.size())
	
	# Add this check before terrain application
	if total_cells < WIDTH * HEIGHT:
		print("WARNING: Some tiles were not assigned terrain!")
		# Find missing positions
		for y in HEIGHT:
			for x in WIDTH:
				var pos = Vector2i(x, y)
				if not (pos in grass_cells or pos in dirt_cells or pos in water_cells):
					print("Missing terrain at: ", pos)
					# Default to grass for missing tiles
					grass_cells.append(pos)
