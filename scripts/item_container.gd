extends Node2D
class_name ItemContainer

## A lootable container standing on one map tile — a chest, a shelf, a barrel.
##
## The container owns no art. The prop tile the map generator painted *is* the
## container: its sprite and its collision come from the tileset like any other
## prop (see the container-prop notes in resources/tileset_layout.gd). This node
## is only the contents, the lock, and the record of what has been taken out.
##
## Interaction is grid-based and costs a turn, like everything else in this
## world — the player opens whatever container is on or beside their tile via
## `ui_interact`. There is no proximity area and no per-frame input handling.

## Group every container joins, so a tile lookup never has to walk the tree.
const GROUP := &"containers"

## Human-readable label per role. Roles are plain strings (the value of a tile's
## `container` override), so a new kind of container needs no code change beyond
## an entry here — and an unlisted role still reads sensibly.
const ROLE_LABELS: Dictionary = {
	"chest": "Chest",
	"shelf": "Shelf",
	"barrel": "Barrel",
	"crate": "Crate",
	"sack": "Sack",
	"cupboard": "Cupboard",
}

# ── Identity ──────────────────────────────────────────────────────────────────
## Tile this container occupies, in the local map's grid.
@export var tile: Vector2i = Vector2i.ZERO
## What kind of container this is ("chest", "shelf", …). Picks the label and,
## by default, the loot table.
@export var role: String = "chest"
## ItemGenerator loot table used to fill it. Empty falls back to `role`.
@export var loot_table: String = ""
## Stable key for save/load. Derived from role + tile when left blank.
@export var container_id: String = ""

# ── Contents ──────────────────────────────────────────────────────────────────
@export var max_slots: int = 12
@export var is_locked: bool = false
@export var lock_key_id: String = ""        ## Item ID required to unlock. Empty = any key.
@export var initial_items: Array[Item] = [] ## Items pre-loaded into the container in the editor.

var inventory: Inventory = null

## Tracks items that have been taken out, as { item_id -> quantity_removed }.
## Used by the save system so removed items don't respawn.
var removed_log: Dictionary = {}

var is_open: bool = false
var is_emptied: bool = false  ## True once all items have been taken.

# ── Tile art ──────────────────────────────────────────────────────────────────
## The map this container's tile belongs to, and how to repaint that tile once
## it has been opened. All optional — a container whose prop has no distinct
## "open" sprite simply never changes appearance.
var map: Node = null
var layer_name: String = ""
var source_id: int = -1
var closed_atlas: Vector2i = Vector2i(-1, -1)
var open_atlas: Vector2i = Vector2i(-1, -1)

var _inventory_screen_scene := preload("res://scenes/inventory_screen.tscn")
var _inventory_screen_instance: InventoryScreen = null

# ── Signals ───────────────────────────────────────────────────────────────────
signal container_opened(container: ItemContainer)
signal container_closed(container: ItemContainer)
signal item_taken(container: ItemContainer, item: Item, quantity: int)
signal container_emptied(container: ItemContainer)
signal container_unlocked(container: ItemContainer)

# ── Ready ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group(GROUP)
	if container_id.is_empty():
		container_id = "%s@%d,%d" % [role, tile.x, tile.y]

	_setup_inventory()
	_populate_initial_items()

# ── Setup ─────────────────────────────────────────────────────────────────────
func _setup_inventory() -> void:
	if inventory != null:
		return
	inventory = Inventory.new()
	inventory.max_slots = max_slots
	inventory.max_weight = -1.0  # Containers are weight-unlimited by default
	inventory.inventory_changed.connect(_on_inventory_changed)
	inventory.item_removed.connect(_on_item_removed_from_inventory)
	add_child(inventory)

func _populate_initial_items() -> void:
	for item in initial_items:
		if item:
			inventory.add_item(item, 1)

## Configure a freshly built container from one of MapGenerator.container_cells.
## Call before adding the node to the tree.
func configure(source_map: Node, cell: Vector2i, record: Dictionary) -> void:
	map = source_map
	tile = cell
	role = String(record.get("role", "chest"))
	loot_table = String(record.get("loot_table", role))
	layer_name = String(record.get("layer", ""))
	source_id = int(record.get("source_id", -1))
	closed_atlas = record.get("atlas", Vector2i(-1, -1))
	open_atlas = record.get("open_atlas", closed_atlas)
	container_id = "%s@%d,%d" % [role, tile.x, tile.y]

# ── Lookup ────────────────────────────────────────────────────────────────────

## The container standing on `cell`, or null. Cheap enough to call once per
## interaction: a settlement holds tens of containers, not thousands.
static func at(tree: SceneTree, cell: Vector2i) -> ItemContainer:
	for node in tree.get_nodes_in_group(GROUP):
		var container: ItemContainer = node
		if is_instance_valid(container) and container.tile == cell:
			return container
	return null

# ── Public API ────────────────────────────────────────────────────────────────

