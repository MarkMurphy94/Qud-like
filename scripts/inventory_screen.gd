extends CanvasLayer
class_name InventoryScreen

## Inventory UI screen that displays the player's inventory
## Shows items in a grid, allows sorting, and displays item details

signal inventory_closed

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleBar/TitleLabel
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var sort_option: OptionButton = $Panel/MarginContainer/VBoxContainer/TopBar/SortOption
@onready var weight_label: Label = $Panel/MarginContainer/VBoxContainer/TopBar/WeightLabel
@onready var value_label: Label = $Panel/MarginContainer/VBoxContainer/TopBar/ValueLabel
@onready var item_grid: GridContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/ItemGrid
@onready var item_details: Panel = $Panel/MarginContainer/VBoxContainer/BottomPanel/ItemDetails
@onready var item_name_label: Label = $Panel/MarginContainer/VBoxContainer/BottomPanel/ItemDetails/VBoxContainer/ItemNameLabel
@onready var item_desc_label: Label = $Panel/MarginContainer/VBoxContainer/BottomPanel/ItemDetails/VBoxContainer/ItemDescLabel
@onready var item_stats_label: Label = $Panel/MarginContainer/VBoxContainer/BottomPanel/ItemDetails/VBoxContainer/ItemStatsLabel
@onready var action_buttons: HBoxContainer = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons
@onready var use_button: Button = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons/UseButton
@onready var drop_button: Button = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons/DropButton
@onready var drop_amount: SpinBox = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons/DropAmount

## Reference to the inventory being displayed
var inventory: Inventory = null

## Currently selected slot index
var selected_slot_index: int = -1

## Item slot scene for displaying items
var item_slot_scene: PackedScene

## Array of item slot buttons
var item_slots: Array = []


func _ready():
	# Hide by default
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Create item slot scene programmatically if not preloaded
	_create_item_slot_scene()
	
	# Connect signals
	close_button.pressed.connect(_on_close_button_pressed)
	use_button.pressed.connect(_on_use_button_pressed)
	drop_button.pressed.connect(_on_drop_button_pressed)
	sort_option.item_selected.connect(_on_sort_option_selected)
	
	# Setup sort options
	sort_option.clear()
	sort_option.add_item("Name", 0)
	sort_option.add_item("Type", 1)
	sort_option.add_item("Value", 2)
	sort_option.add_item("Weight", 3)
	sort_option.add_item("Rarity", 4)
	
	# Disable action buttons initially
	use_button.disabled = true
	drop_button.disabled = true
	drop_amount.visible = false


func _input(event):
	if not visible:
		return
	
	# Close inventory with ESC or inventory key
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_inventory"):
		_on_close_button_pressed()
		get_viewport().set_input_as_handled()


func open_inventory(player_inventory: Inventory):
	"""Open the inventory screen and display the given inventory"""
	inventory = player_inventory
	
	if not inventory:
		push_error("[InventoryScreen] Cannot open with null inventory")
		return
	
	# Connect to inventory signals
	if not inventory.inventory_changed.is_connected(_on_inventory_changed):
		inventory.inventory_changed.connect(_on_inventory_changed)
	
	refresh_inventory()
	show()
	
	# Pause the game when inventory is open
	get_tree().paused = true


func close_inventory():
	"""Close the inventory screen"""
	if inventory and inventory.inventory_changed.is_connected(_on_inventory_changed):
		inventory.inventory_changed.disconnect(_on_inventory_changed)
	
	selected_slot_index = -1
	hide()
	
	# Unpause the game
	get_tree().paused = false
	
	inventory_closed.emit()


func refresh_inventory():
	"""Refresh the entire inventory display"""
	if not inventory:
		return
	
	# Clear existing slots
	_clear_item_slots()
	
	# Update stats
	_update_stats_display()
	
	# Create slots for each item
	var items = inventory.get_all_items()
	for i in range(items.size()):
		var slot_data = items[i]
		_create_item_slot(slot_data, i)
	
	# Clear selection if invalid
	if selected_slot_index >= items.size():
		selected_slot_index = -1
		_update_item_details(null, 0)


