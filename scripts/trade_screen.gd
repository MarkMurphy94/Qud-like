extends CanvasLayer
class_name TradeScreen

## Trade UI shown when the player trades with an NPC.
## Displays player inventory (left) and NPC inventory (right).
## Items can be dragged between panels to buy/sell.
## - Drag NPC → Player  : buy (player pays gold)
## - Drag Player → NPC  : sell (player receives gold)
## A "Transfer" button in the detail panel is also available as a fallback.

signal trade_closed

# ---- References ----
var player_ref: Node = null       ## The Player node
var npc_ref: Node = null          ## The NPC node

var player_inventory: Inventory = null
var npc_inventory: Inventory = null

# Displayed prices use the NPC's trade_prices multipliers
var _buy_mult: float = 1.0     ## NPC → Player  (player buys at this markup)
var _sell_mult: float = 0.5    ## Player → NPC  (NPC buys at this fraction)

# ---- UI nodes (built in _ready) ----
var _panel: Panel
var _title_label: Label
var _player_gold_label: Label
var _npc_gold_label: Label
var _close_btn: Button
var _player_grid: GridContainer
var _npc_grid: GridContainer
var _player_stats_label: Label
var _npc_stats_label: Label
var _detail_panel: Panel
var _detail_name: Label
var _detail_desc: Label
var _detail_stats: Label
var _detail_price: Label
var _transfer_btn: Button

# Currently selected slot info
var _selected_item: Item = null
var _selected_quantity: int = 0
var _selected_owner: String = ""
var _selected_index: int = -1

