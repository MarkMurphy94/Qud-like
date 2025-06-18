@tool
extends Node2D

# Signal to indicate when generation is complete
signal generation_completed

# Reference to necessary nodes and scenes
@onready var tilemap = $TileMap
@onready var settlement_generator = $SettlementGenerator

# Layer definitions
const LAYERS = {
	"GROUND": 0, # Ground terrain (grass, dirt, stone)
	"INTERIOR_FLOOR": 1, # Building floors
	"WALLS": 2, # Building walls
	"DOORS": 3, # Building doors
	"FURNITURE": 4, # Furniture
	"ITEMS": 5 # Items and decorations
}

# Terrain sets for better tile transitions
const TERRAINS = {
	"stone": 0, # Stone paths and plazas
	"grass": 1, # Natural grass areas
	"dirt": 2, # Dirt paths and yards
	"water": 3 # Water areas
}

const TERRAIN_SET_ID = 0 # The ID of the TerrainSet in the tileset
const TILE_SOURCE_ID = 5 # The ID of the TileSetAtlasSource in the tileset
const CITY_IMAGE_SIZE = Vector2i(80, 80) # Expected input image size

# Color mapping for different building types and terrain
const COLOR_MAPPING = {
	Color(0.2, 0.2, 0.2): "ROAD", # Dark gray for roads
	Color(0.5, 0.5, 0.5): "PLAZA", # Light gray for plazas
	Color(0.8, 0.4, 0.4): "HOUSE", # Red for houses
	Color(0.4, 0.4, 0.8): "TAVERN", # Blue for taverns
	Color(0.4, 0.8, 0.4): "SHOP", # Green for shops
	Color(0.8, 0.8, 0.4): "MANOR", # Yellow for manors
	Color(0.8, 0.4, 0.8): "CHURCH", # Purple for churches
	Color(0.4, 0.8, 0.8): "BARRACKS", # Cyan for barracks
	Color(0.1, 0.6, 0.1): "GRASS", # Dark green for grass
	Color(0.6, 0.4, 0.2): "DIRT", # Brown for dirt
	Color(0.7, 0.7, 0.7): "STONE", # Gray for stone paths
	Color(0.2, 0.4, 0.8): "WATER", # Blue for water
}

# Building type mapping
enum BuildingType {HOUSE, TAVERN, SHOP, MANOR, CHURCH, BARRACKS}

# Building size ranges
const BUILDING_SIZES = {
	"HOUSE": Vector2i(4, 4),
	"TAVERN": Vector2i(6, 6),
	"SHOP": Vector2i(5, 5),
	"MANOR": Vector2i(8, 8),
	"CHURCH": Vector2i(8, 8),
	"BARRACKS": Vector2i(8, 8),
}

const BUILDING_TYPE_MAPPING = {
	"HOUSE": BuildingType.HOUSE,
	"TAVERN": BuildingType.TAVERN,
	"SHOP": BuildingType.SHOP,
	"MANOR": BuildingType.MANOR,
	"CHURCH": BuildingType.CHURCH,
	"BARRACKS": BuildingType.BARRACKS,
}

# Path to the layout image
@export_file("*.png") var layout_image_path: String:
	set(value):
		layout_image_path = value
		if Engine.is_editor_hint() and layout_image_path:
			generate_from_image(layout_image_path)

var building_positions = []

# Method to load and process the image
func generate_from_image(image_path: String) -> void:
	if not tilemap:
		push_error("TileMap node not found!")
		return
		
	if not settlement_generator:
		push_error("SettlementGenerator node not found!")
		return
		
	var img = Image.load_from_file(image_path)
	if not img:
		push_error("Failed to load image from path: " + image_path)
		return
		
	# Resize image if needed
	if img.get_size() != CITY_IMAGE_SIZE:
		img.resize(CITY_IMAGE_SIZE.x, CITY_IMAGE_SIZE.y, Image.INTERPOLATE_NEAREST)
	
	# Clear existing tilemap
	tilemap.clear()
	building_positions.clear()
	
	# Process each pixel and place corresponding tiles
	for y in CITY_IMAGE_SIZE.y:
		for x in CITY_IMAGE_SIZE.x:
			var pixel_color = img.get_pixel(x, y)
			process_pixel(Vector2i(x, y), pixel_color)
	
	# Connect terrain after all tiles are placed
	connect_terrain()
	
	# Place buildings after terrain
	place_buildings()
	
	# Emit completion signal
	generation_completed.emit()

