extends Node2D

@onready var area: Node2D = $area
@onready var spawn_tile: Area2D = $spawn_tile

var _local_area_packed: PackedScene = preload("res://scenes/local_area_generator.tscn")
var _npc_spawner_packed: PackedScene = preload("res://scenes/npc_spawner.tscn")

var current_area: Node2D = null
var npc_spawner: NPCSpawner = null

# ─── Public API ────────────────────────────────────────────────────────────────

## Core entry point. Pass a scene_path for hand-crafted settlements,
## or a TileMetadata for procedurally-generated wilderness areas (or both).
func load_area(scene_path: String = "", metadata: TileMetadata = null) -> void:
	clear()
	if scene_path != "":
		var packed: PackedScene = load(scene_path)
		if packed == null:
			push_error("AreaContainer: could not load scene '%s'" % scene_path)
			return
		current_area = packed.instantiate()
		area.add_child(current_area)
		_attach_npc_spawner(true)
	elif metadata != null:
		current_area = _local_area_packed.instantiate()
		current_area.auto_generate_on_ready = false
		area.add_child(current_area)
		current_area.generate_local_map(metadata)
		_attach_npc_spawner(false, metadata)
	else:
		push_warning("AreaContainer.load_area: no scene_path or metadata provided.")

## Convenience wrapper — reads fields from a LocalMapTile node.
func load_from_tile(tile: LocalMapTile) -> void:
	load_area(tile.scene_path, tile.tile_metadata)

## Destroy the current local area and reset references.
func clear() -> void:
	if is_instance_valid(current_area):
		current_area.queue_free()
	current_area = null
	npc_spawner = null

# ─── Private helpers ───────────────────────────────────────────────────────────

func _attach_npc_spawner(is_settlement: bool, metadata: TileMetadata = null) -> void:
	if not is_instance_valid(current_area):
		return
	npc_spawner = _npc_spawner_packed.instantiate() as NPCSpawner
	if is_settlement:
		# Provide the MapConfig so the spawner can look up settlement NPC counts.
		if "config" in current_area:
			npc_spawner.settlement_data = current_area.config
		elif "map_template" in current_area:
			npc_spawner.settlement_data = current_area.map_template
	else:
		# Provide TileMetadata so wilderness counts/types are data-driven.
		npc_spawner.wilderness_metadata = metadata
	current_area.add_child(npc_spawner)
	if is_settlement:
		npc_spawner.spawn_settlement_npcs()
	else:
		npc_spawner.spawn_wilderness_npcs()