# Preload the slot script
const TradeItemSlotScript = preload("res://scripts/trade_item_slot.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


# =============================
# PUBLIC API
# =============================

func open_trade(p_player: Node, p_npc: Node) -> void:
	player_ref = p_player
	npc_ref = p_npc
	player_inventory = p_player.inventory if p_player.get("inventory") != null else null
	npc_inventory = p_npc.inventory if p_npc.get("inventory") != null else null

	if not player_inventory:
		push_error("[TradeScreen] Player has no inventory")
		return
	if not npc_inventory:
		push_error("[TradeScreen] NPC has no inventory")
		return

	# Load trade price multipliers from NPC
	if p_npc.get("trade_prices") != null:
		_buy_mult = p_npc.trade_prices.get("buy_multiplier", 1.0)
		_sell_mult = p_npc.trade_prices.get("sell_multiplier", 0.5)
	else:
		_buy_mult = 1.0
		_sell_mult = 0.5

	# Title
	var npc_name_str: String = p_npc.npc_name if p_npc.get("npc_name") and p_npc.npc_name != "" else "Merchant"
	_title_label.text = "Trading with %s" % npc_name_str

	# Connect inventory change signals
	if not player_inventory.inventory_changed.is_connected(_refresh_all):
		player_inventory.inventory_changed.connect(_refresh_all)
	if not npc_inventory.inventory_changed.is_connected(_refresh_all):
		npc_inventory.inventory_changed.connect(_refresh_all)

	_clear_selection()
	_refresh_all()
	show()
	get_tree().paused = true


func close_trade() -> void:
	if player_inventory and player_inventory.inventory_changed.is_connected(_refresh_all):
		player_inventory.inventory_changed.disconnect(_refresh_all)
	if npc_inventory and npc_inventory.inventory_changed.is_connected(_refresh_all):
		npc_inventory.inventory_changed.disconnect(_refresh_all)

	_clear_selection()
	hide()
	get_tree().paused = false
	trade_closed.emit()


# =============================
# DRAG-AND-DROP HANDLER
# =============================

func _handle_drop(data: Dictionary, target_owner: String) -> void:
	"""Called by TradeItemSlot when a drop is completed."""
	var item: Item = data.get("item")
	var quantity: int = data.get("quantity", 1)
	var source_owner: String = data.get("source_owner", "")

	if not item:
		return

	if source_owner == "player" and target_owner == "npc":
		_sell_item(item, quantity)
	elif source_owner == "npc" and target_owner == "player":
		_buy_item(item, quantity)


func _sell_item(item: Item, quantity: int) -> void:
	"""Move item from player → NPC. Player receives gold."""
	if not player_inventory or not npc_inventory:
		return
	if not player_inventory.has_item(item.id, quantity):
		return
	if not npc_inventory.add_item(item, quantity):
		_show_message("Merchant's inventory is full.")
		return
	player_inventory.remove_item(item.id, quantity)
	var earned: int = int(item.get_total_value() * _sell_mult) * quantity
	if player_ref and player_ref.get("gold") != null:
		player_ref.gold += earned
	if npc_ref and npc_ref.get("gold") != null:
		npc_ref.gold = max(0, npc_ref.gold - earned)
	_update_gold_labels()


func _buy_item(item: Item, quantity: int) -> void:
	"""Move item from NPC → Player. Player pays gold."""
	if not player_inventory or not npc_inventory:
		return
	if not npc_inventory.has_item(item.id, quantity):
		return
	var cost: int = int(item.get_total_value() * _buy_mult) * quantity
	if player_ref and player_ref.get("gold") != null:
		if player_ref.gold < cost:
			_show_message("You can't afford that! (%d gold needed)" % cost)
			return
	if not player_inventory.add_item(item, quantity):
		_show_message("Your inventory is full.")
		return
	npc_inventory.remove_item(item.id, quantity)
	if player_ref and player_ref.get("gold") != null:
		player_ref.gold -= cost
	if npc_ref and npc_ref.get("gold") != null:
		npc_ref.gold += cost
	_update_gold_labels()


# =============================
# TRANSFER BUTTON (fallback)
# =============================

func _on_transfer_pressed() -> void:
	if not _selected_item or _selected_index < 0:
		return

	if _selected_owner == "player":
		_sell_item(_selected_item, _selected_quantity)
	elif _selected_owner == "npc":
		_buy_item(_selected_item, _selected_quantity)

	_clear_selection()


# =============================
# REFRESH / DISPLAY
# =============================

func _refresh_all() -> void:
	_populate_grid(_player_grid, player_inventory, "player")
	_populate_grid(_npc_grid, npc_inventory, "npc")
	_update_stats_labels()
	_update_gold_labels()


func _populate_grid(grid: GridContainer, inv: Inventory, owner_tag: String) -> void:
	for child in grid.get_children():
		child.queue_free()

	if not inv:
		return

	var items := inv.get_all_items()
	for i in range(items.size()):
		var slot_data: Dictionary = items[i]
		var btn: Button = _create_slot_button(slot_data, i, owner_tag)
		grid.add_child(btn)


func _create_slot_button(slot_data: Dictionary, index: int, owner_tag: String) -> Button:
	var btn: Button = TradeItemSlotScript.new()
	btn.setup(index, owner_tag, slot_data, self)
	btn.custom_minimum_size = Vector2(60, 60)
	btn.toggle_mode = false

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var item: Item = slot_data.item
	var tex = item.get_icon()
	if tex:
		icon_rect.texture = tex

	var qty_label := Label.new()
	qty_label.text = "x%d" % slot_data.quantity if slot_data.quantity > 1 else ""
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", 11)
	qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	vbox.add_child(icon_rect)
	vbox.add_child(qty_label)
	btn.add_child(vbox)

	_style_slot(btn, item.rarity)

	btn.tooltip_text = _item_tooltip(item, slot_data.quantity, owner_tag)
	btn.pressed.connect(_on_slot_clicked.bind(index, owner_tag))

	return btn


func _on_slot_clicked(index: int, owner_tag: String) -> void:
	var inv: Inventory = player_inventory if owner_tag == "player" else npc_inventory
	if not inv:
		return
	var slot := inv.get_slot(index)
	if slot.is_empty():
		_clear_selection()
		return

	_selected_item = slot.item
	_selected_quantity = slot.quantity
	_selected_owner = owner_tag
	_selected_index = index
	_update_detail_panel(slot.item, slot.quantity, owner_tag)


func _update_detail_panel(item: Item, quantity: int, owner_tag: String) -> void:
	_detail_name.text = item.get_display_name()
	_detail_name.add_theme_color_override("font_color", item.get_rarity_color())
	_detail_desc.text = item.description if item.description else ""

	var stats := PackedStringArray()
	stats.append("Type: %s" % Item.ItemType.keys()[item.item_type])
	stats.append("Weight: %.1f kg" % item.weight)
	stats.append("Base value: %d gold" % item.get_total_value())
	if quantity > 1:
		stats.append("Qty: %d" % quantity)
	_detail_stats.text = "\n".join(stats)

	# Price line
	if owner_tag == "npc":
		var cost := int(item.get_total_value() * _buy_mult) * quantity
		_detail_price.text = "Buy cost: %d gold" % cost
		_transfer_btn.text = "Buy"
	else:
		var earn := int(item.get_total_value() * _sell_mult) * quantity
		_detail_price.text = "Sell value: %d gold" % earn
		_transfer_btn.text = "Sell"

	_transfer_btn.disabled = false


func _clear_selection() -> void:
	_selected_item = null
	_selected_quantity = 0
	_selected_owner = ""
	_selected_index = -1
	_detail_name.text = "Select an item"
	_detail_desc.text = ""
	_detail_stats.text = ""
	_detail_price.text = ""
	_transfer_btn.text = "Transfer"
	_transfer_btn.disabled = true


func _update_stats_labels() -> void:
	if player_inventory:
		_player_stats_label.text = "%.1f / %.1f kg  |  %d items" % [
			player_inventory.get_total_weight(),
			player_inventory.max_weight if player_inventory.max_weight > 0 else 999,
			player_inventory.get_slot_count()
		]
	if npc_inventory:
		_npc_stats_label.text = "%.1f kg  |  %d items" % [
			npc_inventory.get_total_weight(),
			npc_inventory.get_slot_count()
		]


func _update_gold_labels() -> void:
	var p_gold: int = player_ref.gold if player_ref and player_ref.get("gold") != null else 0
	var n_gold: int = npc_ref.gold if npc_ref and npc_ref.get("gold") != null else 0
	_player_gold_label.text = "Your Gold: %d" % p_gold
	_npc_gold_label.text = "Merchant Gold: %d" % n_gold


func _show_message(msg: String) -> void:
	_detail_price.text = msg


# =============================
# TOOLTIP
# =============================

func _item_tooltip(item: Item, quantity: int, owner_tag: String) -> String:
	var lines := PackedStringArray()
	lines.append(item.get_display_name())
	lines.append(item.get_rarity_name())
	if item.description:
		lines.append(item.description)
	lines.append("Weight: %.1f kg" % (item.weight * quantity))
	if owner_tag == "npc":
		lines.append("Buy: %d gold" % int(item.get_total_value() * _buy_mult * quantity))
	else:
		lines.append("Sell: %d gold" % int(item.get_total_value() * _sell_mult * quantity))
	return "\n".join(lines)


# =============================
# INPUT
# =============================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_trade()
		get_viewport().set_input_as_handled()


# =============================
# UI CONSTRUCTION
# =============================

func _build_ui() -> void:
	# --- Root panel (dimmed overlay) ---
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Offset inset
	_panel.offset_left = 60
	_panel.offset_top = 40
	_panel.offset_right = -60
	_panel.offset_bottom = -40
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox_root := VBoxContainer.new()
	vbox_root.add_theme_constant_override("separation", 8)
	margin.add_child(vbox_root)

	# --- Title bar ---
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 12)
	vbox_root.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "Trade"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 22)
	title_bar.add_child(_title_label)

	_player_gold_label = Label.new()
	_player_gold_label.text = "Your Gold: 0"
	title_bar.add_child(_player_gold_label)

	_npc_gold_label = Label.new()
	_npc_gold_label.text = "Merchant Gold: 0"
	title_bar.add_child(_npc_gold_label)

	_close_btn = Button.new()
	_close_btn.text = "Close [ESC]"
	_close_btn.pressed.connect(close_trade)
	title_bar.add_child(_close_btn)

	# --- Main area (two inventory panels + details) ---
	var hbox_main := HBoxContainer.new()
	hbox_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox_main.add_theme_constant_override("separation", 10)
	vbox_root.add_child(hbox_main)

	# Player side
	var player_vbox := _build_inventory_panel(
		"Your Inventory",
		true,   # player side
		_player_grid,
		_player_stats_label
	)
	hbox_main.add_child(player_vbox)

	var sep := VSeparator.new()
	hbox_main.add_child(sep)

	# NPC side
	var npc_vbox := _build_inventory_panel(
		"Merchant's Goods",
		false,  # npc side
		_npc_grid,
		_npc_stats_label
	)
	hbox_main.add_child(npc_vbox)

	# Detail panel (right column)
	_detail_panel = _build_detail_panel()
	hbox_main.add_child(_detail_panel)

	# Hint label
	var hint := Label.new()
	hint.text = "Drag items between panels to trade  •  Click an item then press Buy/Sell to transfer"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.7, 0.7, 0.7)
	vbox_root.add_child(hint)


