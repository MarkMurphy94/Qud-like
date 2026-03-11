extends CanvasLayer
class_name SpellBookScreen

## Spell Book UI screen that displays learned spells
## Shows spells in a grid with details and casting information

signal spell_book_closed
signal spell_cast_requested(spell: Spell)

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleBar/TitleLabel
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var filter_option: OptionButton = $Panel/MarginContainer/VBoxContainer/TopBar/FilterOption
@onready var spell_count_label: Label = $Panel/MarginContainer/VBoxContainer/TopBar/SpellCountLabel
@onready var spell_grid: GridContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/SpellGrid
@onready var spell_details: Panel = $Panel/MarginContainer/VBoxContainer/BottomPanel/SpellDetails
@onready var spell_name_label: Label = $Panel/MarginContainer/VBoxContainer/BottomPanel/SpellDetails/VBoxContainer/SpellNameLabel
@onready var spell_desc_label: Label = $Panel/MarginContainer/VBoxContainer/BottomPanel/SpellDetails/VBoxContainer/SpellDescLabel
@onready var spell_stats_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/BottomPanel/SpellDetails/VBoxContainer/SpellStatsLabel
@onready var action_buttons: HBoxContainer = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons
@onready var cast_button: Button = $Panel/MarginContainer/VBoxContainer/BottomPanel/ActionButtons/CastButton

## Reference to the player
var player = null

## Currently selected spell index
var selected_spell_index: int = -1

## Array of spell slot buttons
var spell_slots: Array = []

## Current filter
var current_filter: int = 0  # 0 = All, 1 = Offensive, 2 = Defensive, etc.


func _ready():
	# Hide by default
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect signals
	close_button.pressed.connect(_on_close_button_pressed)
	cast_button.pressed.connect(_on_cast_button_pressed)
	filter_option.item_selected.connect(_on_filter_option_selected)
	
	# Setup filter options
	filter_option.clear()
	filter_option.add_item("All", 0)
	filter_option.add_item("Offensive", 1)
	filter_option.add_item("Defensive", 2)
	filter_option.add_item("Healing", 3)
	filter_option.add_item("Utility", 4)
	filter_option.add_item("Buff", 5)
	filter_option.add_item("Debuff", 6)
	filter_option.add_item("Summoning", 7)
	
	# Disable cast button initially
	cast_button.disabled = true


func _input(event):
	if not visible:
		return
	
	# Close spell book with ESC
	if event.is_action_pressed("ui_cancel"):
		_on_close_button_pressed()
		get_viewport().set_input_as_handled()


func open_spell_book(player_ref):
	"""Open the spell book screen and display learned spells"""
	player = player_ref
	
	if not player:
		push_error("[SpellBookScreen] Cannot open with null player")
		return
	
	refresh_spells()
	show()
	
	# Pause the game when spell book is open
	get_tree().paused = true


func close_spell_book():
	"""Close the spell book screen"""
	selected_spell_index = -1
	hide()
	
	# Unpause the game
	get_tree().paused = false
	
	emit_signal("spell_book_closed")


func refresh_spells():
	"""Refresh the spell grid with current spells"""
	if not player:
		return
	
	# Clear existing spell slots
	for slot in spell_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	spell_slots.clear()
	
	# Clear grid
	for child in spell_grid.get_children():
		child.queue_free()
	
	var learned_spells = player.get_learned_spells()
	var filtered_spells = _filter_spells(learned_spells)
	
	# Update count label
	spell_count_label.text = "%d / %d Spells" % [filtered_spells.size(), learned_spells.size()]
	
	# Create spell slots
	for i in range(filtered_spells.size()):
		var spell = filtered_spells[i]
		var slot_button = _create_spell_slot(spell, i)
		spell_grid.add_child(slot_button)
		spell_slots.append(slot_button)
	
	# Clear selection
	selected_spell_index = -1
	_update_spell_details(null)


func _filter_spells(spells: Array[Spell]) -> Array[Spell]:
	"""Filter spells based on current filter"""
	if current_filter == 0:
		return spells
	
	var filtered: Array[Spell] = []
	for spell in spells:
		if int(spell.spell_type) == current_filter - 1:
			filtered.append(spell)
	
	return filtered


