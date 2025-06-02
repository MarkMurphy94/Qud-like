extends Node2D

enum Tile {DEEP_WATER, SHALLOW_WATER, SAND, GRASS, MOUNTAIN, TOWN, CITY, CASTLE}

const TILE_COORDS = {
	Tile.DEEP_WATER: Vector2i(4, 13),
	Tile.SHALLOW_WATER: Vector2i(8, 13),
	Tile.SAND: Vector2i(10, 9),
	Tile.GRASS: Vector2i(4, 5),
	Tile.MOUNTAIN: Vector2i(9, 14),
	Tile.TOWN: Vector2i(4, 17),
	Tile.CITY: Vector2i(6, 18),
	Tile.CASTLE: Vector2i(5, 18)
}

const WIDTH = 80
const HEIGHT = 60

@export var num_landmasses: int = 3
@export var water_level: float = 0.4
@export var mountain_level: float = 0.7
@export_range(1, 100) var noise_scale: float = 50.0

@onready var tilemap = $TileMap
var rng = RandomNumberGenerator.new()
var noise: FastNoiseLite

@export var npc_scene: PackedScene
@export var npc_count: int = 10

func _ready():
	if not tilemap:
		push_error("TileMap node not found!")
		return
	
	generate_map()
	spawn_npcs()

func generate_map(custom_seed: int = -1) -> void:
	rng.seed = custom_seed if custom_seed != -1 else randi()
	initialize_noise()
	generate_terrain()
	add_landmasses()
	smooth_map()
	generate_settlements() # Only call once

func initialize_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.0 / noise_scale
	noise.fractal_octaves = 4

func generate_terrain() -> void:
	tilemap.clear()
	for y in HEIGHT:
		for x in WIDTH:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2 # Normalize to 0-1
			var tile = get_tile_from_height(height)
			tilemap.set_cell(0, Vector2i(x, y), 0, TILE_COORDS[tile])

func get_tile_from_height(height: float) -> int:
	if height < water_level - 0.1:
		return Tile.DEEP_WATER
	elif height < water_level:
		return Tile.SHALLOW_WATER
	elif height < water_level + 0.1:
		return Tile.SAND
	elif height < mountain_level:
		return Tile.GRASS
	else:
		return Tile.MOUNTAIN

func get_tile_type(coords: Vector2i) -> int:
	var atlas_coords = tilemap.get_cell_atlas_coords(0, coords)
	for tile in TILE_COORDS:
		if TILE_COORDS[tile] == atlas_coords:
			return tile
	return -1

func add_landmasses() -> void:
	for i in num_landmasses:
		var center_x = rng.randi_range(10, WIDTH - 10)
		var center_y = rng.randi_range(10, HEIGHT - 10)
		var size = rng.randi_range(5, 10)
		
		for y in range(-size, size + 1):
			for x in range(-size, size + 1):
				var dist = sqrt(x * x + y * y)
				if dist <= size:
					var map_x = center_x + x
					var map_y = center_y + y
					if map_y >= 0 and map_y < HEIGHT and map_x >= 0 and map_x < WIDTH:
						var pos = Vector2i(map_x, map_y)
						if get_tile_type(pos) == Tile.DEEP_WATER:
							tilemap.set_cell(0, pos, 0, TILE_COORDS[Tile.GRASS])

func smooth_map() -> void:
	var changes = []
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var pos = Vector2i(x, y)
			var current_tile = get_tile_type(pos)
			var grass_neighbors = 0
			var deep_water_neighbors = 0
			
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var neighbor_pos = Vector2i(x + dx, y + dy)
					var neighbor_type = get_tile_type(neighbor_pos)
					if neighbor_type == Tile.GRASS:
						grass_neighbors += 1
					elif neighbor_type == Tile.DEEP_WATER:
						deep_water_neighbors += 1
			
			if current_tile == Tile.DEEP_WATER and grass_neighbors >= 5:
				changes.append([pos, Tile.SHALLOW_WATER])
			elif current_tile == Tile.SHALLOW_WATER and deep_water_neighbors >= 5:
				changes.append([pos, Tile.DEEP_WATER])
	
	# Apply changes after analyzing the whole map
	for change in changes:
		tilemap.set_cell(0, change[0], 0, TILE_COORDS[change[1]])

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
	var tile_type = get_tile_type(pos)
	return tile_type not in [Tile.DEEP_WATER, Tile.SHALLOW_WATER]

