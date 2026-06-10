@tool
extends Node2D

# ── TileMapLayer nodes ──────────────────────────────────────────────────────
# grassland_poneti.tres  → ground terrain, road, and terrain features
# temperate_medieval_village.tres → premade building sprites
@onready var ground: TileMapLayer = $base_terrain
@onready var road: TileMapLayer = $road
@onready var terrain_features: TileMapLayer = $terrain_features
@onready var structures_exterior: TileMapLayer = $structures_exterior
@onready var structures_interior: TileMapLayer = $structures_interior
@onready var foliage: TileMapLayer = $foliage

# Mirror of OverworldGenerator.Tile for reference
enum OverworldTile {WATER, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, DIRT, WATER}
enum FoliageTile {TREE, BUSH, ROCK}
enum TerrainFeatureTile {
	LARGE_DIRT_PATCH_1,
	LARGE_DIRT_PATCH_2,
	LARGE_DIRT_WITH_PUDDLES,
	SMALL_DIRT_PATCH_1,
	SMALL_DIRT_PATCH_2,
	SMALL_DIRT_PATCH_3,
	SMALL_DIRT_PATCH_4,
	CREVASSE_1,
	CREVASSE_2,
	ROCK_IN_DIRT_1,
	ROCK_IN_DIRT_2,
	ROCK_IN_DIRT_3,
	SMALL_PUDDLE_1,
	SMALL_PUDDLE_2,
	ROAD_PUDDLE_1,
	ROAD_PUDDLE_2,
	ROAD_GRASS_1,
	ROAD_GRASS_2,
	SMALL_LIGHT_GRASS_PATCH_1,
	SMALL_LIGHT_GRASS_PATCH_2,
	LIGHT_GRASS_PATCH_1,
	LIGHT_GRASS_PATCH_2,
	DARK_GRASS_PATCH_1,
	FLOWER_PATCH_1,
	FLOWER_PATCH_2,
	SMALL_ROCKS_1,
	SMALL_ROCKS_2,
	SMALL_ROCKS_3,
}
enum HamletStructureType {HOUSE, SHOP, TEMPLE, TOWER, WALL}

# Area generation types – mirrors MapConfig.MapType for backward compat.
# Settlement sub-types (town vs city vs castle) are now inferred from
# MapConfig.BuildingDensity and/or culture rather than hard-coded here.
enum MapType {
	NON_SETTLEMENT, # Natural local area with possible hamlet
	SETTLEMENT, # Towns, cities, etc.
	CASTLE_INTERIOR, # Interior of a castle
	DUNGEON # Dungeon level
}

# ── Source IDs within grassland_poneti.tres ─────────────────────────────────
const GROUND_SOURCE_ID = 0 # TileGrass.png – autotile terrain
const TERRAIN_FEATURE_SOURCE_ID = 0
const FEATURE_SOURCE_ID = 6 # TreeAndStoneSprites.png – trees, rocks, bushes

# ── Source IDs within temperate_medieval_village.tres ───────────────────────
const STRUCT_SOURCE_TOWERS = 1 # Towers.png
const STRUCT_SOURCE_TOWN = 2 # TownSprites.png
const STRUCT_SOURCE_VILLAGE = 3 # VillageBuildingSprites.png
const STRUCT_SOURCE_WOODEN = 5 # WoodenElements.png – fences, props

# ── Terrain set IDs (grassland_poneti.tres terrain set 0) ───────────────────
const TERRAINS = {
	"stone": 0, # change to new terrain set index when updated in grassland_poneti.tres
	"grass": 1,
	"dirt": 2,
	"water": 3, # change to new terrain set index when updated in grassland_poneti.tres
	"wheat_field": 4, # change to new terrain set index when updated in grassland_poneti.tres
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

const FOLIAGE_DATA = {
	FoliageTile.TREE: {"atlas": Vector2i(35, 14), "size": Vector2i(8, 13)},
	FoliageTile.BUSH: {"atlas": Vector2i(8, 38), "size": Vector2i(4, 3)},
	FoliageTile.ROCK: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
}
const TERRAIN_FEATURE_DATA = {
	# TODO:update atlas coords and sizes
	TerrainFeatureTile.LARGE_DIRT_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.LARGE_DIRT_PATCH_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.LARGE_DIRT_WITH_PUDDLES: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_DIRT_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_DIRT_PATCH_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_DIRT_PATCH_3: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_DIRT_PATCH_4: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.CREVASSE_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.CREVASSE_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROCK_IN_DIRT_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROCK_IN_DIRT_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROCK_IN_DIRT_3: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_PUDDLE_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_PUDDLE_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROAD_PUDDLE_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROAD_PUDDLE_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROAD_GRASS_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.ROAD_GRASS_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_LIGHT_GRASS_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_LIGHT_GRASS_PATCH_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.LIGHT_GRASS_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.LIGHT_GRASS_PATCH_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.DARK_GRASS_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.FLOWER_PATCH_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.FLOWER_PATCH_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_ROCKS_1: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_ROCKS_2: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
	TerrainFeatureTile.SMALL_ROCKS_3: {"atlas": Vector2i(17, 23), "size": Vector2i(3, 3)},
}

# ── Building sprite definitions (temperate_medieval_village.tres) ────────────
# Each entry maps a Structure.StructureType to the atlas coords of the premade
# exterior and interior sprites.  "size" is the sprite footprint in ground
# tiles (= size_in_atlas of the exterior sprite).
# IMPORTANT: verify these atlas coords against your tileset editor – they must
# match the actual sprite positions in VillageBuildingSprites.png / TownSprites.png.
const BUILDING_SPRITES = {
	Structure.StructureType.HOUSE: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(0, 0),
		"size": Vector2i(12, 10),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(0, 10),
		"interior_size": Vector2i(12, 7),
		"ground": "dirt",
		"spacing": 2,
	},
	Structure.StructureType.SHOP: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(26, 30),
		"size": Vector2i(13, 13),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(26, 43),
		"interior_size": Vector2i(13, 14),
		"ground": "stone",
		"spacing": 2,
	},
	Structure.StructureType.TAVERN: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(2, 25),
		"size": Vector2i(20, 16),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(1, 41),
		"interior_size": Vector2i(21, 17),
		"ground": "stone",
		"spacing": 3,
	},
	Structure.StructureType.MANOR: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(59, 0),
		"size": Vector2i(25, 20),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(59, 20),
		"interior_size": Vector2i(24, 16),
		"ground": "stone",
		"spacing": 4,
	},
}

