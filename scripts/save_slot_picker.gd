extends CanvasLayer

## A full-screen overlay that lists save slots for Save, Load, or Delete.
## Emits `slot_selected(slot_index)` when the player picks a slot,
## or `picker_closed` when they press Back / Escape.

signal slot_selected(slot_index: int)
signal picker_closed

enum Mode { SAVE, LOAD }

var current_mode: Mode = Mode.LOAD

@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var slot_list: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/SlotList
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/BottomBar/BackButton
@onready var panel: PanelContainer = $PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while paused
	back_button.pressed.connect(_on_back_pressed)
	hide()

func open(mode: Mode) -> void:
	current_mode = mode
	title_label.text = "Save Game" if mode == Mode.SAVE else "Load Game"
	_refresh_slots()
	show()

# ─── Build slot entries ─────────────────────────────────────────────────
func _refresh_slots() -> void:
	# Clear old entries
	for child in slot_list.get_children():
		child.queue_free()

	var summaries := SaveGameResource.get_all_slot_summaries()
	var occupied_slots: Dictionary = {}
	for s in summaries:
		occupied_slots[s.slot] = s

	for i in range(SaveGameResource.MAX_SLOTS):
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if occupied_slots.has(i):
			var info: Dictionary = occupied_slots[i]
			_add_occupied_slot(row, i, info)
		else:
			_add_empty_slot(row, i)

		slot_list.add_child(row)

func _add_occupied_slot(row: HBoxContainer, slot: int, info: Dictionary) -> void:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var play_str := _format_play_time(info.get("play_time", 0.0))
	var area_str := " [Local Area]" if info.get("in_local_area", false) else ""
	label.text = "Slot %d  —  %s  |  %s  |  %s%s" % [
		slot + 1,
		info.get("name", "Unnamed"),
		info.get("date", "???"),
		play_str,
		area_str,
	]
	row.add_child(label)

	# Select button (Save = overwrite, Load = load)
	var select_btn := Button.new()
	select_btn.text = "Save" if current_mode == Mode.SAVE else "Load"
	select_btn.custom_minimum_size.x = 70
	select_btn.pressed.connect(_on_slot_pressed.bind(slot))
	row.add_child(select_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size.x = 70
	del_btn.pressed.connect(_on_delete_pressed.bind(slot))
	row.add_child(del_btn)

func _add_empty_slot(row: HBoxContainer, slot: int) -> void:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "Slot %d  —  [ Empty ]" % (slot + 1)
	label.modulate = Color(0.5, 0.5, 0.5)
	row.add_child(label)

	if current_mode == Mode.SAVE:
		var select_btn := Button.new()
		select_btn.text = "Save"
		select_btn.custom_minimum_size.x = 70
		select_btn.pressed.connect(_on_slot_pressed.bind(slot))
		row.add_child(select_btn)
	else:
		# Can't load an empty slot — add spacer to keep alignment
		var spacer := Control.new()
		spacer.custom_minimum_size.x = 70
		row.add_child(spacer)

	# No delete for empty
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 70
	row.add_child(spacer2)

# ─── Callbacks ──────────────────────────────────────────────────────────
func _on_slot_pressed(slot: int) -> void:
	slot_selected.emit(slot)
	hide()

func _on_delete_pressed(slot: int) -> void:
	SaveGameResource.delete_slot(slot)
	_refresh_slots()

func _on_back_pressed() -> void:
	picker_closed.emit()
	hide()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()

# ─── Helpers ────────────────────────────────────────────────────────────
func _format_play_time(seconds: float) -> String:
	var total := int(seconds)
	@warning_ignore("integer_division")
	var h := total / 3600
	@warning_ignore("integer_division")
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	elif m > 0:
		return "%dm %02ds" % [m, s]
	else:
		return "%ds" % s
