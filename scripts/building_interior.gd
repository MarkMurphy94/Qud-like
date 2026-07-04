@tool
extends Node2D

## building.tscn contains one child Node2D per building_id (e.g. "house_1",
## "tavern_1"), each holding both its exterior and interior sub-hierarchy.
## new_tileset_test_town.gd sets `building_id` before adding this scene to the
## tree; _ready() then shows only the matching child and hides every other
## variant, including the "node_hierarchy_template" authoring placeholder.
## Marked @tool because new_tileset_test_town.gd is itself a @tool script that
## instantiates this scene in the editor — without @tool here, _ready() (and
## therefore activate_building()) would never run in edit mode, leaving every
## instance in its baked default visibility state.
const TEMPLATE_NODE_NAME := "node_hierarchy_template"

@export var building_id: String = ""


func _ready() -> void:
	activate_building(building_id)


# Shows the child whose name matches target_building_id and hides every other
# building variant (including the authoring template). Also wires up the
# active building's "threshold" Area2D so its "exterior" node hides while the
# player is inside.
func activate_building(target_building_id: String) -> void:
	var found := false
	for child in get_children():
		if child.name == TEMPLATE_NODE_NAME:
			child.visible = false
			continue
		var is_match: bool = child.name == target_building_id
		child.visible = is_match
		found = found or is_match
		if is_match:
			_connect_threshold(child)

	if not found:
		push_warning("building_interior: no building node found for building id '%s'" % target_building_id)


# Connects the given building node's "threshold" Area2D (if present) so
# entering it hides the building's "exterior" node and exiting shows it again.
func _connect_threshold(building_node: Node) -> void:
	var threshold: Area2D = building_node.get_node_or_null("threshold")
	var exterior: Node = building_node.get_node_or_null("exterior")
	if not threshold or not exterior:
		return
	threshold.body_entered.connect(_on_threshold_body_entered.bind(exterior))
	threshold.body_exited.connect(_on_threshold_body_exited.bind(exterior))


func _on_threshold_body_entered(body: Node2D, exterior: Node) -> void:
	if body.is_in_group("player"):
		exterior.visible = false


func _on_threshold_body_exited(body: Node2D, exterior: Node) -> void:
	if body.is_in_group("player"):
		exterior.visible = true