# Maps the old HamletStructureType enum to Structure.StructureType so hamlet
# buildings can share the BUILDING_SPRITES table.
const HAMLET_TYPE_MAP = {
	HamletStructureType.HOUSE: Structure.StructureType.HOUSE,
	HamletStructureType.SHOP: Structure.StructureType.SHOP,
	HamletStructureType.TEMPLE: Structure.StructureType.TAVERN,
	HamletStructureType.TOWER: Structure.StructureType.HOUSE,
	HamletStructureType.WALL: Structure.StructureType.HOUSE,
}

const WIDTH = 80
const HEIGHT = 80
const TILE_SIZE = 16 # Pixel size per atlas cell (both tilesets)
const TERRAIN_SET_ID = 0 # Terrain set index in grassland_poneti.tres

# Default terrain type per settlement density tier.
# Replaces the old MapType-keyed SETTLEMENT_TERRAIN.
const SETTLEMENT_TERRAIN_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		"primary": "grass", "secondary": "grass", "paths": "dirt"
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": "stone"
	},
	MapConfig.BuildingDensity.CITY: {
		"primary": "grass", "secondary": "dirt", "paths": "stone"
	},
}

# How many of each building type to place per BuildingDensity tier.
const BUILDING_COUNTS_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		Structure.StructureType.HOUSE: 4,
		Structure.StructureType.TAVERN: 0,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		Structure.StructureType.HOUSE: 8,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		Structure.StructureType.HOUSE: 10,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 2,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		Structure.StructureType.HOUSE: 16,
		Structure.StructureType.TAVERN: 2,
		Structure.StructureType.SHOP: 3,
		Structure.StructureType.MANOR: 1,
	},
	MapConfig.BuildingDensity.CITY: {
		Structure.StructureType.HOUSE: 24,
		Structure.StructureType.TAVERN: 3,
		Structure.StructureType.SHOP: 4,
		Structure.StructureType.MANOR: 2,
	},
}

# Foliage density multipliers per MapConfig.TreeDensity enum.
# Values are lower than before because each foliage sprite now occupies many
# tiles (e.g. a tree is 6×8).  The used_cells check prevents overlapping.
const TREE_DENSITY_VALUES = {
	MapConfig.TreeDensity.NONE: 0.0,
	MapConfig.TreeDensity.SPARSE: 0.15,
	MapConfig.TreeDensity.FOREST: 0.30,
}

# Road generation parameters
const ROAD_WIDTH = 2
const PLAZA_MIN_SIZE = 4
const PLAZA_MAX_SIZE = 8
const PLAZA_DISTANCE_THRESHOLD = 10

@export var map_template: MapConfig

var noise: FastNoiseLite
var rng = RandomNumberGenerator.new()
# Overworld tile type enum value (OverworldTile); named to avoid clash with $base_terrain node
var base_terrain_type: int = OverworldTile.GRASS
var overworld_position: Vector2i
# Deterministic map seed to decouple sub-feature seeding from RNG consumption order
var current_map_seed: int = 0

func _ready() -> void:
	# Validate required TileMapLayer nodes
	for layer_node in [ground, road, terrain_features, structures_exterior, structures_interior]:
		if not layer_node:
			push_error("Missing TileMapLayer node in new_tileset_test_town scene!")
			return
	ground.clear()
	road.clear()
	terrain_features.clear()
	structures_exterior.clear()
	structures_interior.clear()
	noise = FastNoiseLite.new()
	setup_and_generate()

