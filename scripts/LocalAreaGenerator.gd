extends Node2D

# Mirror of OverworldGenerator.Tile for local reference
enum OverworldTile {DEEP_WATER, SHALLOW_WATER, SAND, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, SAND, WATER}
enum FoliageTile {TREE, BUSH, ROCK}
enum StructureType {HOUSE, SHOP, TEMPLE, TOWER, WALL}

# Terrain sets for ground tiles
const TERRAIN_SETS = {
	"grass": 0,
	"dirt": 1,
	"water": 2
}

# Map our enum types to terrain sets
const GROUND_TERRAIN_MAP = {
	GroundTile.GRASS: "grass",
	GroundTile.STONE: "dirt",
	GroundTile.SAND: "dirt",
	GroundTile.WATER: "water"
}

const FOLIAGE_COORDS = {
	FoliageTile.TREE: Vector2i(4, 28), # Tree tile
	FoliageTile.BUSH: Vector2i(4, 31), # Bush/shrub tile
	FoliageTile.ROCK: Vector2i(4, 32) # Boulder/rock tile
}

const STRUCTURE_TILES = {
	# Wall tiles
	"WALL_H": Vector2i(6, 43), # Horizontal wall
	"WALL_V": Vector2i(4, 43), # Vertical wall
	"CORNER_NW": Vector2i(5, 43),
	"CORNER_NE": Vector2i(7, 43),
	"CORNER_SW": Vector2i(5, 44),
	"CORNER_SE": Vector2i(7, 44),
	# Door tiles
	"DOOR": Vector2i(5, 45),
	# Floor tiles
	"FLOOR_WOOD": Vector2i(33, 14),
	"FLOOR_STONE": Vector2i(33, 9),
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
const TILE_SOURCE_ID = 3 # The ID of the TileSetAtlasSource in the tileset

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
	position = Vector2(world_position) * TILE_SIZE
	
	# Set up noise and RNG with deterministic seed
	# var map_seed = generate_seed(world_position, overworld_tile_type)
	var map_seed = 16778390 # fixed seed for testing
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
	if not tilemap:
		push_error("TileMap is null!")
		return
	print("Generating map with base terrain: ", base_terrain)
	tilemap.clear()
	
	# Generate terrain data first
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
				"grass": grass_cells.append(pos)
				"dirt": dirt_cells.append(pos)
				"water": water_cells.append(pos)
	
	# Apply terrain for each type separately
	if grass_cells:
		tilemap.set_cells_terrain_connect(0, grass_cells, 0, TERRAIN_SETS["grass"])
	if dirt_cells:
		tilemap.set_cells_terrain_connect(0, dirt_cells, 0, TERRAIN_SETS["dirt"])
	if water_cells:
		tilemap.set_cells_terrain_connect(0, water_cells, 0, TERRAIN_SETS["water"])
	
	# Add water features to appropriate terrains first
	if base_terrain in [OverworldTile.GRASS, OverworldTile.SAND]:
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

func get_ground_tile(_x: int, _y: int, height: float) -> int:
	match base_terrain:
		OverworldTile.GRASS:
			if height > 0.8: # Small chance for stone patches
				return GroundTile.STONE
			return GroundTile.GRASS
		OverworldTile.SAND:
			if height > 0.9: # Rare stone outcroppings
				return GroundTile.STONE
			return GroundTile.SAND
		OverworldTile.MOUNTAIN:
			if height < 0.4:
				return GroundTile.GRASS
			elif height < 0.7:
				return GroundTile.SAND
			return GroundTile.STONE
		OverworldTile.DEEP_WATER, OverworldTile.SHALLOW_WATER:
			if height > 0.8: # Islands
				return GroundTile.SAND
			return GroundTile.WATER
		_:
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
			if ground_type in [GroundTile.GRASS, GroundTile.SAND, GroundTile.STONE]:
				# Scale densities based on terrain type
				var local_tree_density = tree_density
				var local_bush_density = bush_density
				var local_rock_density = rock_density
				
				match ground_type:
					GroundTile.SAND:
						local_tree_density *= 0.3 # Fewer trees in sand
						local_bush_density *= 0.5 # Fewer bushes in sand
						local_rock_density *= 1.5 # More rocks in sand
					GroundTile.STONE:
						local_tree_density *= 0.5 # Fewer trees on stone
						local_bush_density *= 0.7 # Fewer bushes on stone
						local_rock_density *= 2.0 # More rocks on stone
				
				# Add foliage based on adjusted densities
				if detail_value < local_tree_density:
					tilemap.set_cell(1, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.TREE])
				elif detail_value < local_tree_density + local_bush_density:
					tilemap.set_cell(1, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.BUSH])
				elif detail_value < local_tree_density + local_bush_density + local_rock_density:
					tilemap.set_cell(1, pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.ROCK])

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
		tilemap.set_cells_terrain_connect(0, water_cells, 0, TERRAIN_SETS["water"])

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
		tilemap.set_cells_terrain_connect(0, river_cells, 0, TERRAIN_SETS["water"])

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = tilemap.get_cell_tile_data(0, coords)
	if not tile_data:
		return -1
	var terrain = tile_data.terrain
	# Map terrain back to ground tile type
	for tile in GROUND_TERRAIN_MAP:
		if TERRAIN_SETS[GROUND_TERRAIN_MAP[tile]] == terrain:
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

func place_building(pos: Vector2i, size: Vector2i, type: int) -> void:
	var template = STRUCTURE_TEMPLATES[type]
	print('placing building: ', type, ' at ', pos, ' with size ', size)
	
	# Place floors
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemap.set_cell(0, Vector2i(x, y), TILE_SOURCE_ID,
						   STRUCTURE_TILES[template.floor])
	
	# Place walls
	for x in range(pos.x, pos.x + size.x):
		tilemap.set_cell(1, Vector2i(x, pos.y), TILE_SOURCE_ID, STRUCTURE_TILES.WALL_H) # Top wall
		tilemap.set_cell(1, Vector2i(x, pos.y + size.y - 1), TILE_SOURCE_ID, STRUCTURE_TILES.WALL_H) # Bottom wall
	
	for y in range(pos.y, pos.y + size.y):
		tilemap.set_cell(1, Vector2i(pos.x, y), TILE_SOURCE_ID, STRUCTURE_TILES.WALL_V) # Left wall
		tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, y), TILE_SOURCE_ID, STRUCTURE_TILES.WALL_V) # Right wall
	
	# Place corners
	tilemap.set_cell(1, pos, TILE_SOURCE_ID, STRUCTURE_TILES.CORNER_NW)
	tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, pos.y), TILE_SOURCE_ID,
					 STRUCTURE_TILES.CORNER_NE)
	tilemap.set_cell(1, Vector2i(pos.x, pos.y + size.y - 1), TILE_SOURCE_ID,
					 STRUCTURE_TILES.CORNER_SW)
	tilemap.set_cell(1, Vector2i(pos.x + size.x - 1, pos.y + size.y - 1),
					 TILE_SOURCE_ID, STRUCTURE_TILES.CORNER_SE)
	
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
	tilemap.set_cell(2, door_pos, TILE_SOURCE_ID, STRUCTURE_TILES["DOOR"])

func generate_seed(world_position: Vector2i, terrain_type: int) -> int:
	# Combine position and terrain type into a deterministic seed
	# Using large prime numbers to minimize collisions
	return abs(world_position.x * 16777619 + world_position.y * 65537 + terrain_type * 257)
