@tool
extends Node2D

enum Tile {
	NONE = -1,
	DEEP_WATER,
	SHALLOW_WATER,
	SAND,
	GRASS,
	MOUNTAIN,
	TOWN,
	CITY,
	CASTLE
}

# Terrain sets for better tile transitions
const TERRAIN_SETS = {
	"grass": 0, # Plains and grass
	"water": 1, # Deep and shallow water
	"beach": 0, # Sand and coastal areas
	"mountain": 0 # Hills and peaks
}

# Map tile types to terrain sets
const TILE_TO_TERRAIN = {
	Tile.DEEP_WATER: "water",
	Tile.SHALLOW_WATER: "water",
	Tile.SAND: "grass",
	Tile.GRASS: "grass",
	Tile.MOUNTAIN: "grass"
}

# Special tiles that don't use terrain sets
const SETTLEMENT_COORDS = {
	Tile.TOWN: Vector2i(4, 17),
	Tile.CITY: Vector2i(6, 18),
	Tile.CASTLE: Vector2i(5, 18)
}

const TILESET_ATLAS_ID = 3
const WIDTH = 80
const HEIGHT = 60
const MAX_PLACEMENT_ATTEMPTS = 100

# Water level is normalized between -1 and 1
const water_level = -0.2
const mountain_level = 0.3

@export var num_landmasses: int = 3
@export_range(1, 100) var noise_scale: float = 50.0
@export var npc_scene: PackedScene
@export var npc_count: int = 10
@onready var tilemap = $TileMap

var rng = RandomNumberGenerator.new()
var noise: FastNoiseLite
var settle_noise: FastNoiseLite

const max_settlements = {
	Tile.CASTLE: 2,
	Tile.CITY: 4,
	Tile.TOWN: 8
}

const min_settlement_distance = {
	Tile.CASTLE: 20,
	Tile.CITY: 15,
	Tile.TOWN: 10
}

func _ready() -> void:
	var seed_val = randi()
	initialize_noise(seed_val)
	generate_terrain()
	generate_settlements()
	spawn_npcs()

func generate_map(custom_seed: int = -1) -> void:
	var seed_val = custom_seed if custom_seed != -1 else randi()
	rng.seed = seed_val
	initialize_noise(seed_val)
	generate_terrain()
	add_landmasses()
	smooth_map()
	generate_settlements()

func initialize_noise(seed_val: int) -> void:
	noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.frequency = 0.02
	
	settle_noise = FastNoiseLite.new()
	settle_noise.seed = seed_val + 1
	settle_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	settle_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	settle_noise.frequency = 0.01

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

func generate_terrain() -> void:
	# Initialize empty arrays for each terrain type
	var terrain_cells = {}
	for terrain in TERRAIN_SETS:
		terrain_cells[terrain] = []
	
	# Generate terrain based on height
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var coords = Vector2i(x, y)
			var height = noise.get_noise_2d(x, y)
			var tile_type = get_tile_from_height(height)
			var terrain = TILE_TO_TERRAIN[tile_type]
			terrain_cells[terrain].append(coords)
	
	# Apply all terrains using terrain sets for proper transitions
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			tilemap.set_cells_terrain_connect(0, terrain_cells[terrain], 0, TERRAIN_SETS[terrain])

func get_tile_type(coords: Vector2i) -> int:
	if coords.x < 0 or coords.x >= WIDTH or coords.y < 0 or coords.y >= HEIGHT:
		return Tile.NONE
		
	var tile_data = tilemap.get_cell_tile_data(TILESET_ATLAS_ID, coords)
	if tile_data == null:
		return Tile.NONE
	
	var terrain_id = tile_data.terrain
	# Convert terrain ID back to tile type
	for tile in TILE_TO_TERRAIN:
		if TERRAIN_SETS[TILE_TO_TERRAIN[tile]] == terrain_id:
			return tile
	
	# Special case for settlements which don't use terrain
	var atlas_coords = tilemap.get_cell_atlas_coords(0, coords)
	for settlement_type in SETTLEMENT_COORDS:
		if SETTLEMENT_COORDS[settlement_type] == atlas_coords:
			return settlement_type
			
	return Tile.NONE