func _build_inventory_panel(
		title: String,
		is_player: bool,
		_out_grid,  ## written below – returned via member vars
		_out_stats  ## same
) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lbl)

	var stats_lbl := Label.new()
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(stats_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# Write to the correct member
	if is_player:
		_player_grid = grid
		_player_stats_label = stats_lbl
	else:
		_npc_grid = grid
		_npc_stats_label = stats_lbl

	return vbox


func _build_detail_panel() -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	margin.add_child(inner)

	_detail_name = Label.new()
	_detail_name.text = "Select an item"
	_detail_name.add_theme_font_size_override("font_size", 15)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 12)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.modulate = Color(0.85, 0.85, 0.85)
	inner.add_child(_detail_desc)

	_detail_stats = Label.new()
	_detail_stats.add_theme_font_size_override("font_size", 11)
	_detail_stats.modulate = Color(0.7, 0.9, 0.7)
	inner.add_child(_detail_stats)

	_detail_price = Label.new()
	_detail_price.add_theme_font_size_override("font_size", 13)
	_detail_price.modulate = Color(1.0, 0.85, 0.2)
	inner.add_child(_detail_price)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	_transfer_btn = Button.new()
	_transfer_btn.text = "Transfer"
	_transfer_btn.disabled = true
	_transfer_btn.pressed.connect(_on_transfer_pressed)
	inner.add_child(_transfer_btn)

	return panel


