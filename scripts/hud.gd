extends CanvasLayer

@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/HPContainer/HPBar
@onready var mp_bar: ProgressBar = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/MPContainer/MPBar
@onready var sp_bar: ProgressBar = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/SPContainer/SPBar
@onready var hp_value: Label = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/HPContainer/HPValue
@onready var mp_value: Label = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/MPContainer/MPValue
@onready var sp_value: Label = $MarginContainer/VBoxContainer/TopContainer/BarsContainer/SPContainer/SPValue
@onready var pause_button: Button = $MarginContainer/VBoxContainer/TopContainer/PauseButton
@onready var inventory: Button = $MarginContainer/VBoxContainer/TopContainer/inventory
@onready var hotbar_container: HBoxContainer = $MarginContainer/VBoxContainer/HotbarContainer

const HOTBAR_SLOTS := 9
const SLOT_SIZE := 48  # pixels per slot

## Each entry: { "type": "item"/"spell", "data": Item/Spell } or null
var hotbar_slots: Array = []
## Parallel array of slot Panel nodes
var hotbar_slot_nodes: Array = []

var player_inventory = null
var inventory_screen_scene = load("res://scenes/inventory_screen.tscn")
var inventory_screen_instance = null

signal pause_requested

func _ready() -> void:
	pause_button.pressed.connect(_on_pause_button_pressed)
	inventory.pressed.connect(_on_inventory_pressed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_style_bars()
	_build_hotbar()

func _style_bars() -> void:
	# HP = Red, MP = Blue, SP = Green
	_set_bar_color(hp_bar, Color(0.8, 0.2, 0.2), Color(0.3, 0.1, 0.1))
	_set_bar_color(mp_bar, Color(0.2, 0.4, 0.9), Color(0.1, 0.15, 0.35))
	_set_bar_color(sp_bar, Color(0.2, 0.75, 0.2), Color(0.1, 0.3, 0.1))

func _set_bar_color(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)

func update_hp(current: int, max_value: int) -> void:
	hp_bar.max_value = max_value
	hp_bar.value = current
	hp_value.text = "%d/%d" % [current, max_value]

func update_mp(current: int, max_value: int) -> void:
	mp_bar.max_value = max_value
	mp_bar.value = current
	mp_value.text = "%d/%d" % [current, max_value]

func update_sp(current: int, max_value: int) -> void:
	sp_bar.max_value = max_value
	sp_bar.value = current
	sp_value.text = "%d/%d" % [current, max_value]

func _on_pause_button_pressed() -> void:
	emit_signal("pause_requested")

func _on_inventory_pressed() -> void:
	# Check if inventory screen already exists
	if inventory_screen_instance and is_instance_valid(inventory_screen_instance):
		# If it's already visible, toggle it closed
		if inventory_screen_instance.visible:
			inventory_screen_instance.close_inventory()
			return
		else:
			# If it exists but is hidden, show it again
			player_inventory = get_parent().inventory
			if player_inventory:
				inventory_screen_instance.open_inventory(player_inventory)
			return
	
	# Create new inventory screen instance
	inventory_screen_instance = inventory_screen_scene.instantiate()
	add_child(inventory_screen_instance)
	
	# Connect to closed signal to clean up reference
	inventory_screen_instance.inventory_closed.connect(_on_inventory_screen_closed)
	
	# Open with player's inventory
	player_inventory = get_parent().inventory
	if player_inventory:
		inventory_screen_instance.open_inventory(player_inventory)

func _on_inventory_screen_closed() -> void:
	# Keep the instance around for reuse, just hide it
	pass

# =============================
# HOTBAR
# =============================

func _build_hotbar() -> void:
	hotbar_slots.resize(HOTBAR_SLOTS)
	hotbar_slot_nodes.resize(HOTBAR_SLOTS)

	for i in range(HOTBAR_SLOTS):
		hotbar_slots[i] = null

		# Outer panel for border/background
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_style_hotbar_slot(panel, false)

		# Key number label (top-left)
		var key_label := Label.new()
		key_label.text = str(i + 1)
		key_label.add_theme_font_size_override("font_size", 10)
		key_label.position = Vector2(2, 0)
		key_label.size = Vector2(14, 14)
		panel.add_child(key_label)

		# Icon texture
		var icon_rect := TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.position = Vector2(10, 10)
		icon_rect.size = Vector2(28, 28)
		panel.add_child(icon_rect)

		# Quantity label (bottom-right, only for stackable items)
		var qty_label := Label.new()
		qty_label.name = "Qty"
		qty_label.add_theme_font_size_override("font_size", 10)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.position = Vector2(2, SLOT_SIZE - 16)
		qty_label.size = Vector2(SLOT_SIZE - 4, 14)
		qty_label.visible = false
		panel.add_child(qty_label)

		# Tooltip-style name label (shown as panel tooltip)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.add_theme_font_size_override("font_size", 9)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = Vector2(0, SLOT_SIZE - 14)
		name_label.size = Vector2(SLOT_SIZE, 12)
		name_label.clip_text = true
		name_label.visible = false
		panel.add_child(name_label)

		# Click button (transparent, covers whole slot)
		var btn := Button.new()
		btn.flat = true
		btn.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		btn.position = Vector2.ZERO
		var idx := i  # capture
		btn.pressed.connect(func(): _on_hotbar_slot_pressed(idx))
		panel.add_child(btn)

		hotbar_container.add_child(panel)
		hotbar_slot_nodes[i] = panel

func _style_hotbar_slot(panel: Panel, active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.82) if not active else Color(0.25, 0.55, 0.85, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.55, 0.55, 0.9) if not active else Color(1.0, 0.85, 0.2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)

## Called by Player._on_item_added – auto-assigns first new consumable slot.
func notify_item_added(item: Item, _quantity: int) -> void:
	if item.item_type != Item.ItemType.CONSUMABLE:
		return
	# Check if this item is already on the hotbar
	for i in range(HOTBAR_SLOTS):
		var slot = hotbar_slots[i]
		if slot != null and slot.type == "item" and slot.data.id == item.id:
			_refresh_slot_visual(i)
			return
	# Auto-assign to first empty slot
	_assign_item(item)

## Called by Player.learn_spell – auto-assigns newly learned spell.
func notify_spell_learned(spell: Spell) -> void:
	# Check if already on hotbar
	for i in range(HOTBAR_SLOTS):
		var slot = hotbar_slots[i]
		if slot != null and slot.type == "spell" and slot.data.id == spell.id:
			return
	_assign_spell(spell)

## Assign an item to the first empty hotbar slot.
func _assign_item(item: Item) -> void:
	for i in range(HOTBAR_SLOTS):
		if hotbar_slots[i] == null:
			hotbar_slots[i] = { "type": "item", "data": item }
			_refresh_slot_visual(i)
			return

## Assign a spell to the first empty hotbar slot.
func _assign_spell(spell: Spell) -> void:
	for i in range(HOTBAR_SLOTS):
		if hotbar_slots[i] == null:
			hotbar_slots[i] = { "type": "spell", "data": spell }
			_refresh_slot_visual(i)
			return

## Refresh the visual for a single slot based on hotbar_slots[index].
func _refresh_slot_visual(index: int) -> void:
	var panel: Panel = hotbar_slot_nodes[index]
	if not panel:
		return
	var icon_rect: TextureRect = panel.get_node("Icon")
	var qty_label: Label = panel.get_node("Qty")
	var name_label: Label = panel.get_node("Name")
	var slot = hotbar_slots[index]

	if slot == null:
		icon_rect.texture = null
		qty_label.visible = false
		name_label.visible = false
		_style_hotbar_slot(panel, false)
		return

	if slot.type == "item":
		var item: Item = slot.data
		icon_rect.texture = item.icon if item.icon else null
		# Show quantity from player inventory
		var player = get_parent()
		if player and player.inventory:
			var qty: int = player.inventory.get_item_quantity(item.id) if player.inventory.has_method("get_item_quantity") else 0
			if qty > 0 and item.stackable:
				qty_label.text = str(qty)
				qty_label.visible = true
			else:
				qty_label.visible = false
		else:
			qty_label.visible = false
		name_label.text = item.get_display_name() if item.has_method("get_display_name") else item.display_name
		name_label.visible = true
	elif slot.type == "spell":
		var spell: Spell = slot.data
		icon_rect.texture = null  # spells may not have icons yet
		qty_label.visible = false
		name_label.text = spell.get_display_name() if spell.has_method("get_display_name") else spell.display_name
		name_label.visible = true

## Remove a consumed/empty item slot from the hotbar.
func remove_hotbar_item(item_id: String) -> void:
	for i in range(HOTBAR_SLOTS):
		var slot = hotbar_slots[i]
		if slot != null and slot.type == "item" and slot.data.id == item_id:
			hotbar_slots[i] = null
			_refresh_slot_visual(i)
			return

## Remove a specific spell from the hotbar (e.g. if unlearned).
func remove_hotbar_spell(spell_id: String) -> void:
	for i in range(HOTBAR_SLOTS):
		var slot = hotbar_slots[i]
		if slot != null and slot.type == "spell" and slot.data.id == spell_id:
			hotbar_slots[i] = null
			_refresh_slot_visual(i)
			return

func _on_hotbar_slot_pressed(index: int) -> void:
	_use_hotbar_slot(index)

func _use_hotbar_slot(index: int) -> void:
	if index < 0 or index >= HOTBAR_SLOTS:
		return
	var slot = hotbar_slots[index]
	if slot == null:
		return

	var player = get_parent()
	if not player:
		return

	if slot.type == "item":
		var item: Item = slot.data
		# Use the item via player
		if player.has_method("use_item"):
			player.use_item(item.id)
		elif player.inventory:
			# Fallback: trigger use logic directly for consumables
			var inv = player.inventory
			if inv.has_item(item.id):
				if item.item_type == Item.ItemType.CONSUMABLE:
					var consumable = item as ItemConsumable
					if consumable and player.has_method("apply_consumable_effect"):
						player.apply_consumable_effect(consumable)
						inv.remove_item(item.id, 1)
						_refresh_slot_visual(index)
						# Clean up slot if item is fully depleted
						if not inv.has_item(item.id):
							hotbar_slots[index] = null
							_refresh_slot_visual(index)
	elif slot.type == "spell":
		var spell: Spell = slot.data
		if player.has_method("_on_spell_cast_requested"):
			player._on_spell_cast_requested(spell)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# Keys 1–9 trigger hotbar slots
	var key_map := {
		KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4,
		KEY_6: 5, KEY_7: 6, KEY_8: 7, KEY_9: 8
	}
	if key_map.has(event.keycode):
		_use_hotbar_slot(key_map[event.keycode])
		get_viewport().set_input_as_handled()
