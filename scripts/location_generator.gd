# @tool
extends Node2D
class_name LocationGenerator

# Mirror of OverworldGenerator.Tile for reference
enum OverworldTile {WATER, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, DIRT, WATER}
enum FoliageTile {TREE, BUSH, ROCK}
enum HamletStructureType {HOUSE, SHOP, TEMPLE, TOWER, WALL}

# Area generation types
enum AreaType {
	LOCAL_AREA, # Natural local area with possible hamlet
	TOWN, # Town settlement
	CITY, # City settlement
	CASTLE # Castle settlement
}

# Terrain sets for ground tiles (matching LocationGenerator)
const TERRAINS = {
	"stone": 0, # Stone paths and plazas
	"grass": 1, # Natural grass areas
	"dirt": 2, # Dirt paths and yards
	"water": 3,
	"wheat_field": 4,
}

# Layer definitions matching LocationGenerator
const LAYERS = {
	"GROUND": 0,
	"INTERIOR_FLOOR": 1,
	"WALLS": 2,
	"FURNITURE": 3,
	"ITEMS": 4,
	"DOORS": 5,
	"ROOF": 6
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

# Map our enum types to terrain sets
const GROUND_TERRAIN_MAP = {
	GroundTile.STONE: "stone",
	GroundTile.GRASS: "grass",
	GroundTile.DIRT: "dirt",
	GroundTile.WATER: "water"
}

# Terrain cells for batch processing
var terrain_cells = {
	"stone": [],
	"grass": [],
	"dirt": [],
	"water": []
}

const FOLIAGE_COORDS = {
	FoliageTile.TREE: Vector2i(7, 4), # Tree tile
	FoliageTile.BUSH: Vector2i(8, 6), # Bush/shrub tile
	FoliageTile.ROCK: Vector2i(4, 8) # Boulder/rock tile
}

# Tile definitions matching LocationGenerator structure
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
	"RED_BRICK_WALL_H": Vector2i(31, 20),
	"RED_BRICK_WALL_H_INT": Vector2i(31, 20),
	"RED_BRICK_WALL_V_LEFT": Vector2i(28, 20),
	"RED_BRICK_WALL_V_RIGHT": Vector2i(28, 19),
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
}

const STRUCTURE_TEMPLATES = {
		HamletStructureType.HOUSE: {
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
		"ground": "DIRT",
		"spacing": 1
	},
		HamletStructureType.SHOP: {
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
		"ground": "STONE",
		"spacing": 2
	},
		HamletStructureType.TEMPLE: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_WOOD",
		"roof": "ROOF_RED",
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
		"ground": "GRASS",
		"spacing": 3
	},
		HamletStructureType.TOWER: {
		"min_size": Vector2i(4, 4),
		"max_size": Vector2i(6, 6),
		"floor": "FLOOR_STONE",
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
		"ground": "STONE",
		"spacing": 3
	},
		HamletStructureType.WALL: {
		"min_size": Vector2i(6, 6),
		"max_size": Vector2i(9, 9),
		"floor": "FLOOR_STONE",
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
		"ground": "STONE",
		"spacing": 3
	}
}

# (Legacy MainGameState enums removed; using Structure.StructureType and AreaType)

# Building templates for settlements (from LocationGenerator)
const BUILDING_TEMPLATES = {
		Structure.StructureType.HOUSE: {
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
		"ground": "DIRT",
		"spacing": 1
	},
		Structure.StructureType.TAVERN: {
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
		"ground": "STONE",
		"spacing": 2
	},
		Structure.StructureType.SHOP: {
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
		"ground": "STONE",
		"spacing": 2
	},
		Structure.StructureType.MANOR: {
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
		"ground": "STONE",
		"spacing": 3
	}
}

const WIDTH = 80 # Local area is more detailed, so larger
const HEIGHT = 80
const TILE_SIZE = 16 # Size of each tile in pixels
const TILE_SOURCE_ID = 5 # The ID of the TileSetAtlasSource in the tileset
const TERRAIN_SET_ID = 0 # The ID of the TerrainSetAtlasSource in the tileset