# Public function to generate either local areas or settlements
func setup_and_generate(
		map_type = map_template.map_type,
		overworld_tile_type: int = OverworldTile.GRASS,
		world_position: Vector2i = Vector2i.ZERO,
		seed_value: int = map_template.SEED
	) -> void:
	overworld_position = world_position
	var local_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		local_rng.seed = randi()
	else:
		local_rng.seed = seed_value

	match map_type:
		MapType.NON_SETTLEMENT:
			generate_local_area(overworld_tile_type, world_position, local_rng)
		MapType.SETTLEMENT, MapType.CASTLE_INTERIOR:
			# Ensure a config exists (seed/type/size/pos), then decide build vs generate
			# comment out the below block + indent generate_settlement() to use in editor
			if map_template.buildings and map_template.buildings.size() > 0:
				build_settlement_from_dataset()
			else:
				generate_settlement(local_rng)
			# npc_spawner.spawn_settlement_npcs(self)
	print("area seed is: ", local_rng.seed)

# Build a settlement from a saved dataset (no randomness in placement)
func build_settlement_from_dataset() -> void:
	ground.clear()
	road.clear()
	terrain_features.clear()
	structures_exterior.clear()
	structures_interior.clear()

	var area_size = Vector2i(WIDTH, HEIGHT)
	var settlement_rng := RandomNumberGenerator.new()
	settlement_rng.seed = int(map_template.SEED)
	var settlement_terrain = _get_settlement_terrain()
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
			ground.set_cells_terrain_connect(terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)

	current_map_seed = int(map_template.SEED)

	var placed_for_roads: Array = []
	for b: Structure in map_template.important_buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var pos: Vector2i = b.POSITION
		var size: Vector2i = sprite_def["size"]
		place_building_settlement(pos, size, enum_type)
		placed_for_roads.append({"type": enum_type, "pos": pos, "size": size})

	for b: Structure in map_template.buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var pos: Vector2i = b.POSITION
		var size: Vector2i = sprite_def["size"]
		place_building_settlement(pos, size, enum_type)
		placed_for_roads.append({"type": enum_type, "pos": pos, "size": size})

	generate_roads_between_buildings(placed_for_roads, RandomNumberGenerator.new())
	generate_edge_roads()
	add_terrain_features(RandomNumberGenerator.new())
	add_foliage()

func get_settlement_details() -> Dictionary:
	var details := {
		"type": int(map_template.map_type),
		"seed": map_template.SEED,
		"width": WIDTH,
		"height": HEIGHT,
		"pos": overworld_position,
		"buildings": {},
		"important_npcs": {}
	}
	var idx := 0
	for b: Structure in map_template.buildings:
		if b == null:
			continue
		var sprite_def = BUILDING_SPRITES.get(int(b.TYPE))
		var bsize: Vector2i = sprite_def["size"] if sprite_def else Vector2i(4, 4)
		var building_id = "%s_%d" % [str(b.TYPE).to_lower(), idx]
		details.buildings[building_id] = {
			"id": building_id,
			"type": int(b.TYPE),
			"pos": b.POSITION,
			"size": bsize,
			"zones": b.ZONES,
			"inhabitants": [],
			"interior_features": b.INTERIOR_FEATURES,
			"scripted_content": b.SCRIPTED_CONTENT
		}
		idx += 1
	return details

# Legacy function for backward compatibility
func setup_and_generate_local(overworld_tile_type: int, world_position: Vector2i, seed_value: int = 0) -> void:
	setup_and_generate(MapType.NON_SETTLEMENT, overworld_tile_type, world_position, seed_value)

func generate_local_area(overworld_tile_type: int, world_position: Vector2i, local_rng: RandomNumberGenerator) -> void:
	base_terrain_type = overworld_tile_type
	overworld_position = world_position
	print("Generating local area at position: ", world_position, " with terrain type: ", base_terrain_type)
	
	var map_seed = generate_seed(world_position, overworld_tile_type)
	current_map_seed = map_seed
	local_rng.seed = map_seed
	noise.seed = map_seed
	noise.frequency = 1.0 / map_template.noise_scale
	print("local area seed: ", map_seed, " for terrain: ", base_terrain_type)
	
	for terrain in terrain_cells:
		terrain_cells[terrain].clear()
	
	var area_size = Vector2i(WIDTH, HEIGHT)
	for y in area_size.y:
		for x in area_size.x:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2
			var ground_tile = get_ground_tile(x, y, height)
			var terrain_type = GROUND_TERRAIN_MAP[ground_tile]
			terrain_cells[terrain_type].append(Vector2i(x, y))
	
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			ground.set_cells_terrain_connect(
				terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)
	
	if base_terrain_type == OverworldTile.GRASS:
		maybe_add_water_features()
	
	_generate_misc_features(local_rng)
	generate_edge_roads()
	add_terrain_features(local_rng)
	add_foliage()

