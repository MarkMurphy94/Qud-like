extends Resource

class_name MapConfig

enum MapType {
	NON_SETTLEMENT, # Natural local area with possible hamlet, farm, etc.
	SETTLEMENT, # Towns, cities, etc.
	CASTLE_INTERIOR,
	DUNGEON,
}
enum BuildingDensity {
	NONE,
	SMALL_VILLAGE,
	LARGE_VILLAGE,
	SMALL_TOWN,
	LARGE_TOWN,
	CITY
}

enum MiscFeatures {
	HAMLET,
	FARM,
	DUNGEON_ENTRANCE,
	CAMP,
	RUIN,
	SHRINE_SITE,
	HIDDEN_SITE
}

## Bitmask flags for which edges of this local map have a road connection.
## NORTH=1, EAST=2, SOUTH=4, WEST=8.
## For settlement maps, set these manually in the editor.
## For non-settlement maps, they are auto-assigned by the world generator
## so that neighbouring tiles always have matching exits.
## e.g. if tile A has EAST set, tile B (to its east) will have WEST set.
enum RoadExit {
	NONE  = 0,
	NORTH = 1,
	EAST  = 2,
	SOUTH = 4,
	WEST  = 8,
}

enum Climate {
	TEMPERATE,
	COLD,
	HOT,
	ARID,
	TROPICAL
}

enum TerrainType {
	PLAINS,
	FOREST,
	MOUNTAIN,
	DESERT,
	SWAMP,
	COAST
}

enum Culture {
	MIDLANDS,
	COASTAL,
	HIGHLANDS,
	DESERT,
	TRIBAL
}

enum TreeDensity {
	NONE,
	SPARSE,
	FOREST,
}
# (12, 49), (31, 59), (37, 59), (59, 37), (47, 55), (30, 46), (83, 29), (29, 83), (49, 12), (59, 31), (59, 37), (37, 59)
@export_group("Technical Properties")
@export var noise_scale: float = 20.0
@export var overworld_tile: Vector2i
@export var scene_path: String
@export var SEED: int = 0
@export_group("Map Properties")
@export var map_name: String
@export var building_density: BuildingDensity = BuildingDensity.SMALL_VILLAGE
@export var buildings: Array[Structure] = []
@export var important_buildings: Array[Structure] = []
@export var important_npcs: Array[NPCConfig] = []
@export var map_type: MapType = MapType.NON_SETTLEMENT
@export var misc_features: Array[MiscFeatures] = []
@export var tree_density: TreeDensity = TreeDensity.NONE
@export var bush_density: float = 0.15
@export var rock_density: float = 0.08
@export var water_level: float = 0.4
@export var climate: Climate = Climate.TEMPERATE
@export var terrain: TerrainType = TerrainType.PLAINS
@export var culture: Culture = Culture.MIDLANDS

## Which edges of this local map have a road connection (bitmask of RoadExit flags).
## For non-settlement maps this is assigned automatically by the world generator;
## for settlement maps you can set it manually in the editor.
@export_flags("North:1", "East:2", "South:4", "West:8") var road_exits: int = 0
## Terrain type used to paint roads on the ground layer.
## Matches the keys in LocationGenerator.TERRAINS ("dirt", "stone").
@export_enum("dirt", "stone") var road_terrain: String = "dirt"

# TODO - coastal properties
# TODO - landscape features- rivers, etc.


# Save this resource to disk. Creates folders if needed.
func save_to_file(path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return ResourceSaver.save(self, path)

# Convenience: create, initialize, and save a new MapConfig
static func create_and_save(path: String, init: Dictionary = {}) -> Dictionary:
	var cfg := MapConfig.new()
	for k in init.keys():
		if cfg.has_property(k):
			cfg.set(k, init[k])
	# Ensure directory exists and save
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(cfg, path)
	return {"error": err, "resource": cfg}
