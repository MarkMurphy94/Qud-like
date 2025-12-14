# @tool
extends LocationGenerator

# Local-area focused wrapper around LocationGenerator.
# Generates natural (non-settlement) tiles using the parent helpers only.

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

	if auto_generate_on_ready:
		generate_local_map(current_metadata)

func generate_local_map(metadata) -> void:
	current_metadata = metadata
	if metadata.has("coords"):
		world_position = metadata["coords"]

	base_terrain = metadata.get("terrain", overworld_tile_type)
	overworld_position = world_position
	print("Generating local area at position: ", world_position, " with terrain type: ", base_terrain)
	
	# Set up noise and RNG with deterministic seed from metadata
	var map_seed = metadata.get("seed", 0)
	noise.seed = map_seed
	noise.frequency = 1.0 / 50.0 # Default fallback
	
	# Initialize RNG with the seed for deterministic generation
	# Store in parent's rng variable so all parent class methods use the same seeded RNG
	if not rng:
		rng = RandomNumberGenerator.new()
	rng.seed = map_seed
	
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
		maybe_add_water_features(rng)
	
	# Seed the RNG again before foliage to ensure consistent flower placement
	# rng.seed = map_seed
	
	# Add foliage and details on items layer
	add_foliage()
	
	# Generate features based on metadata if available
	if not current_metadata.is_empty():
		if current_metadata.get("hamlet", false):
			generate_hamlet("village", rng)
		elif current_metadata.get("farm", false):
			generate_hamlet("farm", rng)
			
		if current_metadata.get("camp", false):
			# TODO: Implement camp generation
			pass
			
		if current_metadata.get("dungeon_entrance", false):
			# TODO: Implement dungeon entrance generation
			pass
	else:
		# Fallback to random generation if no metadata
		if base_terrain == OverworldTile.GRASS:
			if rng.randf() < 0.3: # 30% chance for settlement
				var hamlet_type = "village"
				if rng.randf() < 0.3:
					hamlet_type = "farm"
				generate_hamlet(hamlet_type, rng)
	
	# Connect terrain for proper transitions
	connect_terrain()

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
