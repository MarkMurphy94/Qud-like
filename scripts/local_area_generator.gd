# @tool
extends LocationGenerator

# Local-area focused wrapper around LocationGenerator.
# Generates natural (non-settlement) tiles using the parent helpers only.
# Metadata from the world generator (TileMetadata / Dictionary) is merged
# into map_template so the base-class helpers (add_foliage, generate_edge_roads,
# _generate_misc_features …) work transparently.

@export_category("Local Area Generation")
@export var overworld_tile_type: int = OverworldTile.GRASS
@export var world_position: Vector2i = Vector2i.ZERO
@export var seed_value: int = 0
@export var auto_generate_on_ready: bool = true

var current_metadata: Dictionary = {}

func _ready() -> void:
	# Don't rely on the base _ready, as it triggers general setup that may generate settlements.
	# We only need minimal setup for local areas: validate layers, clear them, init noise, then generate.
	if not _validate_layers():
		return

	_clear_all_layers()

	# Parent generation expects a noise instance to exist.
	noise = FastNoiseLite.new()
	if not map_template:
		map_template = MapConfig.new() # Fallback if not set by world generator

	if auto_generate_on_ready:
		generate_local_map(current_metadata)

func generate_local_map(metadata) -> void:
	# Accept either Dictionary or TileMetadata Resource; normalize to Dictionary
	if typeof(metadata) == TYPE_OBJECT and metadata is TileMetadata:
		current_metadata = (metadata as TileMetadata).to_dict()
	else:
		current_metadata = metadata
	if current_metadata.has("coords"):
		world_position = current_metadata["coords"]

	base_terrain = current_metadata.get("terrain", overworld_tile_type)
	overworld_position = world_position
	print("Generating local area at position: ", world_position, " with terrain type: ", base_terrain)

	# ── Sync metadata into map_template so base-class helpers work ──
	_apply_metadata_to_config()

	# Set up noise and RNG with deterministic seed from metadata
	var map_seed = current_metadata.get("seed", 0)
	current_map_seed = map_seed
	noise.seed = map_seed
	noise.frequency = 1.0 / map_template.noise_scale

	if not rng:
		rng = RandomNumberGenerator.new()
	rng.seed = map_seed

	print("local area seed: ", map_seed, " for terrain: ", base_terrain)

	# Initialize terrain cells for each type
	for terrain in terrain_cells:
		terrain_cells[terrain].clear()

	# Generate base terrain
	var area_size = Vector2i(WIDTH, HEIGHT)

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
		maybe_add_water_features(rng)

	# Add foliage (reads tree_density enum, bush_density, rock_density from map_template)
	add_foliage()

	# Generate misc features (hamlet, farm, dungeon entrance, etc.)
	_generate_misc_features(rng)

	# Paint edge roads from road_exits config (base-class helper)
	generate_edge_roads()

	# Connect terrain for proper transitions
	connect_terrain()

# ─── Metadata → MapConfig bridge ────────────────────────────────────

## Push relevant world-generator metadata fields into map_template so that
## every base-class helper (add_foliage, generate_edge_roads, _generate_misc_features)
## can read from a single authoritative source.
func _apply_metadata_to_config() -> void:
	# Road exits & surface
	map_template.road_exits = current_metadata.get("road_exits", 0)
	map_template.road_terrain = current_metadata.get("road_terrain", "dirt")

	# Foliage profile → tree_density enum + bush/rock floats
	var foliage: Dictionary = current_metadata.get("foliage_profile", {})
	if foliage.has("tree_density"):
		var td: float = foliage["tree_density"]
		if td <= 0.0:
			map_template.tree_density = MapConfig.TreeDensity.NONE
		elif td < 0.25:
			map_template.tree_density = MapConfig.TreeDensity.SPARSE
		else:
			map_template.tree_density = MapConfig.TreeDensity.FOREST
	if foliage.has("bush_density"):
		map_template.bush_density = foliage["bush_density"]
	if foliage.has("rock_density"):
		map_template.rock_density = foliage["rock_density"]

	# Misc features — translate legacy boolean fields into the enum array
	# that the base-class _generate_misc_features() reads.
	var features: Array[MapConfig.MiscFeatures] = []
	# Legacy boolean hamlet / farm
	if current_metadata.get("hamlet", false):
		features.append(MapConfig.MiscFeatures.HAMLET)
	if current_metadata.get("farm", false):
		var farm_data = current_metadata.get("farm_plot", null)
		if farm_data is Dictionary and farm_data.get("exists", false):
			features.append(MapConfig.MiscFeatures.FARM)
		elif current_metadata.get("farm", false) == true:
			features.append(MapConfig.MiscFeatures.FARM)
	# Structured TileMetadata fields
	var dungeon_data = current_metadata.get("dungeon_entrance", null)
	if dungeon_data is Dictionary and dungeon_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.DUNGEON_ENTRANCE)
	var camp_data = current_metadata.get("camp", null)
	if camp_data is Dictionary and camp_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.CAMP)
	var ruins_data = current_metadata.get("ruins", null)
	if ruins_data is Dictionary and ruins_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.RUIN)

	map_template.misc_features = features

# ─── Layer helpers ──────────────────────────────────────────────────

# Minimal validation that required TileMapLayer nodes exist (mirrors base expectations).
func _validate_layers() -> bool:
	for layer_key in LAYERS:
		if not tilemaps.has(layer_key) or tilemaps[layer_key] == null:
			push_error("TileMapLayer node for %s not found!" % layer_key)
			return false
	return true

# Clear all tilemap layers (ground, items, walls, etc.).
func _clear_all_layers() -> void:
	for layer_key in LAYERS:
		var tm = tilemaps[layer_key]
		if tm:
			tm.clear()