# Default terrain type for each settlement type (from LocationGenerator)
const SETTLEMENT_TERRAIN = {
		AreaType.TOWN: {
		"primary": "grass",
		"secondary": "grass",
		"paths": "dirt"
	},
		AreaType.CITY: {
		"primary": "grass",
		"secondary": "dirt",
		"paths": "stone"
	},
		AreaType.CASTLE: {
		"primary": "stone",
		"secondary": "dirt",
		"paths": "stone"
	}
}

# Road generation parameters (from LocationGenerator)
const ROAD_WIDTH = 2
const PLAZA_MIN_SIZE = 4
const PLAZA_MAX_SIZE = 8
const PLAZA_DISTANCE_THRESHOLD = 10

@export var area_template: AreaConfig

@onready var spawn_tile: Area2D = $spawn_tile
@onready var npc_spawner: NPCSpawner = $npc_spawner
@onready var ground: TileMapLayer = $ground

var noise: FastNoiseLite
var rng = RandomNumberGenerator.new()
var base_terrain: int = 1 # The overworld terrain type this area is based on, default = grass
var overworld_position: Vector2i

# Using area_template.buildings (Array[Structure]) as the authoritative building list

func _ready() -> void:
	# Check all tilemaps exist
	for layer in LAYERS:
		if not tilemaps.has(layer) or not tilemaps[layer]:
			push_error("TileMapLayer node for %s not found!" % layer)
			return
	
	# Clear and initialize all layers
	for layer in LAYERS:
		tilemaps[layer].clear()
	
	# Initialize noise
	noise = FastNoiseLite.new()
	# npc_spawner.settlement_data = area_template
	setup_and_generate() # un-comment to use in-editor

# Public function to generate either local areas or settlements
func setup_and_generate(
		area_type = area_template.area_type,
		overworld_tile_type: int = OverworldTile.GRASS,
		world_position: Vector2i = Vector2i.ZERO,
		seed_value: int = area_template.SEED
	) -> void:
	overworld_position = world_position
	var local_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		local_rng.seed = randi()
	else:
		local_rng.seed = seed_value

	match area_type:
		AreaType.LOCAL_AREA:
			generate_local_area(overworld_tile_type, world_position, local_rng)
		AreaType.TOWN, AreaType.CITY, AreaType.CASTLE:
			# Ensure a config exists (seed/type/size/pos), then decide build vs generate
			# comment out the below block + un-indent generate_settlement() to use in editor
			# if area_template.buildings and area_template.buildings.size() > 0:
			# 	build_settlement_from_dataset()
			# else:
			generate_settlement(area_type, local_rng)
			# npc_spawner.spawn_settlement_npcs(self)
	print("area seed is: ", local_rng.seed)

# Build a settlement from a saved dataset (no randomness in placement)
func build_settlement_from_dataset() -> void:
	# Clear layers
	for layer in LAYERS:
		tilemaps[layer].clear()
	# Lay base terrain deterministically using saved seed and type
	var area_size = Vector2i(WIDTH, HEIGHT)
	var settlement_rng := RandomNumberGenerator.new()
	settlement_rng.seed = int(area_template.SEED)
	var settlement_type: int = int(area_template.area_type)
	var settlement_terrain = SETTLEMENT_TERRAIN[settlement_type]
	for terrain in terrain_cells:
		terrain_cells[terrain].clear()
	for y in area_size.y:
		for x in area_size.x:
			var terrain_type: String
			var rand = settlement_rng.randf()
			if rand < 0.7:
				terrain_type = settlement_terrain["primary"]
			elif rand < 0.9:
				terrain_type = settlement_terrain["secondary"]
			else:
				terrain_type = "grass"
			terrain_cells[terrain_type].append(Vector2i(x, y))
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			tilemaps["GROUND"].set_cells_terrain_connect(terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)

	# Place buildings from resource array exactly as recorded
	var placed_for_roads: Array = []
	for b: Structure in area_template.buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var pos: Vector2i = b.POSITION
		var size: Vector2i = (b.INTERIOR_SIZE if b.INTERIOR_SIZE != Vector2i.ZERO else Vector2i(4, 4)) + Vector2i(2, 2)
		place_building_settlement(pos, size, enum_type)
		placed_for_roads.append({"type": enum_type, "pos": pos, "size": size})

	# Rebuild roads from building list
	generate_roads_between_buildings(placed_for_roads, RandomNumberGenerator.new(), settlement_type)
	connect_terrain()