# Generate settlement function driven by MapConfig fields.
func generate_settlement(settlement_rng: RandomNumberGenerator) -> void:
	map_template.SEED = settlement_rng.seed
	var area_size = Vector2i(WIDTH, HEIGHT)
	var density: int = int(map_template.building_density)
	var building_counts: Dictionary = BUILDING_COUNTS_BY_DENSITY.get(density, {})
	print("Generating settlement '%s' density=%d  counts=%s" % [map_template.map_name, density, building_counts])

	ground.clear()
	road.clear()
	terrain_features.clear()
	structures_exterior.clear()
	structures_interior.clear()
	
	var settlement_terrain = _get_settlement_terrain()
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
			ground.set_cells_terrain_connect(
				terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)
		else:
			print("No cells for terrain type: ", terrain)

	current_map_seed = map_template.SEED

	var occupied_space_grid = []
	for y in area_size.y:
		occupied_space_grid.append([])
		for x in area_size.x:
			occupied_space_grid[y].append(false)

	var placed_buildings: Array = []

	for b: Structure in map_template.important_buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		var pos: Vector2i = b.POSITION
		if pos == Vector2i.ZERO:
			pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, enum_type)
			b.POSITION = pos
		if pos.x != -1:
			place_building_settlement(pos, size, enum_type)
			mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
			placed_buildings.append({"type": enum_type, "pos": pos, "size": size})

	var building_order = [Structure.StructureType.MANOR, Structure.StructureType.TAVERN, Structure.StructureType.SHOP, Structure.StructureType.HOUSE]
	for building_type in building_order:
		var count: int = building_counts.get(building_type, 0)
		var sprite_def = BUILDING_SPRITES.get(building_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		for _i in count:
			var pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, building_type)
			if pos.x != -1:
				place_building_settlement(pos, size, building_type)
				mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
				placed_buildings.append({"type": building_type, "pos": pos, "size": size})
				var s := Structure.new()
				s.TYPE = building_type
				s.POSITION = pos
				s.INTERIOR_SIZE = size
				s.ZONES = []
				s.INTERIOR_FEATURES = []
				s.SCRIPTED_CONTENT = null
				map_template.buildings.append(s)
	
	generate_roads_between_buildings(placed_buildings, settlement_rng)
	generate_edge_roads()
	add_terrain_features(settlement_rng)
	add_foliage()

	var details := get_settlement_details()
	details.type = int(map_template.map_type)
	details.seed = settlement_rng.seed

	print_rich("Generated settlement with ", map_template.buildings.size(), " buildings")

func get_ground_tile(_x: int, _y: int, height: float) -> int:
	if base_terrain_type == OverworldTile.GRASS:
		if height > 0.8:
			return GroundTile.STONE
		return GroundTile.GRASS
	if base_terrain_type == OverworldTile.MOUNTAIN:
		if height < 0.4:
			return GroundTile.GRASS
		elif height < 0.7:
			return GroundTile.DIRT
		return GroundTile.STONE
	if base_terrain_type == OverworldTile.WATER:
		return GroundTile.WATER
	return GroundTile.GRASS
			
func add_foliage() -> void:
	var detail_noise = FastNoiseLite.new()
	var derived_seed = int(current_map_seed) ^ (overworld_position.x * 73856093) ^ (overworld_position.y * 19349663) ^ int(base_terrain_type)
	detail_noise.seed = derived_seed
	detail_noise.frequency = 1.0 / (map_template.noise_scale * 0.5)

	# Track which cells are already covered by a placed multi-tile sprite
	var used_cells: Dictionary = {}

	for y in HEIGHT:
		for x in WIDTH:
			var pos = Vector2i(x, y)
			if used_cells.has(pos):
				continue

			# Skip if a road tile is present at this cell or within 1 tile
			var near_road := false
			for check_dy in range(-1, 2):
				for check_dx in range(-1, 2):
					if road.get_cell_source_id(pos + Vector2i(check_dx, check_dy)) != -1:
						near_road = true
						break
				if near_road:
					break
			if near_road:
				continue

			var ground_type = get_cell_ground_type(pos)
			if ground_type == -1:
				print("Could not determine ground type for cell %s, skipping foliage" % pos)
				continue

			var detail_value = (detail_noise.get_noise_2d(x, y) + 1) / 2

			if ground_type in [GroundTile.GRASS, GroundTile.DIRT, GroundTile.STONE]:
				var local_tree_density: float = TREE_DENSITY_VALUES.get(
					int(map_template.tree_density), 0.06)
				var local_bush_density: float = map_template.bush_density * 0.4
				var local_rock_density: float = map_template.rock_density

				match ground_type:
					GroundTile.DIRT:
						local_tree_density *= 0.3
						local_bush_density *= 0.5
						local_rock_density *= 1.5
					GroundTile.STONE:
						local_tree_density *= 0.5
						local_bush_density *= 0.7
						local_rock_density *= 2.0

				var foliage_type = -1
				if detail_value < local_tree_density:
					foliage_type = FoliageTile.TREE
				elif detail_value < local_tree_density + local_bush_density:
					foliage_type = FoliageTile.BUSH
				elif detail_value < local_tree_density + local_bush_density + local_rock_density:
					foliage_type = FoliageTile.ROCK

				if foliage_type != -1:
					var fdata: Dictionary = FOLIAGE_DATA[foliage_type]
					var fsize: Vector2i = fdata["size"]
					# Only place if the full sprite footprint is free
					var area_free = true
					for dy in fsize.y:
						for dx in fsize.x:
							if used_cells.has(pos + Vector2i(dx, dy)):
								area_free = false
								break
						if not area_free:
							break
					if area_free:
						terrain_features.set_cell(pos, FEATURE_SOURCE_ID, fdata["atlas"])
						# Mark every cell of this sprite as occupied
						for dy in fsize.y:
							for dx in fsize.x:
								used_cells[pos + Vector2i(dx, dy)] = true