func process_pixel(pos: Vector2i, color: Color) -> void:
	# Find the closest matching color in our mapping
	var closest_type = find_closest_color_mapping(color)
	
	match closest_type:
		"ROAD", "PLAZA", "GRASS", "DIRT", "STONE", "WATER":
			place_terrain(pos, closest_type.to_lower())
		"HOUSE", "TAVERN", "SHOP", "MANOR", "CHURCH", "BARRACKS":
			# Store building position for later placement
			building_positions.append({
				"pos": pos,
				"type": closest_type
			})
			# Place appropriate ground under the building
			place_terrain(pos, "stone" if closest_type in ["MANOR", "SHOP", "TAVERN"] else "dirt")

func find_closest_color_mapping(color: Color) -> String:
	var min_distance = 1000000.0
	var closest_type = "GRASS" # Default to grass
	
	for mapping_color in COLOR_MAPPING:
		var r = color.r - mapping_color.r
		var g = color.g - mapping_color.g
		var b = color.b - mapping_color.b
		var distance = sqrt(r * r + g * g + b * b)
		
		if distance < min_distance:
			min_distance = distance
			closest_type = COLOR_MAPPING[mapping_color]
	
	return closest_type

func place_terrain(pos: Vector2i, terrain_type: String) -> void:
	tilemap.set_cells_terrain_connect(
		LAYERS.GROUND,
		[pos],
		TERRAIN_SET_ID,
		TERRAINS[terrain_type]
	)

func place_buildings() -> void:
	# Group adjacent building pixels of the same type
	var building_groups = group_building_pixels()
	
	# Place each building group
	for group in building_groups:
		var building_type = BUILDING_TYPE_MAPPING[group.type]
		var size = calculate_building_size(group.pixels)
		
		# Ensure minimum building size
		size.x = max(size.x, BUILDING_SIZES[group.type].x)
		size.y = max(size.y, BUILDING_SIZES[group.type].y)
		
		# Place the building using SettlementGenerator
		settlement_generator.place_building(group.pos, size, building_type)

func group_building_pixels() -> Array:
	var groups = []
	var processed = {}
	
	for building in building_positions:
		var pos = building.pos
		var pos_key = str(pos.x) + "," + str(pos.y)
		
		if processed.has(pos_key):
			continue
			
		var current_group = {
			"type": building.type,
			"pos": pos,
			"pixels": [pos]
		}
		
		# Flood fill to find connected pixels of the same building type
		var to_check = [pos]
		processed[pos_key] = true
		
		while not to_check.is_empty():
			var check_pos = to_check.pop_back()
			
			# Check adjacent pixels
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
						
					var next_pos = check_pos + Vector2i(dx, dy)
					var next_key = str(next_pos.x) + "," + str(next_pos.y)
					
					if processed.has(next_key):
						continue
						
					# Check if this position has a building of the same type
					for b in building_positions:
						if b.pos == next_pos and b.type == building.type:
							to_check.append(next_pos)
							current_group.pixels.append(next_pos)
							processed[next_key] = true
							break
		
		groups.append(current_group)
	
	return groups

func connect_terrain() -> void:
	var tiles = tilemap.get_used_cells(LAYERS.GROUND)
	var cells_by_terrain = {}
	
	# Group cells by their current terrain type
	for tile_pos in tiles:
		var cell_data = tilemap.get_cell_tile_data(LAYERS.GROUND, tile_pos)
		if not cell_data:
			continue
			
		var current_terrain = cell_data.terrain
		if not cells_by_terrain.has(current_terrain):
			cells_by_terrain[current_terrain] = []
		cells_by_terrain[current_terrain].append(tile_pos)
	
	# Apply terrain connections for each group
	for terrain in cells_by_terrain:
		tilemap.set_cells_terrain_connect(
			LAYERS.GROUND,
			cells_by_terrain[terrain],
			TERRAIN_SET_ID,
			terrain
		)

func calculate_building_size(pixels: Array) -> Vector2i:
	var min_x = 1000000
	var min_y = 1000000
	var max_x = -1000000
	var max_y = -1000000
	
	for pos in pixels:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
		max_x = max(max_x, pos.x)
		max_y = max(max_y, pos.y)
	
	return Vector2i(
		max_x - min_x + 1,
		max_y - min_y + 1
	)
