extends PopupMenu
class_name ContextMenu

## Right-click menu for whatever the player clicked on — an NPC, a dropped
## item, a container.
##
## The menu only decides *what can be done* with a target and reports the
## choice; the Player decides how to do it (walk over, spend the turn, ask for
## confirmation). Keeping it that way means the menu never has to know about
## turns, routes or reach.

signal action_chosen(action: StringName, target: Node)

const ACTION_TALK := &"talk"
const ACTION_INSPECT := &"inspect"
const ACTION_ATTACK := &"attack"
const ACTION_OPEN := &"open"
const ACTION_PICKUP := &"pickup"

## What the currently shown menu refers to.
var target: Node = null

## Action for each item id, parallel to the entries added by `_add`.
var _actions: Array[StringName] = []


func _ready() -> void:
	# The loot and inventory screens pause the tree; a menu that stops working
	# while one is up would strand the player mid-click.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide_on_item_selection = true
	id_pressed.connect(_on_id_pressed)


## Fill the menu for `for_target` and show it at `at` (viewport coordinates).
## Returns false when there is nothing worth offering, in which case nothing
## is shown and the click should fall through.
func open_for(for_target: Node, at: Vector2) -> bool:
	target = for_target
	clear()
	_actions.clear()

	if for_target is NPC:
		_build_npc_menu(for_target as NPC)
	elif for_target is ItemContainer:
		_build_container_menu(for_target as ItemContainer)
	elif for_target is WorldItem:
		_build_item_menu(for_target as WorldItem)

	if _actions.is_empty():
		target = null
		return false

	reset_size()
	popup_on_parent(Rect2i(Vector2i(at), Vector2i.ZERO))
	return true


func _build_npc_menu(npc: NPC) -> void:
	_add_header(npc.get_display_name())
	if not npc.is_alive():
		_add("Inspect", ACTION_INSPECT)
		return
	# Someone already swinging at you is past the point of conversation.
	if not npc.is_hostile_toward(_player()):
		_add("Talk", ACTION_TALK)
	_add("Inspect", ACTION_INSPECT)
	_add("Attack", ACTION_ATTACK)


func _build_container_menu(container: ItemContainer) -> void:
	_add_header(container.container_label)
	_add("Open", ACTION_OPEN)
	_add("Inspect", ACTION_INSPECT)


func _build_item_menu(world_item: WorldItem) -> void:
	_add_header(world_item.get_description())
	_add("Pick up", ACTION_PICKUP)
	_add("Inspect", ACTION_INSPECT)


## A disabled entry naming the target, so the menu says what it belongs to.
func _add_header(text: String) -> void:
	add_item(text, -1)
	set_item_disabled(item_count - 1, true)
	add_separator()


func _add(label: String, action: StringName) -> void:
	add_item(label, _actions.size())
	_actions.append(action)


func _player() -> Node:
	var players := get_tree().get_nodes_in_group("Player")
	return players[0] if not players.is_empty() else null


func _on_id_pressed(id: int) -> void:
	if id < 0 or id >= _actions.size() or not is_instance_valid(target):
		return
	# Deferred so the popup is fully closed before the action runs — an action
	# that opens another screen would otherwise fight this one for focus.
	action_chosen.emit.call_deferred(_actions[id], target)
