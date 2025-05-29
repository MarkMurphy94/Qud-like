extends Node2D

enum Tile {WALL = 0, FLOOR = 20}

const WIDTH = 50
const HEIGHT = 50
const MAX_STEPS = 1000
const MIN_FLOOR_PERCENTAGE = 0.3 # Minimum percentage of floor tiles

@onready var tilemap = $TileMap
var map = []
var rng = RandomNumberGenerator.new()

func _ready():
	if not tilemap:
		push_error("TileMap node not found!")
		return
	
	generate_map()
	draw_map()

func generate_map():
	rng.randomize()
	initialize_map()
	
	var walker_pos = Vector2i(WIDTH / 2, HEIGHT / 2)
	var floor_tiles = 0
	var total_tiles = (WIDTH - 2) * (HEIGHT - 2) # Excluding borders
	
	# Continue walking until we have enough floor tiles or reach max steps
	var steps = 0
	while steps < MAX_STEPS and float(floor_tiles) / total_tiles < MIN_FLOOR_PERCENTAGE:
		if map[walker_pos.y][walker_pos.x] == Tile.WALL:
			floor_tiles += 1
		map[walker_pos.y][walker_pos.x] = Tile.FLOOR
		
		# Random direction with diagonal movement
		var dir = Vector2i(
			rng.randi_range(-1, 1),
			rng.randi_range(-1, 1)
		)
		
		walker_pos += dir
		walker_pos.x = clamp(walker_pos.x, 1, WIDTH - 2)
		walker_pos.y = clamp(walker_pos.y, 1, HEIGHT - 2)
		steps += 1
	
	clean_up_map()

func initialize_map():
	map.clear()
	for y in HEIGHT:
		map.append([])
		for x in WIDTH:
			map[y].append(Tile.WALL)

func clean_up_map():
	# Remove single wall tiles surrounded by floors (smoothing)
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			if map[y][x] == Tile.WALL:
				var floor_neighbors = 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						if map[y + dy][x + dx] == Tile.FLOOR:
							floor_neighbors += 1
				
				if floor_neighbors >= 5: # If most neighbors are floor
					map[y][x] = Tile.FLOOR

func draw_map():
	tilemap.clear()
	for y in HEIGHT:
		for x in WIDTH:
			tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(map[y][x], 0))

# Returns the generated map for testing or further processing
func get_map() -> Array:
	return map