# Gather compact dataset for persistence
func get_settlement_details() -> Dictionary:
	# Legacy summary using resource-backed data (useful for debugging/compat)
	var details := {
		"type": int(area_template.area_type),
		"seed": area_template.SEED,
		"width": WIDTH,
		"height": HEIGHT,
		"pos": overworld_position,
		"buildings": {},
		"important_npcs": {}
	}
	var idx := 0
	for b: Structure in area_template.buildings:
		if b == null:
			continue
		var outer_size: Vector2i = (b.INTERIOR_SIZE if b.INTERIOR_SIZE != Vector2i.ZERO else Vector2i(4, 4)) + Vector2i(2, 2)
		var building_id = "%s_%d" % [str(b.TYPE).to_lower(), idx]
		details.buildings[building_id] = {
			"id": building_id,
			"type": int(b.TYPE),
			"pos": b.POSITION,
			"size": outer_size,
			"zones": b.ZONES,
			"inhabitants": [],
			"interior_features": b.INTERIOR_FEATURES,
			"scripted_content": b.SCRIPTED_CONTENT
		}
		idx += 1
	return details

# Legacy function for backward compatibility
func setup_and_generate_local(overworld_tile_type: int, world_position: Vector2i, seed_value: int = 0) -> void:
	setup_and_generate(AreaType.LOCAL_AREA, overworld_tile_type, world_position, seed_value)

func generate_local_area(overworld_tile_type: int, world_position: Vector2i, local_rng: RandomNumberGenerator) -> void:
	base_terrain = overworld_tile_type
	overworld_position = world_position
	print("Generating local area at position: ", world_position, " with terrain type: ", base_terrain)
	
	# Set up noise and RNG with deterministic seed
	var map_seed = generate_seed(world_position, overworld_tile_type)
	local_rng.seed = map_seed
	noise.seed = map_seed
	noise.frequency = 1.0 / area_template.noise_scale
	print("local area seed: ", map_seed, " for terrain: ", base_terrain)
	
	# Initialize terrain cells for each type
	for terrain in terrain_cells:
		terrain_cells[terrain].clear()
	
	# Generate base terrain using the same structure as LocationGenerator
	var area_size = Vector2i(WIDTH, HEIGHT)
	
	# Set initial terrain and collect cells for each terrain type
	for y in area_size.y:
		for x in area_size.x:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2 # Normalize to 0-1
			
			var ground_tile = get_ground_tile(x, y, height)
			var terrain_type = GROUND_TERRAIN_MAP[ground_tile]
			
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
	
	# Add water features to appropriate terrains first
	if base_terrain == OverworldTile.GRASS:
		maybe_add_water_features()
	
	# Add foliage and details on items layer
	add_foliage()
	
	# Generate small settlement if on appropriate terrain
	if base_terrain == OverworldTile.GRASS:
		if local_rng.randf() < 0.3: # 30% chance for settlement
			var hamlet_type = "village"
			if local_rng.randf() < 0.3:
				hamlet_type = "farm"
			generate_hamlet(hamlet_type, local_rng)
	
	# Connect terrain for proper transitions
	connect_terrain()