func get_current_seed() -> int:
	return noise.seed

func spawn_npcs() -> void:
	if not npc_scene:
		push_error("NPC scene is not set!")
		return
	
	# Remove any existing NPCs first
	for child in get_children():
		if child.is_in_group("npcs"):
			child.queue_free()
	
	# Spawn new NPCs
	for _i in range(npc_count):
		var npc = npc_scene.instantiate()
		add_child(npc)
		npc.add_to_group("npcs")
		npc.initialize(self)

func generate_settlements() -> void:
	# Parameters for settlement generation
	var min_settlement_distance = {
		Tile.TOWN: 8, # Towns can be closer together
		Tile.CITY: 15, # Cities need more space
		Tile.CASTLE: 20 # Castles need the most space
	}
	
	var settlements_to_generate = {
		Tile.TOWN: rng.randi_range(4, 6), # 4-6 towns for local commerce
		Tile.CITY: rng.randi_range(2, 3), # 2-3 major cities
		Tile.CASTLE: rng.randi_range(1, 2) # 1-2 castles as power centers
	}
	
	var existing_settlements = [] # Track placed settlements
	
	# Generate settlements in order of importance (castles first, then cities, then towns)
	var settlement_order = [Tile.CASTLE, Tile.CITY, Tile.TOWN]
	
	for settlement_type in settlement_order:
		var count = settlements_to_generate[settlement_type]
		var attempts = 0
		var max_attempts = 200 # Increased attempts for better placement
		
		while count > 0 and attempts < max_attempts:
			var pos = Vector2i(
				rng.randi_range(5, WIDTH - 5),
				rng.randi_range(5, HEIGHT - 5)
			)
			
			# Check if position is suitable with type-specific distance
			if is_valid_settlement_position(pos, existing_settlements, min_settlement_distance[settlement_type], settlement_type):
				tilemap.set_cell(0, pos, 0, TILE_COORDS[settlement_type])
				existing_settlements.append([pos, settlement_type])
				count -= 1
				print("Placed ", settlement_type, " at ", pos)
			
			attempts += 1

func is_valid_settlement_position(pos: Vector2i, existing_settlements: Array, min_distance: int, settlement_type: int) -> bool:
	# Check if the tile is suitable for a settlement
	var current_tile = get_tile_type(pos)
	if current_tile != Tile.GRASS: # Settlements can only be placed on grass
		return false
	
	# Check distance from other settlements
	for settlement in existing_settlements:
		var settlement_pos = settlement[0] # Each settlement is [pos, type]
		var dx = abs(pos.x - settlement_pos.x)
		var dy = abs(pos.y - settlement_pos.y)
		var distance = sqrt(dx * dx + dy * dy)
		if distance < min_distance:
			return false
	
	# Different requirements based on settlement type
	var required_grass_tiles = 6 # Base requirement
	match settlement_type:
		Tile.CASTLE:
			required_grass_tiles = 12 # Castles need more flat land
		Tile.CITY:
			required_grass_tiles = 9 # Cities need medium amount
		Tile.TOWN:
			required_grass_tiles = 6 # Towns need least amount
	
	# Check surrounding area for suitability
	var grass_count = 0
	var check_radius = 3 if settlement_type == Tile.CASTLE else 2
	
	for y in range(-check_radius, check_radius + 1):
		for x in range(-check_radius, check_radius + 1):
			var check_pos = Vector2i(pos.x + x, pos.y + y)
			if check_pos.x >= 0 and check_pos.x < WIDTH and check_pos.y >= 0 and check_pos.y < HEIGHT:
				var tile = get_tile_type(check_pos)
				if tile == Tile.GRASS:
					grass_count += 1
	
	return grass_count >= required_grass_tiles
