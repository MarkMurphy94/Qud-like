extends Resource

class_name AreaConfig

enum AreaType {
	LOCAL_AREA, # Natural local area with possible hamlet, farm, etc.
	TOWN, # Town settlement
	CITY, # City settlement
	CASTLE # Castle settlement
}


@export var noise_scale: float = 20.0
@export var tree_density: float = 0.1
@export var bush_density: float = 0.15
@export var rock_density: float = 0.08
@export var water_level: float = 0.4
@export var overworld_tile: Vector2i
@export var scene_path: String
@export var SEED: int = 0
@export var settlement_name: String
@export var buildings: Array[Structure] = []
@export var area_type: AreaType = AreaType.LOCAL_AREA # fix- there's AreaType and SettlementType
@export var climate: String
@export var culture: String # placeholder types

# TODO - coastal properties
# TODO - landscape features- rivers, etc.


# Save this resource to disk. Creates folders if needed.
func save_to_file(path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return ResourceSaver.save(self, path)

# Convenience: create, initialize, and save a new AreaConfig
static func create_and_save(path: String, init: Dictionary = {}) -> Dictionary:
	var cfg := AreaConfig.new()
	for k in init.keys():
		if cfg.has_property(k):
			cfg.set(k, init[k])
	# Ensure directory exists and save
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(cfg, path)
	return {"error": err, "resource": cfg}