# Generate settlement function (from LocationGenerator)
func generate_settlement(settlement_type: int, settlement_rng: RandomNumberGenerator) -> void:
	area_template.SEED = settlement_rng.seed
	var area_size = Vector2i(WIDTH, HEIGHT)
	var building_counts = {
			AreaType.TOWN: {
				Structure.StructureType.HOUSE: 10,
				Structure.StructureType.TAVERN: 1,
				Structure.StructureType.SHOP: 1,
				Structure.StructureType.MANOR: 0
		},
			AreaType.CITY: {
				Structure.StructureType.HOUSE: 20,
				Structure.StructureType.TAVERN: 3,
				Structure.StructureType.SHOP: 3,
				Structure.StructureType.MANOR: 4
		},
			AreaType.CASTLE: {
				Structure.StructureType.HOUSE: settlement_rng.randi_range(2, 4),
				Structure.StructureType.TAVERN: 0,
				Structure.StructureType.SHOP: 0,
				Structure.StructureType.MANOR: 1
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
			var rand = settlement_rng.randf()
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
	var placed_buildings: Array = []
	var building_order = [Structure.StructureType.MANOR, Structure.StructureType.TAVERN, Structure.StructureType.SHOP, Structure.StructureType.HOUSE]
	
	for building_type in building_order:
		var count = building_counts[settlement_type][building_type]
		for _i in count:
			var template = BUILDING_TEMPLATES[building_type]
			var size = Vector2i(
				settlement_rng.randi_range(template["min_size"].x, template["max_size"].x),
				settlement_rng.randi_range(template["min_size"].y, template["max_size"].y)
			)
			var pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, building_type, settlement_type)
			if pos.x != -1:
				place_building_settlement(pos, size, building_type)
				mark_occupied_settlement(occupied_space_grid, pos, size, template["spacing"])
				placed_buildings.append({"type": building_type, "pos": pos, "size": size})
				# Create and append a Structure resource instance
				var s := Structure.new()
				s.TYPE = building_type
				s.POSITION = pos
				s.INTERIOR_SIZE = size - Vector2i(2, 2)
				s.ZONES = []
				s.INTERIOR_FEATURES = []
				s.SCRIPTED_CONTENT = null
				area_template.buildings.append(s)
	
	# Generate roads between buildings
	generate_roads_between_buildings(placed_buildings, settlement_rng, settlement_type)
	
	# Connect terrain
	connect_terrain()
	# Persist and spawn using per-settlement dataset
	var details := get_settlement_details()
	details.type = settlement_type
	details.seed = settlement_rng.seed
	# print_rich("Settlement details: ", details)

	# comment out the below 3 lines for use in editor
	# var key = MainGameState.make_settlement_key(settlement_type, overworld_position)
	# MainGameState.add_settlement(key, details)
	print_rich("Generated settlement with ", area_template.buildings.size(), " buildings")

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
	detail_noise.frequency = 1.0 / (area_template.noise_scale * 0.5)
	
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
				var local_tree_density = area_template.tree_density
				var local_bush_density = area_template.bush_density
				var local_rock_density = area_template.rock_density
				
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
					tilemaps["ITEMS"].set_cell(pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.TREE])
				elif detail_value < local_tree_density + local_bush_density:
					tilemaps["ITEMS"].set_cell(pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.BUSH])
				elif detail_value < local_tree_density + local_bush_density + local_rock_density:
					tilemaps["ITEMS"].set_cell(pos, TILE_SOURCE_ID, FOLIAGE_COORDS[FoliageTile.ROCK])

func maybe_add_water_features(local_rng=null) -> void:
	# 30% chance to add a water feature
	if not local_rng:
		if rng.randf() > 0.3:
			return
		
		# Decide between lake or river
		if rng.randf() > 0.5:
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
			if dist <= size + rng.randf() * 2 - 1: # Irregular edges
				water_cells.append(pos)
	
	# Apply water terrain to all cells at once using the terrain system
	if water_cells.size() > 0:
		tilemaps["GROUND"].set_cells_terrain_connect(water_cells, TERRAIN_SET_ID, TERRAINS["water"])

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
			sign(dir.x) if rng.randf() > 0.3 else rng.randi_range(-1, 1),
			sign(dir.y)
		)
		current.x = clamp(current.x, 0, WIDTH - 1)
		current.y = clamp(current.y, 0, HEIGHT - 1)
	
	# Apply water terrain to all river cells at once using the terrain system
	if river_cells.size() > 0:
		tilemaps["GROUND"].set_cells_terrain_connect(river_cells, TERRAIN_SET_ID, TERRAINS["water"])

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = tilemaps["GROUND"].get_cell_tile_data(coords)
	if not tile_data:
		return -1
	var terrain = tile_data.terrain
	# Map terrain back to ground tile type
	for tile in GROUND_TERRAIN_MAP:
		if TERRAINS[GROUND_TERRAIN_MAP[tile]] == terrain:
			return tile
	return -1

