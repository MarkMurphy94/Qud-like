extends Node2D

# Mirror of OverworldGenerator.Tile for local reference
enum OverworldTile {DEEP_WATER, SHALLOW_WATER, SAND, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, SAND, WATER}
enum FoliageTile {TREE, BUSH, ROCK}

# Atlas coordinates for the Roguelike_Ground_merged tileset
const GROUND_COORDS = {
	GroundTile.GRASS: Vector2i(1, 1), # Green grass tile
	GroundTile.STONE: Vector2i(0, 13), # Gray stone tile
	GroundTile.SAND: Vector2i(10, 1), # Sand/dirt tile
	GroundTile.WATER: Vector2i(74, 2) # Blue water tile
}

const FOLIAGE_COORDS = {
	FoliageTile.TREE: Vector2i(4, 28), # Tree tile
	FoliageTile.BUSH: Vector2i(4, 31), # Bush/shrub tile
	FoliageTile.ROCK: Vector2i(4, 32) # Boulder/rock tile
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
	generate_map()
	
func _ready() -> void:
	if not tilemap:
		push_error("TileMap node not found!")
		return
	noise = FastNoiseLite.new()
	rng.randomize()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / noise_scale

func generate_map() -> void:
	if not tilemap:
		push_error("TileMap is null!")
		return
	print("Generating map with base terrain: ", base_terrain)
	tilemap.clear()
	
	# Generate base terrain on ground layer (layer 0)
	for y in HEIGHT:
		for x in WIDTH:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2 # Normalize to 0-1
			
			var ground_tile = get_ground_tile(x, y, height)
			tilemap.set_cell(0, Vector2i(x, y), TILE_SOURCE_ID, GROUND_COORDS[ground_tile])
	
	# Add water features to appropriate terrains first
	if base_terrain in [OverworldTile.GRASS, OverworldTile.SAND]:
		maybe_add_water_features()
	
	# Add foliage and details on foliage layer (layer 1)
	add_foliage()

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
	
	for y in range(-size, size + 1):
		for x in range(-size, size + 1):
			var pos = center + Vector2i(x, y)
			if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
				continue
			
			var dist = sqrt(x * x + y * y)
			if dist <= size + randf() * 2 - 1: # Irregular edges
				tilemap.set_cell(0, pos, TILE_SOURCE_ID, GROUND_COORDS[GroundTile.WATER])

func generate_river() -> void:
	var start = Vector2i(
		rng.randi_range(0, WIDTH),
		0 if rng.randi() % 2 == 0 else HEIGHT - 1
	)
	var end = Vector2i(
		rng.randi_range(0, WIDTH),
		HEIGHT - 1 if start.y == 0 else 0
	)
	
	var current = start
	while current != end:
		tilemap.set_cell(0, current, TILE_SOURCE_ID, GROUND_COORDS[GroundTile.WATER])
		
		# Move towards end with some randomness
		var dir = Vector2(end - current).normalized()
		current += Vector2i(
			sign(dir.x) if randf() > 0.3 else rng.randi_range(-1, 1),
			sign(dir.y)
		)
		current.x = clamp(current.x, 0, WIDTH - 1)
		current.y = clamp(current.y, 0, HEIGHT - 1)

func get_cell_ground_type(coords: Vector2i) -> int:
	var atlas_coords = tilemap.get_cell_atlas_coords(0, coords) # Check ground layer
	for tile in GROUND_COORDS:
		if GROUND_COORDS[tile] == atlas_coords:
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
