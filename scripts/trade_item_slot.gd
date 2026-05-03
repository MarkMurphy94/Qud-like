extends Button
class_name TradeItemSlot

## A single item slot in the trade screen.
## Supports Godot 4 GUI drag-and-drop for transferring items between inventories.

var slot_index: int = 0
var owner_tag: String = ""   ## "player" or "npc"
var item_data: Dictionary = {}  ## {item: Item, quantity: int}
var trade_screen_ref: Node = null  ## Reference to TradeScreen


func setup(p_index: int, p_owner: String, p_data: Dictionary, p_screen: Node) -> void:
	slot_index = p_index
	owner_tag = p_owner
	item_data = p_data
	trade_screen_ref = p_screen


# ---- Drag source ----

func _get_drag_data(_at_position: Vector2):
	if item_data.is_empty() or not item_data.has("item"):
		return null

	set_drag_preview(_create_drag_preview())

	return {
		"source_index": slot_index,
		"source_owner": owner_tag,
		"item": item_data.item,
		"quantity": item_data.quantity,
	}


# ---- Drop target ----

func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not data is Dictionary or not data.has("item"):
		return false
	# Only allow drops from the opposite side
	return data.get("source_owner", owner_tag) != owner_tag


func _drop_data(_at_position: Vector2, data) -> void:
	if trade_screen_ref and trade_screen_ref.has_method("_handle_drop"):
		trade_screen_ref._handle_drop(data, owner_tag)


# ---- Drag preview ----

func _create_drag_preview() -> Control:
	var panel := PanelContainer.new()
	panel.modulate = Color(1, 1, 1, 0.85)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_color = Color(0.8, 0.7, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(60, 60)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item_data.has("item"):
		var tex = item_data.item.get_icon()
		if tex:
			icon_rect.texture = tex

	var qty_label := Label.new()
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_label.add_theme_font_size_override("font_size", 11)
	qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item_data.get("quantity", 1) > 1:
		qty_label.text = "x%d" % item_data.quantity

	vbox.add_child(icon_rect)
	vbox.add_child(qty_label)
	panel.add_child(vbox)
	return panel
