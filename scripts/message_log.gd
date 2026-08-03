extends CanvasLayer
## MessageLog — the running narration of everything that happens in the world.
##
## In a turn-based game with no combat mode, the log is how the player finds
## out what the turn they just spent actually accomplished: who swung at them,
## what died, what a spell did. It listens to TurnManager.message_logged and
## does nothing else, so any system can narrate itself with one call:
##
##     TurnManager.log_message("The bandit lunges at you!", "attack")
##
## Edit the layout in scenes/message_log.tscn.

@onready var log_scroll: ScrollContainer = $LogPanel/MarginContainer/VBoxContainer/LogScroll
@onready var log_list: VBoxContainer = $LogPanel/MarginContainer/VBoxContainer/LogScroll/LogList

## Oldest lines are dropped past this to keep the node count bounded.
const MAX_LOG_LINES := 40

const C_LOG_INFO   := Color(0.75, 0.75, 0.80)
const C_LOG_MOVE   := Color(0.55, 0.65, 0.85)
const C_LOG_ATTACK := Color(0.95, 0.55, 0.45)
const C_LOG_SPELL  := Color(0.70, 0.55, 0.95)
const C_LOG_DEATH  := Color(0.95, 0.30, 0.30)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TurnManager.message_logged.connect(_on_message_logged)


func _on_message_logged(text: String, category: String) -> void:
	var line := Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 11)
	line.add_theme_color_override("font_color", _colour_for(category))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 264
	log_list.add_child(line)

	while log_list.get_child_count() > MAX_LOG_LINES:
		var oldest := log_list.get_child(0)
		log_list.remove_child(oldest)
		oldest.queue_free()

	# The new label has no size until the next layout pass, so scrolling to the
	# bottom has to wait for it.
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _colour_for(category: String) -> Color:
	match category:
		"move":   return C_LOG_MOVE
		"attack": return C_LOG_ATTACK
		"spell":  return C_LOG_SPELL
		"death":  return C_LOG_DEATH
		_:        return C_LOG_INFO