func add_terrain_features(local_rng: RandomNumberGenerator) -> void:
	var feature_noise := FastNoiseLite.new()
	feature_noise.seed = int(current_map_seed) ^ 0xCAFEBABE
	feature_noise.frequency = 1.0 / (map_template.noise_scale * 0.3)

	# Features grouped by the ground type they suit
	var grass_features: Array[int] = [
		TerrainFeatureTile.SMALL_LIGHT_GRASS_PATCH_1,
		TerrainFeatureTile.SMALL_LIGHT_GRASS_PATCH_2,
		TerrainFeatureTile.LIGHT_GRASS_PATCH_1,
		TerrainFeatureTile.LIGHT_GRASS_PATCH_2,
		TerrainFeatureTile.DARK_GRASS_PATCH_1,
		TerrainFeatureTile.FLOWER_PATCH_1,
		TerrainFeatureTile.FLOWER_PATCH_2,
		TerrainFeatureTile.SMALL_PUDDLE_1,
		TerrainFeatureTile.SMALL_PUDDLE_2,
	]
	var dirt_features: Array[int] = [
		TerrainFeatureTile.LARGE_DIRT_PATCH_1,
		TerrainFeatureTile.LARGE_DIRT_PATCH_2,
		TerrainFeatureTile.LARGE_DIRT_WITH_PUDDLES,
		TerrainFeatureTile.SMALL_DIRT_PATCH_1,
		TerrainFeatureTile.SMALL_DIRT_PATCH_2,
		TerrainFeatureTile.SMALL_DIRT_PATCH_3,
		TerrainFeatureTile.SMALL_DIRT_PATCH_4,
		TerrainFeatureTile.ROCK_IN_DIRT_1,
		TerrainFeatureTile.ROCK_IN_DIRT_2,
		TerrainFeatureTile.ROCK_IN_DIRT_3,
		TerrainFeatureTile.SMALL_PUDDLE_1,
	]
	var stone_features: Array[int] = [
		TerrainFeatureTile.CREVASSE_1,
		TerrainFeatureTile.CREVASSE_2,
		TerrainFeatureTile.SMALL_ROCKS_1,
		TerrainFeatureTile.SMALL_ROCKS_2,
		TerrainFeatureTile.SMALL_ROCKS_3,
	]

	const FEATURE_DENSITY := 0.06
	var used_cells: Dictionary = {}

	for y in HEIGHT:
		for x in WIDTH:
			var pos := Vector2i(x, y)
			if used_cells.has(pos):
				continue

			# Skip if at or adjacent to a road tile
			var near_road := false
			for cdy in range(-1, 2):
				for cdx in range(-1, 2):
					if road.get_cell_source_id(pos + Vector2i(cdx, cdy)) != -1:
						near_road = true
						break
				if near_road:
					break
			if near_road:
				continue

			var ground_type := get_cell_ground_type(pos)
			if ground_type == -1 or ground_type == GroundTile.WATER:
				continue

			var noise_val := (feature_noise.get_noise_2d(x, y) + 1.0) / 2.0
			if noise_val >= FEATURE_DENSITY:
				continue

			# Pick a candidate list for this ground type
			var candidates: Array[int]
			match ground_type:
				GroundTile.GRASS:
					candidates = grass_features
				GroundTile.DIRT:
					candidates = dirt_features
				GroundTile.STONE:
					candidates = stone_features
				_:
					continue

			var feature_type: int = candidates[local_rng.randi() % candidates.size()]
			var fdata: Dictionary = TERRAIN_FEATURE_DATA[feature_type]
			var fsize: Vector2i = fdata["size"]

			# Verify the full footprint is free of existing features and roads
			var area_free := true
			for dy in fsize.y:
				for dx in fsize.x:
					var check := pos + Vector2i(dx, dy)
					if check.x >= WIDTH or check.y >= HEIGHT:
						area_free = false
						break
					if used_cells.has(check):
						area_free = false
						break
					if road.get_cell_source_id(check) != -1:
						area_free = false
						break
				if not area_free:
					break
			if not area_free:
				continue

			terrain_features.set_cell(pos, TERRAIN_FEATURE_SOURCE_ID, fdata["atlas"])
			for dy in fsize.y:
				for dx in fsize.x:
					used_cells[pos + Vector2i(dx, dy)] = true