func _clear_item_slots():
	"""Remove all item slot buttons"""
	for slot in item_slots:
		slot.queue_free()
	item_slots.clear()


func _create_item_slot(slot_data: Dictionary, index: int):
	"""Create an item slot button and add it to the grid"""
	var slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(64, 64)
	slot_button.toggle_mode = false
	
	# Create slot content
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Item icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var item: Item = slot_data.item
	var item_icon = item.get_icon()
	if item_icon:
		icon.texture = item_icon
	
	# Quantity label
	var quantity_label = Label.new()
	quantity_label.text = "x%d" % slot_data.quantity if slot_data.quantity > 1 else ""
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.add_theme_font_size_override("font_size", 12)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	vbox.add_child(icon)
	vbox.add_child(quantity_label)
	slot_button.add_child(vbox)
	
	# Style based on rarity
	_style_slot_button(slot_button, item.rarity)
	
	# Connect pressed signal
	slot_button.pressed.connect(_on_item_slot_pressed.bind(index))
	
	# Add tooltip
	slot_button.tooltip_text = _get_item_tooltip(item, slot_data.quantity)
	
	item_grid.add_child(slot_button)
	item_slots.append(slot_button)


func _style_slot_button(button: Button, rarity: Item.Rarity):
	"""Apply styling to a slot button based on item rarity"""
	var style = StyleBoxFlat.new()
	
	match rarity:
		Item.Rarity.COMMON:
			style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style.border_color = Color(0.5, 0.5, 0.5)
		Item.Rarity.UNCOMMON:
			style.bg_color = Color(0.1, 0.3, 0.1, 0.8)
			style.border_color = Color(0.2, 0.8, 0.2)
		Item.Rarity.RARE:
			style.bg_color = Color(0.1, 0.2, 0.4, 0.8)
			style.border_color = Color(0.3, 0.5, 1.0)
		Item.Rarity.EPIC:
			style.bg_color = Color(0.3, 0.1, 0.4, 0.8)
			style.border_color = Color(0.6, 0.3, 0.8)
		Item.Rarity.LEGENDARY:
			style.bg_color = Color(0.4, 0.2, 0.0, 0.8)
			style.border_color = Color(1.0, 0.6, 0.0)
		Item.Rarity.UNIQUE:
			style.bg_color = Color(0.4, 0.3, 0.0, 0.8)
			style.border_color = Color(1.0, 0.84, 0.0)
	
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", _create_hover_style(style))
	button.add_theme_stylebox_override("pressed", _create_pressed_style(style))


func _create_hover_style(base_style: StyleBoxFlat) -> StyleBoxFlat:
	var hover = base_style.duplicate()
	hover.bg_color = hover.bg_color.lightened(0.2)
	return hover


func _create_pressed_style(base_style: StyleBoxFlat) -> StyleBoxFlat:
	var pressed = base_style.duplicate()
	pressed.bg_color = pressed.bg_color.lightened(0.3)
	return pressed


func _get_item_tooltip(item: Item, quantity: int) -> String:
	"""Generate tooltip text for an item"""
	var tooltip = item.get_display_name()
	if quantity > 1:
		tooltip += " x%d" % quantity
	tooltip += "\n" + item.get_rarity_name()
	if item.weight > 0:
		tooltip += "\nWeight: %.1f kg" % (item.weight * quantity)
	if item.base_value > 0:
		tooltip += "\nValue: %d gold" % (item.get_total_value() * quantity)
	return tooltip


func _update_stats_display():
	"""Update the weight and value display"""
	if not inventory:
		return
	
	var current_weight = inventory.get_total_weight()
	var max_weight = inventory.max_weight if inventory.max_weight > 0 else 999999.0
	var total_value = inventory.get_total_value()
	
	weight_label.text = "Weight: %.1f / %.1f kg" % [current_weight, max_weight]
	value_label.text = "Value: %d gold" % total_value