# =============================
# SLOT STYLING
# =============================

func _style_slot(btn: Button, rarity: Item.Rarity) -> void:
	var style := StyleBoxFlat.new()
	match rarity:
		Item.Rarity.COMMON:
			style.bg_color = Color(0.18, 0.18, 0.18, 0.85)
			style.border_color = Color(0.45, 0.45, 0.45)
		Item.Rarity.UNCOMMON:
			style.bg_color = Color(0.08, 0.25, 0.08, 0.85)
			style.border_color = Color(0.2, 0.75, 0.2)
		Item.Rarity.RARE:
			style.bg_color = Color(0.08, 0.16, 0.35, 0.85)
			style.border_color = Color(0.3, 0.5, 1.0)
		Item.Rarity.EPIC:
			style.bg_color = Color(0.25, 0.08, 0.35, 0.85)
			style.border_color = Color(0.6, 0.3, 0.9)
		Item.Rarity.LEGENDARY:
			style.bg_color = Color(0.35, 0.15, 0.0, 0.85)
			style.border_color = Color(1.0, 0.6, 0.0)
		Item.Rarity.UNIQUE:
			style.bg_color = Color(0.35, 0.28, 0.0, 0.85)
			style.border_color = Color(1.0, 0.84, 0.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.2)

	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed.bg_color.lightened(0.35)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
