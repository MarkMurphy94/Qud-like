extends Node
class_name ContainerSpawner

## Stands lootable containers on the cells the map generator marked for them.
##
## Lives as a child of the MapGenerator it populates (see local_scene.tscn),
## mirroring NPCSpawner: MainGame drives it through populate_local_map() on
## entry and clear() on exit, so containers share the map's lifetime.
##
## The container prop is already painted — this only attaches the contents and
## the interaction to the cell it sits on.

@export var container_scene: PackedScene = preload("res://scenes/item_container.tscn")

## The MapGenerator whose container cells this spawner fills. Normally the
## parent; the export is an escape hatch for other scene layouts.
@export var map_generator_path: NodePath

var spawned_containers: Array[ItemContainer] = []
var _map: MapGenerator = null

## Contents are rolled from the map seed, not from a live RNG, so a chest the
## player walked past but never opened holds the same loot when they return.
## Only containers the player actually touches need saving.
const SEED_SALT: int = 0x10078E51

func _ready() -> void:
	if not map_generator_path.is_empty():
		_map = get_node_or_null(map_generator_path) as MapGenerator
	if _map == null:
		_map = get_parent() as MapGenerator

func clear() -> void:
	for container in spawned_containers:
		if is_instance_valid(container):
			container.remove_from_group(ItemContainer.GROUP)
			container.queue_free()
	spawned_containers.clear()

# ─── Entry point ───────────────────────────────────────────────────────────────

## Place a container on every cell the generator recorded, filling each from
## the loot table its prop names. `level` scales the quality of what turns up.
##
## `saved_state` is an optional { "x,y" -> container dict } map of containers
## the player has already opened; those are restored instead of re-rolled.
func populate_local_map(level: int = 1, saved_state: Dictionary = {}) -> void:
	clear()
	if _map == null:
		return

	for cell in _map.container_cells:
		var record: Dictionary = _map.container_cells[cell]
		var container: ItemContainer = container_scene.instantiate()
		container.configure(_map, cell, record)
		container.position = Vector2(cell) * MainGameState.TILE_SIZE
		add_child(container)

		var saved: Variant = saved_state.get(_state_key(cell))
		if saved is Dictionary:
			container.from_dict(saved)
		else:
			_roll_lock(container, record)
			_fill(container, level)

		spawned_containers.append(container)

## The containers the player has opened or looted, as { "x,y" -> dict }, for
## the save system to fold into the tile's dynamic state. Untouched containers
## are left out — their contents rebuild from the map seed.
func get_dirty_state() -> Dictionary:
	var state: Dictionary = {}
	for container in spawned_containers:
		if is_instance_valid(container) and container.has_been_looted():
			state[_state_key(container.tile)] = container.to_dict()
	return state

# ─── Internals ─────────────────────────────────────────────────────────────────

func _state_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

## Seed derived from the map seed and the cell, so each container rolls
## independently of the order they are spawned in.
func _cell_seed(cell: Vector2i) -> int:
	return abs(hash([_map.current_map_seed, cell.x, cell.y, SEED_SALT]))

func _roll_lock(container: ItemContainer, record: Dictionary) -> void:
	var chance: float = float(record.get("locked_chance", 0.0))
	if chance <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(container.tile) ^ 0x5EED10CC
	container.is_locked = rng.randf() < chance

func _fill(container: ItemContainer, level: int) -> void:
	var loot_table: String = container.loot_table if not container.loot_table.is_empty() else container.role
	for item in ItemGenerator.fill_container(loot_table, level, _cell_seed(container.tile)):
		container.add_item(item, 1)
