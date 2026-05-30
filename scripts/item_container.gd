extends Node2D
class_name ItemContainer

## A world container (barrel, chest, box, etc.) that holds items.
## Uses the shared Inventory system for storage.
## Tracks which items have been removed so they don't respawn on reload.

# ── Container type ────────────────────────────────────────────────────────────
enum ContainerType { CHEST, BARREL, BOX, CRATE, SACK }

## Sprite region rects for each container type on the 32rogues tiles.png sheet.
## Each Vector4 is (x, y, width, height) in pixels.
const SPRITE_REGIONS: Dictionary = {
	ContainerType.CHEST:  Rect2(0, 544, 32, 32),
	ContainerType.BARREL: Rect2(128, 544, 32, 32),
	# ContainerType.BOX:    Rect2(96, 480, 32, 32),
	# ContainerType.CRATE:  Rect2(128, 480, 32, 32),
	ContainerType.SACK:   Rect2(160, 544, 32, 32),
}

# ── Exports ───────────────────────────────────────────────────────────────────
@export var container_type: ContainerType = ContainerType.CHEST:
	set(value):
		container_type = value
		if is_inside_tree():
			_update_sprite()

@export var container_id: String = ""       ## Unique ID for save/load. Auto-generated if blank.
@export var container_label: String = "Chest"  ## Display name shown to the player.
@export var max_slots: int = 20
@export var is_locked: bool = false
@export var lock_key_id: String = ""        ## Item ID required to unlock. Empty = any key.
@export var is_destructible: bool = false    ## If true, player can smash it open.
@export var initial_items: Array[Item] = [] ## Items pre-loaded into the container in the editor.

# ── State ─────────────────────────────────────────────────────────────────────
var inventory: Inventory = null

## Tracks items that have been taken out, as { item_id -> quantity_removed }.
## Used by the save system so removed items don't respawn.
var removed_log: Dictionary = {}

var is_open: bool = false
var is_emptied: bool = false  ## True once all items have been taken.

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var sprite: Sprite2D = $Sprite2D
@onready var interact_area: Area2D = $Area2D
@onready var interact_label: Label = $InteractLabel

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
	if container_id.is_empty():
		container_id = "container_%s" % str(get_instance_id())

	_setup_inventory()
	_update_sprite()
	_populate_initial_items()

	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

	if interact_label:
		interact_label.visible = false
		interact_label.text = "[E] Open %s" % container_label

# ── Setup ─────────────────────────────────────────────────────────────────────
func _setup_inventory() -> void:
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

func _update_sprite() -> void:
	if not sprite:
		return
	if SPRITE_REGIONS.has(container_type):
		sprite.region_enabled = true
		sprite.region_rect = SPRITE_REGIONS[container_type]

# ── Public API ────────────────────────────────────────────────────────────────

## Try to open the container. Returns false if locked.
func open(opener: Node = null) -> bool:
	if is_locked:
		# Check if opener has the required key
		if opener and opener.has_method("has_item"):
			var has_key: bool = lock_key_id.is_empty() or opener.has_item(lock_key_id)
			if has_key:
				unlock(opener)
			else:
				return false
		else:
			return false

	is_open = true
	container_opened.emit(self)
	_open_container_screen(opener)
	return true

func close() -> void:
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
	container_unlocked.emit(self)

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

## True once the container has been opened at least once.
func has_been_looted() -> bool:
	return not removed_log.is_empty()

# ── Interaction ───────────────────────────────────────────────────────────────
func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		if interact_label:
			interact_label.text = "[E] %s %s" % ["Unlock" if is_locked else "Open", container_label]
			interact_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		if interact_label:
			interact_label.visible = false
		if is_open:
			close()

func _input(event: InputEvent) -> void:
	# Only process interact key when a player is nearby (label is visible)
	if not interact_label or not interact_label.visible:
		return
	if event.is_action_pressed("ui_interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		var player := _find_nearby_player()
		if player:
			open(player)
		get_viewport().set_input_as_handled()

func _is_player(node: Node) -> bool:
	return node.is_in_group("player") or node.name == "Player"

func _find_nearby_player() -> Node:
	for body in interact_area.get_overlapping_bodies():
		if _is_player(body):
			return body
	return null

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
		"container_type": container_type,
		"is_locked": is_locked,
		"is_open": is_open,
		"is_emptied": is_emptied,
		"removed_log": removed_log.duplicate(),
		"inventory": inventory.to_dict(),
	}

func from_dict(data: Dictionary) -> void:
	if data.has("container_id"): container_id = data.container_id
	if data.has("container_type"): container_type = data.container_type
	if data.has("is_locked"): is_locked = data.is_locked
	if data.has("is_open"): is_open = data.is_open
	if data.has("is_emptied"): is_emptied = data.is_emptied
	if data.has("removed_log"): removed_log = data.removed_log
	if data.has("inventory"): inventory.from_dict(data.inventory)
	_update_sprite()