## Display name for the loot screen and the message log.
var container_label: String:
	get:
		return ROLE_LABELS.get(role, role.capitalize())

## Open the container. Returns true if the attempt cost a turn — a locked lid
## the player cannot pick still costs the attempt.
func open(opener: Node = null) -> bool:
	if is_locked and not _try_unlock(opener):
		TurnManager.log_message("The %s is locked." % container_label.to_lower(), "info")
		return true

	_repaint(open_atlas)

	if inventory.get_slot_count() == 0:
		TurnManager.log_message("The %s is empty." % container_label.to_lower(), "info")
		return true

	is_open = true
	container_opened.emit(self)
	TurnManager.log_message("You open the %s." % container_label.to_lower(), "info")
	_open_container_screen(opener)
	return true

func close() -> void:
	if not is_open:
		return
	is_open = false
	container_closed.emit(self)
	if _inventory_screen_instance and is_instance_valid(_inventory_screen_instance) and _inventory_screen_instance.visible:
		_inventory_screen_instance.close_inventory()

func _open_container_screen(opener: Node) -> void:
	if not _inventory_screen_instance or not is_instance_valid(_inventory_screen_instance):
		_inventory_screen_instance = _inventory_screen_scene.instantiate()
		get_tree().current_scene.add_child(_inventory_screen_instance)
		_inventory_screen_instance.inventory_closed.connect(_on_screen_closed)
	_inventory_screen_instance.open_as_container(self, opener)

func _on_screen_closed() -> void:
	if is_open:
		close()

## Unlock the container (optionally consuming a key from the opener's inventory).
func unlock(opener: Node = null) -> void:
	if not lock_key_id.is_empty() and opener and opener.has_method("remove_item_from_inventory"):
		opener.remove_item_from_inventory(lock_key_id, 1)
	is_locked = false
	TurnManager.log_message("You unlock the %s." % container_label.to_lower(), "info")
	container_unlocked.emit(self)

func _try_unlock(opener: Node) -> bool:
	if opener == null or not opener.has_method("has_item"):
		return false
	if not lock_key_id.is_empty() and not opener.has_item(lock_key_id):
		return false
	unlock(opener)
	return true

## Swap the container's tile to another atlas coord. A no-op when the prop has
## no distinct open sprite, or when the container was placed without a map.
func _repaint(atlas: Vector2i) -> void:
	if map == null or source_id < 0 or atlas.x < 0 or atlas == closed_atlas:
		return
	if not map.has_method("layer_named"):
		return
	var layer: TileMapLayer = map.layer_named(layer_name)
	if layer == null:
		return
	layer.set_cell(tile, source_id, atlas)
	closed_atlas = atlas

## Take a quantity of an item out, logging the removal. Returns actual quantity taken.
func take_item(item_id: String, quantity: int = 1) -> int:
	var removed := inventory.remove_item(item_id, quantity)
	# Logging is handled in _on_item_removed_from_inventory
	return removed

## Add items to the container (e.g. player dropping something in).
func add_item(item: Item, quantity: int = 1) -> bool:
	return inventory.add_item(item, quantity)

## Transfer all contents into another inventory (loot-all).
func loot_all(target_inventory: Inventory) -> void:
	var slots := inventory.get_all_items()
	for slot in slots:
		inventory.transfer_to(target_inventory, slot.item.id, slot.quantity)

## True once anything has been taken out.
func has_been_looted() -> bool:
	return not removed_log.is_empty()

# ── Inventory signal handlers ─────────────────────────────────────────────────
func _on_inventory_changed() -> void:
	if inventory.get_slot_count() == 0 and not is_emptied:
		is_emptied = true
		container_emptied.emit(self)

func _on_item_removed_from_inventory(item: Item, quantity: int) -> void:
	## Record every removal so the save system can suppress respawning.
	if removed_log.has(item.id):
		removed_log[item.id] += quantity
	else:
		removed_log[item.id] = quantity
	item_taken.emit(self, item, quantity)

# ── Save / Load ───────────────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"container_id": container_id,
		"tile": [tile.x, tile.y],
		"role": role,
		"loot_table": loot_table,
		"is_locked": is_locked,
		"is_emptied": is_emptied,
		"removed_log": removed_log.duplicate(),
		"inventory": inventory.to_dict(),
	}

func from_dict(data: Dictionary) -> void:
	_setup_inventory()
	if data.has("container_id"): container_id = data.container_id
	if data.has("tile"):
		var saved_tile: Array = data.tile
		tile = Vector2i(int(saved_tile[0]), int(saved_tile[1]))
	if data.has("role"): role = data.role
	if data.has("loot_table"): loot_table = data.loot_table
	if data.has("is_locked"): is_locked = data.is_locked
	if data.has("is_emptied"): is_emptied = data.is_emptied
	if data.has("removed_log"): removed_log = data.removed_log.duplicate()
	if data.has("inventory"): inventory.from_dict(data.inventory)