func get_cell_foliage_type(coords: Vector2i) -> int:
	var atlas_coords = tilemaps["ITEMS"].get_cell_atlas_coords(coords) # Check foliage layer
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

func generate_hamlet(hamlet_type: String, local_rng: RandomNumberGenerator) -> void:
	var building_count = 0
	match hamlet_type:
		"village":
			building_count = local_rng.randi_range(3, 6)
		"farm":
			building_count = local_rng.randi_range(2, 4)
	
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
		var building_type = HamletStructureType.values()[local_rng.randi() % HamletStructureType.size()]
		if try_place_building(building_type, occupation_grid, local_rng):
			buildings_placed += 1
		attempts += 1

func try_place_building(building_type: int, occupation_grid: Array, local_rng: RandomNumberGenerator) -> bool:
	var template = STRUCTURE_TEMPLATES[building_type]
	var size = Vector2i(
		local_rng.randi_range(template.min_size.x, template.max_size.x),
		local_rng.randi_range(template.min_size.y, template.max_size.y)
	)
	
	# Find valid position using LocationGenerator-style logic
	var pos = find_valid_building_position(Vector2i(WIDTH, HEIGHT), size, occupation_grid, local_rng, building_type)
	if pos.x == -1:
		return false
	
	# Place building using LocationGenerator structure
	place_building(pos, size, building_type)
	
	# Mark area as occupied with spacing
	mark_occupied(occupation_grid, pos, size, template.spacing)
	
	return true

func find_valid_building_position(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, local_rng: RandomNumberGenerator, building_type: int) -> Vector2i:
	var template = STRUCTURE_TEMPLATES[building_type]
	var spacing = template["spacing"]
	var attempts = 0
	
	while attempts < 100:
		var x = local_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = local_rng.randi_range(spacing, area_size.y - size.y - spacing)
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
				
				# Check if terrain is walkable
				if not is_walkable(Vector2i(check_x, check_y)):
					valid = false
					break
					
			if not valid:
				break
		
		if valid:
			return Vector2i(x, y)
		
		attempts += 1
	
	return Vector2i(-1, -1) # No valid position found