func _update_item_details(item: Item, quantity: int):
	"""Update the item details panel"""
	if not item:
		item_name_label.text = "No item selected"
		item_desc_label.text = ""
		item_stats_label.text = ""
		use_button.disabled = true
		drop_button.disabled = true
		drop_amount.visible = false
		return
	
	item_name_label.text = item.get_display_name()
	item_name_label.add_theme_color_override("font_color", item.get_rarity_color())
	
	item_desc_label.text = item.description if item.description else "No description"
	
	# Build stats text
	var stats = []
	stats.append("Type: %s" % Item.ItemType.keys()[item.item_type])
	stats.append("Rarity: %s" % item.get_rarity_name())
	stats.append("Weight: %.1f kg" % item.weight)
	stats.append("Value: %d gold" % item.get_total_value())
	if quantity > 1:
		stats.append("Quantity: %d" % quantity)
	
	item_stats_label.text = "\n".join(stats)
	
	# Enable/disable buttons
	use_button.disabled = not _can_use_item(item)
	drop_button.disabled = not item.can_drop
	
	# Setup drop amount
	if quantity > 1:
		drop_amount.visible = true
		drop_amount.min_value = 1
		drop_amount.max_value = quantity
		drop_amount.value = 1
	else:
		drop_amount.visible = false


func _can_use_item(item: Item) -> bool:
	"""Check if an item can be used"""
	# For now, only consumables can be used
	return item.item_type == Item.ItemType.CONSUMABLE


func _create_item_slot_scene():
	"""Create the item slot scene programmatically"""
	# This is a fallback - ideally you'd have a proper scene file
	pass


# Signal handlers

func _on_close_button_pressed():
	close_inventory()


func _on_item_slot_pressed(index: int):
	"""Called when an item slot is clicked"""
	selected_slot_index = index
	
	if not inventory:
		return
	
	var slot = inventory.get_slot(index)
	if slot.is_empty():
		_update_item_details(null, 0)
		return
	
	_update_item_details(slot.item, slot.quantity)


func _on_use_button_pressed():
	"""Called when Use button is clicked"""
	if selected_slot_index < 0 or not inventory:
		return
	
	var slot = inventory.get_slot(selected_slot_index)
	if slot.is_empty():
		return
	
	var item = slot.item
	
	# TODO: Implement actual item usage (consume potion, equip weapon, etc.)
	print("Using item: %s" % item.get_display_name())
	
	# For consumables, remove one from inventory
	if item.item_type == Item.ItemType.CONSUMABLE:
		inventory.remove_item_at_slot(selected_slot_index, 1)
		# The inventory_changed signal will trigger refresh


func _on_drop_button_pressed():
	"""Called when Drop button is clicked"""
	if selected_slot_index < 0 or not inventory:
		return
	
	var slot = inventory.get_slot(selected_slot_index)
	if slot.is_empty():
		return
	
	var item = slot.item
	var amount = int(drop_amount.value) if drop_amount.visible else 1
	
	# Get player reference to drop item in world
	var player = get_tree().get_first_node_in_group("Player")
	if player and player.has_method("drop_item"):
		if player.drop_item(item.id, amount):
			print("Dropped %d x %s" % [amount, item.get_display_name()])
		# The inventory_changed signal will trigger refresh


func _on_sort_option_selected(index: int):
	"""Called when sort option is changed"""
	if not inventory:
		return
	
	match index:
		0: inventory.sort_by("name")
		1: inventory.sort_by("type")
		2: inventory.sort_by("value")
		3: inventory.sort_by("weight")
		4: inventory.sort_by("rarity")
	
	# Refresh will happen via inventory_changed signal


func _on_inventory_changed():
	"""Called when inventory contents change"""
	refresh_inventory()
