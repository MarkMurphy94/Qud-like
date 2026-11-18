extends CanvasLayer

## Shown by MainGame when the player dies. Pauses the tree until Continue,
## which MainGame answers by restoring the respawn checkpoint.
##
## report keys: "killer", "place", "when", "respawn" (all Strings).

signal continue_pressed

const C_TITLE := Color(0.95, 0.30, 0.30)
const C_DIM := Color(0.75, 0.75, 0.75)


## Call once the screen is in the tree.
func show_report(report: Dictionary) -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := _label("You have died", C_TITLE)
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(HSeparator.new())

	box.add_child(_label("Slain by %s" % report.get("killer", "unknown causes")))
	box.add_child(_label("in %s" % report.get("place", "parts unknown")))
	box.add_child(_label("on %s" % report.get("when", "an unrecorded day")))
	box.add_child(HSeparator.new())

	var respawn: String = report.get("respawn", "")
	if respawn != "":
		box.add_child(_label("You wake again in %s. All that happened since you arrived there is undone." % respawn, C_DIM))

	var button := Button.new()
	button.text = "Continue"
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(120, 0)
	button.pressed.connect(_on_continue)
	box.add_child(button)
	button.grab_focus.call_deferred()


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


func _on_continue() -> void:
	get_tree().paused = false
	continue_pressed.emit()
	queue_free()