func mark_occupied(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

# Update the place_building function to use LocationGenerator structure
func place_building(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var template = STRUCTURE_TEMPLATES[building_type]
	print('placing building: ', building_type, ' at ', pos, ' with size ', size)
	
	# Set base terrain for the building footprint and surroundings
	var building_cells = []
	for y in range(pos.y - 1, pos.y + size.y + 1):
		for x in range(pos.x - 1, pos.x + size.x + 1):
			if x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT:
				building_cells.append(Vector2i(x, y))
	
	# Apply terrain using set_cells_terrain_connect for proper transitions
	var ground_terrain = template["ground"].to_lower()
	if TERRAINS.has(ground_terrain):
		tilemaps["GROUND"].set_cells_terrain_connect(
			building_cells,
			TERRAIN_SET_ID,
			TERRAINS[ground_terrain]
		)
	
	# Place floor tiles on the interior floor layer
	for y in range(pos.y, pos.y + size.y):
		for x in range(pos.x, pos.x + size.x):
			tilemaps["INTERIOR_FLOOR"].set_cell(Vector2i(x, y), TILE_SOURCE_ID, STRUCTURE_TILES[template["floor"]])

	# Place walls on walls layer using LocationGenerator structure
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

# Settlement-specific building functions
func find_valid_building_position_settlement(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, settlement_rng: RandomNumberGenerator, building_type: int, settlement_type: int = AreaType.TOWN) -> Vector2i:
	var template = BUILDING_TEMPLATES[building_type]
	var spacing = template["spacing"]
	var attempts = 0
	var best_pos = Vector2i(-1, -1)
	var best_score = -1.0
	var center = Vector2(area_size.x / 2.0, area_size.y / 2.0)
	var max_distance = center.length()
	
	var positions_to_try = 10 if settlement_type == AreaType.TOWN else 1
	
	while attempts < 100:
		var x = settlement_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = settlement_rng.randi_range(spacing, area_size.y - size.y - spacing)
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
			if settlement_type != AreaType.TOWN:
				return Vector2i(x, y)
			
			# For towns, calculate score based on distance from center
			var pos_center = Vector2(x + size.x / 2.0, y + size.y / 2.0)
			var distance = pos_center.distance_to(center)
			var score = 1.0 - (distance / max_distance)
			
			# Add some randomness to avoid perfect circles
			score += settlement_rng.randf_range(-0.1, 0.1)
			
			if score > best_score:
				best_score = score
				best_pos = Vector2i(x, y)
			
			positions_to_try -= 1
			if positions_to_try <= 0:
				return best_pos
		
		attempts += 1
	
	return best_pos if best_pos.x != -1 else Vector2i(-1, -1)

func mark_occupied_settlement(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

func place_building_settlement(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var template = BUILDING_TEMPLATES[building_type]
	print("Placing settlement building of type ", building_type, " at ", pos, " with size ", size)
	
	# Set base terrain for the building footprint and surroundings
	var building_cells = []
	for y in range(pos.y - 1, pos.y + size.y + 1):
		for x in range(pos.x - 1, pos.x + size.x + 1):
			if x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT:
				building_cells.append(Vector2i(x, y))
	
	# Apply terrain using set_cells_terrain_connect for proper transitions
	var ground_terrain = template["ground"].to_lower()
	if TERRAINS.has(ground_terrain):
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

func generate_roads_between_buildings(placed_buildings: Array, _settlement_rng: RandomNumberGenerator, settlement_type: int) -> void:
	# Simple implementation - just connect buildings with paths
	for i in range(placed_buildings.size()):
		var building_a = placed_buildings[i]
		for j in range(i + 1, placed_buildings.size()):
			var building_b = placed_buildings[j]
			
			# Skip if buildings are too far apart
			var distance = (building_a["pos"] - building_b["pos"]).length()
			if distance > 20: # Maximum road distance
				continue
			
			# Generate simple road between buildings
			generate_road_between_settlements(building_a, building_b, settlement_type)

func generate_road_between_settlements(building_a: Dictionary, building_b: Dictionary, settlement_type: int) -> void:
	var start = get_door_position_settlement(building_a)
	var end = get_door_position_settlement(building_b)
	
	# Use simple line drawing to create road path
	var path = get_path_between_settlements(start, end)
	
	# Get appropriate road terrain type for this settlement
	var road_terrain = SETTLEMENT_TERRAIN[settlement_type]["paths"]
	
	# Collect road cells
	var road_cells = []
	var road_half_width = ROAD_WIDTH >> 1
	
	# Generate road positions
	for pos in path:
		for dx in range(-road_half_width, road_half_width + 1):
			for dy in range(-road_half_width, road_half_width + 1):
				var road_pos = pos + Vector2i(dx, dy)
				if road_pos.x >= 0 and road_pos.x < WIDTH and road_pos.y >= 0 and road_pos.y < HEIGHT:
					road_cells.append(road_pos)
	
	# Apply terrain change using terrain sets for proper transitions
	if road_cells.size() > 0:
		tilemaps["GROUND"].set_cells_terrain_connect(
			road_cells,
			TERRAIN_SET_ID,
			TERRAINS[road_terrain]
		)

func get_door_position_settlement(building: Dictionary) -> Vector2i:
	# Returns the center of the south wall of the building as the door position
	return Vector2i(
		building["pos"].x + (building["size"].x >> 1),
		building["pos"].y + building["size"].y - 1
	)

func get_path_between_settlements(start: Vector2i, end: Vector2i) -> Array:
	# Simple Manhattan line-drawing path
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