func add_landmasses() -> void:
	for i in num_landmasses:
		var center_x = rng.randi_range(10, WIDTH - 10)
		var center_y = rng.randi_range(10, HEIGHT - 10)
		var size = rng.randi_range(5, 10)
		
		var land_cells = []
		var beach_cells = []
		
		for y in range(-size, size + 1):
			for x in range(-size, size + 1):
				var dist = sqrt(x * x + y * y)
				if dist <= size:
					var map_x = center_x + x
					var map_y = center_y + y
					if map_y >= 0 and map_y < HEIGHT and map_x >= 0 and map_x < WIDTH:
						var pos = Vector2i(map_x, map_y)
						if get_tile_type(pos) == Tile.DEEP_WATER:
							if dist >= size - 1:
								beach_cells.append(pos)
							else:
								land_cells.append(pos)
		
		# Apply terrains for smooth transitions
		if beach_cells.size() > 0:
			tilemap.set_cells_terrain_connect(0, beach_cells, 0, TERRAIN_SETS["beach"])
		if land_cells.size() > 0:
			tilemap.set_cells_terrain_connect(0, land_cells, 0, TERRAIN_SETS["grass"])

func smooth_map() -> void:
	var terrain_changes = {
		"water": [],
		"beach": [],
		"grass": [],
		"mountain": []
	}
	
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var pos = Vector2i(x, y)
			var current_tile = get_tile_type(pos)
			var neighbors = count_neighbors(pos)
			
			# Create beach transitions between water and land
			if current_tile in [Tile.DEEP_WATER, Tile.SHALLOW_WATER] and neighbors["grass"] >= 3:
				terrain_changes["beach"].append(pos)
			elif current_tile == Tile.GRASS and neighbors["water"] >= 4:
				terrain_changes["beach"].append(pos)
			
			# Create mountain transitions
			elif current_tile == Tile.GRASS and neighbors["mountain"] >= 5:
				terrain_changes["mountain"].append(pos)
			elif current_tile == Tile.MOUNTAIN and neighbors["grass"] >= 6:
				terrain_changes["grass"].append(pos)
	
	# Apply terrain changes using terrain sets
	for terrain_type in terrain_changes:
		if not terrain_changes[terrain_type].is_empty():
			tilemap.set_cells_terrain_connect(0, terrain_changes[terrain_type], 0, TERRAIN_SETS[terrain_type])

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
	var existing_settlements = []
	
	# Generate settlements in priority order: castles, cities, towns
	for settlement_type in [Tile.CASTLE, Tile.CITY, Tile.TOWN]:
		var settlement_count = max_settlements[settlement_type]
		var attempts = 0
		var placed = 0
		
		while placed < settlement_count and attempts < MAX_PLACEMENT_ATTEMPTS:
			attempts += 1
			var pos = Vector2i(
				randi() % (WIDTH - 4) + 2,
				randi() % (HEIGHT - 4) + 2
			)
			
			if is_valid_settlement_position(pos, existing_settlements, min_settlement_distance[settlement_type], settlement_type):
				tilemap.set_cell(0, pos, 0, SETTLEMENT_COORDS[settlement_type])
				existing_settlements.append([pos, settlement_type])
				placed += 1

func is_valid_settlement_position(pos: Vector2i, existing_settlements: Array, min_distance: int, settlement_type: int) -> bool:
	# Check if tile is walkable (not water or mountain)
	if not is_walkable(pos):
		return false
		
	# Check distance from other settlements
	for settlement in existing_settlements:
		var settlement_pos: Vector2i = settlement[0]
		var dist = sqrt(pow(pos.x - settlement_pos.x, 2) + pow(pos.y - settlement_pos.y, 2))
		if dist < min_distance:
			return false
	
	# Additional terrain checks based on settlement type
	var surrounding_tiles = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			var check_pos = pos + Vector2i(x, y)
			if check_pos.x >= 0 and check_pos.x < WIDTH and check_pos.y >= 0 and check_pos.y < HEIGHT:
				var tile = get_tile_type(check_pos)
				surrounding_tiles.append(tile)
	
	match settlement_type:
		Tile.CASTLE:
			# Castles prefer elevated terrain
			var mountain_count = surrounding_tiles.count(Tile.MOUNTAIN)
			return mountain_count >= 2
		Tile.CITY:
			# Cities need mostly flat terrain
			var grass_count = surrounding_tiles.count(Tile.GRASS)
			return grass_count >= 6
		Tile.TOWN:
			# Towns can be anywhere walkable (already checked)
			return true
	
	return false

func count_neighbors(pos: Vector2i) -> Dictionary:
	var counts = {
		"water": 0,
		"grass": 0,
		"beach": 0,
		"mountain": 0
	}
	
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor_pos = Vector2i(pos.x + dx, pos.y + dy)
			var neighbor_type = get_tile_type(neighbor_pos)
			var terrain = TILE_TO_TERRAIN.get(neighbor_type)
			if terrain:
				counts[terrain] += 1
	
	return counts
