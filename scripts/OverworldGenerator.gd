extends Node2D

enum Tile {DEEP_WATER, SHALLOW_WATER, SAND, GRASS, MOUNTAIN}

const TILE_COORDS = {
	Tile.DEEP_WATER: Vector2i(4, 13),
	Tile.SHALLOW_WATER: Vector2i(8, 13),
	Tile.SAND: Vector2i(10, 9),
	Tile.GRASS: Vector2i(4, 5),
	Tile.MOUNTAIN: Vector2i(9, 14)
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
