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

const FALLBACK_TABLE := "container.generic"

var spawned_containers: Array[ItemContainer] = []
var place: Place = null
var _map: MapGenerator = null

## Contents are rolled from the tile seed, not from a live RNG, so a chest the
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

## Place a container on every container slot of `area_place`, filling each
## from the spawn table its prop names ("container.<loot_table>").
##
## `saved_state` maps container_id -> container dict for containers the player
## has already looted; those are restored instead of re-rolled. Pre-v3 saves
## keyed it by cell ("x,y"), which is still accepted once and re-keyed on the
## next save.
func populate_local_map(area_place: Place, saved_state: Dictionary = {}) -> void:
	clear()
	place = area_place
	if _map == null or place == null:
		return

	for slot in place.slots_of_kind("container"):
		var container: ItemContainer = container_scene.instantiate()
		container.configure(_map, slot, place.place_id)
		container.position = Vector2(container.tile) * MainGameState.TILE_SIZE
		add_child(container)

		var saved: Variant = saved_state.get(container.container_id)
		if saved == null:
			saved = saved_state.get(_legacy_key(container.tile))
			if saved is Dictionary:
				push_warning("[ContainerSpawner] Restored %s from a pre-v3 cell-keyed save record" % container.container_id)
		if saved is Dictionary:
			container.from_dict(saved)
		else:
			_roll_lock(container, slot)
			_fill(container, slot)

		spawned_containers.append(container)

## The containers the player has opened or looted, as { container_id -> dict },
## for the save system. Untouched containers are left out — their first roll is
## already kept in MainGameState.spawn_records.
func get_dirty_state() -> Dictionary:
	var state: Dictionary = {}
	for container in spawned_containers:
		if is_instance_valid(container) and container.has_been_looted():
			state[container.container_id] = container.to_dict()
	return state

# ─── Internals ─────────────────────────────────────────────────────────────────

func _legacy_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

## Seed derived from the tile seed, the place and the slot, so each container
## rolls independently of spawn order and of where it sits on the map.
func _slot_seed(slot: PlaceSlot) -> int:
	return abs(hash([place.tile_seed, place.place_id, slot.slot_id, SEED_SALT]))

func _roll_lock(container: ItemContainer, slot: PlaceSlot) -> void:
	var chance: float = float(slot.data.get("locked_chance", 0.0))
	if chance <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _slot_seed(slot) ^ 0x5EED10CC
	container.is_locked = rng.randf() < chance

## Contents come from the "container.<loot_table>" spawn table, falling back to
## container.generic for a prop whose table has not been authored.
func _fill(container: ItemContainer, slot: PlaceSlot) -> void:
	var loot_table: String = container.loot_table if not container.loot_table.is_empty() else container.role
	var table_id := "container.%s" % loot_table
	if not ItemDatabase.has_spawn_table(table_id):
		table_id = FALLBACK_TABLE
	var ctx := SpawnContext.for_slot(place, slot.slot_id)
	for result in ItemSpawnResolver.resolve_slot_once(table_id, ctx):
		container.add_item(result.item, result.quantity)