func maybe_add_water_features(local_rng = null) -> void:
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
		ground.set_cells_terrain_connect(water_cells, TERRAIN_SET_ID, TERRAINS["water"])

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
		ground.set_cells_terrain_connect(river_cells, TERRAIN_SET_ID, TERRAINS["water"])

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = ground.get_cell_tile_data(coords)
	if not tile_data:
		return -1
	var terrain = tile_data.terrain
	for tile in GROUND_TERRAIN_MAP:
		if TERRAINS[GROUND_TERRAIN_MAP[tile]] == terrain:
			return tile
	return -1

func get_cell_foliage_type(coords: Vector2i) -> int:
	# Check the terrain_features layer for placed foliage
	if terrain_features.get_cell_source_id(coords) != FEATURE_SOURCE_ID:
		return -1
	var atlas_coords = terrain_features.get_cell_atlas_coords(coords)
	for foliage_type in FOLIAGE_DATA:
		if FOLIAGE_DATA[foliage_type]["atlas"] == atlas_coords:
			return foliage_type
	return -1

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
	var ground_type = get_cell_ground_type(pos)
	if ground_type == GroundTile.WATER:
		return false
	# Block if a foliage sprite root is at this position
	if terrain_features.get_cell_source_id(pos) == FEATURE_SOURCE_ID:
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

func try_place_building(hamlet_type: int, occupation_grid: Array, local_rng: RandomNumberGenerator) -> bool:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	if not sprite_def:
		return false
	var size: Vector2i = sprite_def["size"]
	var pos = find_valid_building_position(Vector2i(WIDTH, HEIGHT), size, occupation_grid, local_rng, hamlet_type)
	if pos.x == -1:
		return false
	place_building(pos, size, hamlet_type)
	mark_occupied(occupation_grid, pos, size, sprite_def["spacing"])
	return true

func find_valid_building_position(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, local_rng: RandomNumberGenerator, hamlet_type: int) -> Vector2i:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	var spacing: int = sprite_def["spacing"] if sprite_def else 1
	var attempts = 0
	
	while attempts < 100:
		var x = local_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = local_rng.randi_range(spacing, area_size.y - size.y - spacing)
		var valid = true
		
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x = x + dx
				var check_y = y + dy
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
			if not valid:
				break
		
		if valid:
			return Vector2i(x, y)
		attempts += 1
	
	return Vector2i(-1, -1)