func _create_spell_slot(spell: Spell, index: int) -> Button:
	"""Create a button for a spell slot"""
	var button = Button.new()
	button.custom_minimum_size = Vector2(80, 80)
	button.pressed.connect(_on_spell_slot_pressed.bind(index))
	
	# Create content container
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(vbox)
	
	# Add spell icon if available
	var icon = spell.get_icon()
	if icon:
		var texture_rect = TextureRect.new()
		texture_rect.texture = icon
		texture_rect.custom_minimum_size = Vector2(48, 48)
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(texture_rect)
	
	# Add spell name
	var name_label = Label.new()
	name_label.text = spell.get_display_name()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.y = 20
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)
	
	# Add mana cost
	var cost_label = Label.new()
	cost_label.text = "%d MP" % spell.get_mana_cost()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 9)
	cost_label.add_theme_color_override("font_color", Color.CORNFLOWER_BLUE)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cost_label)
	
	return button


func _update_spell_details(spell: Spell):
	"""Update the spell details panel"""
	if not spell:
		spell_name_label.text = "No Spell Selected"
		spell_desc_label.text = ""
		spell_stats_label.text = ""
		cast_button.disabled = true
		return
	
	# Update name with rarity color
	spell_name_label.text = spell.get_display_name()
	spell_name_label.add_theme_color_override("font_color", spell.get_rarity_color())
	
	# Update description
	spell_desc_label.text = spell.description
	
	# Build stats text
	var stats_text = ""
	stats_text += "[b]Type:[/b] %s\n" % spell.get_spell_type_name()
	stats_text += "[b]Rarity:[/b] %s\n" % spell.get_rarity_name()
	stats_text += "[b]Mana Cost:[/b] %d\n" % spell.get_mana_cost()
	stats_text += "[b]Cast Time:[/b] %.1fs\n" % spell.cast_time
	if spell.cooldown > 0:
		stats_text += "[b]Cooldown:[/b] %.1fs\n" % spell.cooldown
	stats_text += "[b]Range:[/b] %.1f tiles\n" % spell.spell_range
	stats_text += "[b]Target:[/b] %s\n" % spell.get_target_type_name()
	
	if spell.damage > 0:
		stats_text += "[b]Damage:[/b] %d\n" % spell.get_damage()
	if spell.healing > 0:
		stats_text += "[b]Healing:[/b] %d\n" % spell.get_healing()
	if spell.aoe_radius > 0:
		stats_text += "[b]AOE Radius:[/b] %.1f tiles\n" % spell.aoe_radius
	if spell.duration > 0:
		stats_text += "[b]Duration:[/b] %.1fs\n" % spell.duration
	
	if spell.required_level > 1:
		stats_text += "[b]Required Level:[/b] %d\n" % spell.required_level
	if spell.required_skill != "":
		stats_text += "[b]Required Skill:[/b] %s (Lv %d)\n" % [spell.required_skill, spell.required_skill_level]
	
	spell_stats_label.text = stats_text
	
	# Enable/disable cast button based on if spell can be cast
	if player:
		cast_button.disabled = not spell.can_cast(player)
	else:
		cast_button.disabled = true


# Signal handlers

func _on_close_button_pressed():
	close_spell_book()


func _on_spell_slot_pressed(index: int):
	"""Called when a spell slot is clicked"""
	selected_spell_index = index
	
	if not player:
		return
	
	var learned_spells = player.get_learned_spells()
	var filtered_spells = _filter_spells(learned_spells)
	
	if index < 0 or index >= filtered_spells.size():
		_update_spell_details(null)
		return
	
	var spell = filtered_spells[index]
	_update_spell_details(spell)


func _on_cast_button_pressed():
	"""Called when Cast button is clicked"""
	if selected_spell_index < 0 or not player:
		return
	
	var learned_spells = player.get_learned_spells()
	var filtered_spells = _filter_spells(learned_spells)
	
	if selected_spell_index >= filtered_spells.size():
		return
	
	var spell = filtered_spells[selected_spell_index]
	
	# Check if spell can be cast
	if not spell.can_cast(player):
		print("Cannot cast %s right now" % spell.get_display_name())
		return
	
	# Close spell book and request spell cast
	close_spell_book()
	emit_signal("spell_cast_requested", spell)
	
	print("Casting: %s" % spell.get_display_name())


func _on_filter_option_selected(index: int):
	"""Called when filter option changes"""
	current_filter = index
	refresh_spells()
