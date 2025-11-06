@tool
extends LocationGenerator

# Local-area focused wrapper around LocationGenerator.
# Generates natural (non-settlement) tiles using the parent helpers only.

@export_category("Local Area Generation")
@export var overworld_tile_type: int = OverworldTile.GRASS
@export var world_position: Vector2i = Vector2i.ZERO
@export var seed_value: int = 0
@export var auto_generate_on_ready: bool = true

func _ready() -> void:
	# Don't rely on the base _ready, as it triggers general setup that may generate settlements.
	# We only need minimal setup for local areas: validate layers, clear them, init noise, then generate.
	if not _validate_layers():
		return

	_clear_all_layers()

	# Parent generation expects a noise instance to exist.
	noise = FastNoiseLite.new()

	if auto_generate_on_ready:
		generate_local()

# Public entry-point to (re)generate a local area using parent functions only.
func generate_local(new_overworld_tile_type: int = overworld_tile_type, new_world_position: Vector2i = world_position, new_seed_value: int = seed_value) -> void:
	# Ensure clean slate each time.
	_clear_all_layers()
	if noise == null:
		noise = FastNoiseLite.new()

	# Delegate to LocationGenerator's local-only entry point.
	# This computes a deterministic per-area seed from inputs and invokes generate_local_area().
	setup_and_generate_local(new_overworld_tile_type, new_world_position, new_seed_value)

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