func mark_occupied(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

# Place a hamlet building using a premade sprite
func place_building(pos: Vector2i, size: Vector2i, hamlet_type: int) -> void:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	if not sprite_def:
		push_warning("No BUILDING_SPRITES entry for hamlet type %d" % hamlet_type)
		return
	print("Placing hamlet building type %d at %s" % [hamlet_type, pos])
	_place_building_sprite(pos, size, sprite_def)

# Settlement-specific building functions
func find_valid_building_position_settlement(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, settlement_rng: RandomNumberGenerator, building_type: int) -> Vector2i:
	var sprite_def = BUILDING_SPRITES.get(building_type)
	var spacing: int = sprite_def["spacing"] if sprite_def else 1
	var attempts = 0
	var best_pos = Vector2i(-1, -1)
	var best_score = -1.0
	var center = Vector2(area_size.x / 2.0, area_size.y / 2.0)
	var max_distance = center.length()
	
	var density: int = int(map_template.building_density)
	var use_scoring: bool = density >= MapConfig.BuildingDensity.SMALL_TOWN
	var positions_to_try = 10 if use_scoring else 1
	
	while attempts < 100:
		var x = settlement_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = settlement_rng.randi_range(spacing, area_size.y - size.y - spacing)
		var valid = true
		
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x = x + dx
				var check_y = y + dy
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
			if not valid:
				break
		
		if valid:
			if not use_scoring:
				return Vector2i(x, y)
			var pos_center = Vector2(x + size.x / 2.0, y + size.y / 2.0)
			var distance = pos_center.distance_to(center)
			var score = 1.0 - (distance / max_distance)
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

# Place a settlement building using a premade sprite
func place_building_settlement(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var sprite_def = BUILDING_SPRITES.get(building_type)
	if not sprite_def:
		push_warning("No BUILDING_SPRITES entry for building type %d" % building_type)
		return
	print("Placing settlement building type %d at %s" % [building_type, pos])
	_place_building_sprite(pos, size, sprite_def)

# ── Shared sprite placement ────────────────────────────────────────────────
# Paints ground terrain under the footprint, clears foliage, then stamps the
# exterior and interior sprites onto their respective TileMapLayers.
# Both structure layers share the same coordinate space as the ground layer
# provided both tilesets use the same tile_size (default 16 × 16 px).
func _place_building_sprite(pos: Vector2i, size: Vector2i, sprite_def: Dictionary) -> void:
	# Seeded RNG for deterministic patch variation tied to building position
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = int(pos.x * 73856093) ^ int(pos.y * 19349663)

	# Patch is centered explicitly on the building's center tile so all four
	# sides have equal margin.  MIN_CLEAR tiles around the footprint are always
	# included; JITTER additional tiles are added probabilistically for organic
	# edges.
	const MIN_CLEAR := 2
	const JITTER    := 5
	var cx := pos.x + size.x / 2
	var cy := pos.y + size.y / 2

	var building_cells: Array[Vector2i] = []
	for dy in range(-(size.y / 2 + MIN_CLEAR + JITTER), size.y / 2 + MIN_CLEAR + JITTER + 1):
		for dx in range(-(size.x / 2 + MIN_CLEAR + JITTER), size.x / 2 + MIN_CLEAR + JITTER + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
				continue
			# Manhattan distance outside the building footprint
			var dist_x := 0
			if x < pos.x:
				dist_x = pos.x - x
			elif x >= pos.x + size.x:
				dist_x = x - (pos.x + size.x - 1)
			var dist_y := 0
			if y < pos.y:
				dist_y = pos.y - y
			elif y >= pos.y + size.y:
				dist_y = y - (pos.y + size.y - 1)
			var dist := dist_x + dist_y
			if dist <= MIN_CLEAR:
				building_cells.append(Vector2i(x, y))
			elif dist <= MIN_CLEAR + JITTER:
				var chance := 1.0 - float(dist - MIN_CLEAR) / float(JITTER + 1)
				if patch_rng.randf() < chance:
					building_cells.append(Vector2i(x, y))

	var gterrain: String = sprite_def.get("ground", "dirt")
	if TERRAINS.has(gterrain):
		road.set_cells_terrain_connect(building_cells, TERRAIN_SET_ID, TERRAINS[gterrain])

	# Clear foliage under the building
	for cell in building_cells:
		if terrain_features.get_cell_source_id(cell) != -1:
			terrain_features.set_cell(cell, -1)

	# Exterior sprite (what the player sees from outside / on the overworld layer)
	structures_exterior.set_cell(pos, sprite_def["exterior_source"], sprite_def["exterior_atlas"])

	# Interior sprite (floor/interior view shown when player enters)
	if sprite_def.has("interior_atlas"):
		structures_interior.set_cell(pos, sprite_def["interior_source"], sprite_def["interior_atlas"])

func generate_roads_between_buildings(placed_buildings: Array, _settlement_rng: RandomNumberGenerator) -> void:
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
			generate_road_between_buildings(building_a, building_b)

func generate_road_between_buildings(building_a: Dictionary, building_b: Dictionary) -> void:
	var start = get_door_position_settlement(building_a)
	var end = get_door_position_settlement(building_b)
	
	# Seeded RNG for deterministic variation unique to this road segment
	var road_rng := RandomNumberGenerator.new()
	road_rng.seed = int(start.x * 73856093) ^ int(start.y * 19349663) ^ int(end.x * 2654435761) ^ int(end.y * 805459861)
	
	var path = get_varied_path(start, end, road_rng)
	
	# Get appropriate road terrain type from the map config
	var surface: String = _get_settlement_terrain()["paths"]
	
	# Collect road cells, varying width per cell for an organic look
	var road_cells = []
	for pos in path:
		# Width is mostly 1 tile each side, occasionally 2
		var half_w: int = 1 if road_rng.randf() > 0.25 else 2
		for dx in range(-half_w, half_w + 1):
			for dy in range(-half_w, half_w + 1):
				var road_pos = pos + Vector2i(dx, dy)
				if road_pos.x >= 0 and road_pos.x < WIDTH and road_pos.y >= 0 and road_pos.y < HEIGHT:
					road_cells.append(road_pos)
	
	# Apply terrain change using terrain sets for proper transitions
	if road_cells.size() > 0:
		road.set_cells_terrain_connect(road_cells, TERRAIN_SET_ID, TERRAINS[surface])

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

# Like get_path_between_settlements but adds winding, irregular drift for a
# more organic, hand-laid road feel.  The road occasionally enters a "wander"
# mode where it drifts perpendicular to the goal for 1–5 steps before
# correcting, producing visible curves and bends.
func get_varied_path(start: Vector2i, end: Vector2i, path_rng: RandomNumberGenerator) -> Array:
	var path: Array = []
	var current := start
	var wander_steps := 0   # steps remaining in current sideways drift
	var wander_dir := 1     # perpendicular drift direction: +1 or -1

	# Safety cap: Manhattan distance × 4 so a very wandery road can't loop forever
	var max_steps = (abs(end.x - start.x) + abs(end.y - start.y)) * 4 + 10

	while current != end and path.size() < max_steps:
		path.append(current)
		var diff := end - current
		var dominant_x = abs(diff.x) >= abs(diff.y)

		# Occasionally start a new perpendicular wander burst
		if wander_steps <= 0 and path_rng.randf() < 0.25:
			wander_steps = path_rng.randi_range(2, 5)
			wander_dir = 1 if path_rng.randf() > 0.5 else -1

		if wander_steps > 0:
			# Move sideways relative to the dominant travel axis
			if dominant_x:
				# Travelling mostly horizontally → wander in Y
				var ny := current.y + wander_dir
				if ny >= 0 and ny < HEIGHT:
					current.y = ny
					wander_steps -= 1
				else:
					wander_steps = 0  # hit the map edge, abort wander
					current.x += sign(diff.x)
			else:
				# Travelling mostly vertically → wander in X
				var nx := current.x + wander_dir
				if nx >= 0 and nx < WIDTH:
					current.x = nx
					wander_steps -= 1
				else:
					wander_steps = 0
					current.y += sign(diff.y)
		else:
			# Normal progress toward the goal with a small jitter chance
			if dominant_x:
				if abs(diff.y) > 0 and path_rng.randf() < 0.1:
					current.y += sign(diff.y)
				else:
					current.x += sign(diff.x)
			else:
				if abs(diff.x) > 0 and path_rng.randf() < 0.1:
					current.x += sign(diff.x)
				else:
					current.y += sign(diff.y)

	path.append(end)
	return path

func generate_seed(world_position: Vector2i, terrain_type: int) -> int:
	return abs(world_position.x * 16777619 + world_position.y * 65537 + terrain_type * 257)

# ═══════════════════════════════════════════════════════════════════════
#  MAP-CONFIG DRIVEN HELPERS
# ═══════════════════════════════════════════════════════════════════════

## Return the settlement terrain palette (primary / secondary / paths)
## based on the current map_template.building_density.
func _get_settlement_terrain() -> Dictionary:
	var density: int = int(map_template.building_density)
	if SETTLEMENT_TERRAIN_BY_DENSITY.has(density):
		return SETTLEMENT_TERRAIN_BY_DENSITY[density]
	return SETTLEMENT_TERRAIN_BY_DENSITY[MapConfig.BuildingDensity.SMALL_VILLAGE]

## Draw road segments from each active edge midpoint to the map centre.
## Reads road_exits and road_terrain from map_template (MapConfig).
## Because the exit bitmask is assigned symmetrically by the world generator,
## a road that leaves this tile to the east will always enter the eastern
## neighbour from the west.
func generate_edge_roads() -> void:
	var exits: int = map_template.road_exits
	if exits == 0:
		return

	var center := Vector2i(WIDTH >> 1, HEIGHT >> 1)
	var road_half := ROAD_WIDTH >> 1

	# Collect edge entry points for every active exit direction
	var endpoints: Array[Vector2i] = []
	if exits & MapConfig.RoadExit.NORTH:
		endpoints.append(Vector2i(center.x, 0))
	if exits & MapConfig.RoadExit.SOUTH:
		endpoints.append(Vector2i(center.x, HEIGHT - 1))
	if exits & MapConfig.RoadExit.EAST:
		endpoints.append(Vector2i(WIDTH - 1, center.y))
	if exits & MapConfig.RoadExit.WEST:
		endpoints.append(Vector2i(0, center.y))

	if endpoints.is_empty():
		return

	# Choose road surface — fallback to "dirt" if the key is unknown
	var surface: String = map_template.road_terrain
	if not TERRAINS.has(surface):
		surface = "dirt"
	var road_terrain_id: int = TERRAINS[surface]

	# Seeded RNG for deterministic edge-road variation
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = int(map_template.SEED) ^ 0xDEADBEEF

	# Draw each road segment from the edge toward the centre
	var road_cells: Array[Vector2i] = []
	for ep: Vector2i in endpoints:
		var path: Array = get_varied_path(ep, center, edge_rng)
		for cell: Vector2i in path:
			# Vary width: mostly road_half, occasionally one wider
			var hw: int = road_half if edge_rng.randf() > 0.2 else road_half + 1
			for dx in range(-hw, hw + 1):
				for dy in range(-hw, hw + 1):
					var rp := cell + Vector2i(dx, dy)
					if rp.x >= 0 and rp.x < WIDTH and rp.y >= 0 and rp.y < HEIGHT:
						road_cells.append(rp)

	if road_cells.is_empty():
		return

	road.set_cells_terrain_connect(road_cells, TERRAIN_SET_ID, road_terrain_id, false)

## Process MapConfig.misc_features to place hamlets, farms, camps, etc.
## This replaces the old random 30% hamlet-chance logic with data-driven features.
func _generate_misc_features(local_rng: RandomNumberGenerator) -> void:
	for feature in map_template.misc_features:
		match feature:
			MapConfig.MiscFeatures.HAMLET:
				generate_hamlet("village", local_rng)
			MapConfig.MiscFeatures.FARM:
				generate_hamlet("farm", local_rng)
			MapConfig.MiscFeatures.DUNGEON_ENTRANCE:
				# TODO: generate dungeon entrance
				pass
			MapConfig.MiscFeatures.CAMP:
				# TODO: generate camp
				pass
			MapConfig.MiscFeatures.RUIN:
				# TODO: generate ruin
				pass
			MapConfig.MiscFeatures.SHRINE_SITE:
				# TODO: generate shrine site
				pass
			MapConfig.MiscFeatures.HIDDEN_SITE:
				# TODO: generate hidden site
				pass
