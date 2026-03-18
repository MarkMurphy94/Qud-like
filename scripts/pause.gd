extends Control

@onready var player: CharacterBody2D = $"../../Player"
@onready var overworld: Node2D = $"../.."

const PICKER_SCENE := preload("res://scenes/save_slot_picker.tscn")
const PICKER_SCRIPT := preload("res://scripts/save_slot_picker.gd")

var _save: SaveGameResource
var _picker: Node = null
var _picker_mode: int = -1  # tracks whether we opened Save or Load

func _ready():
	# PROCESS_MODE_ALWAYS so buttons are clickable regardless of tree pause state.
	# The menu is shown/hidden explicitly, so this is safe.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_parent().process_mode = Node.PROCESS_MODE_ALWAYS  # CanvasLayer must also always process
	_save = overworld._save
	hide()  # Start hidden

# ─── Resume ─────────────────────────────────────────────────────────────
func _on_resume_pressed() -> void:
	hide()
	get_tree().paused = false

# ─── Quit to Main Menu ─────────────────────────────────────────────────
func quit_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ─── Save Game → open picker in SAVE mode ──────────────────────────────
func _on_save_game_pressed() -> void:
	_open_picker(PICKER_SCRIPT.Mode.SAVE)

# ─── Load Game → open picker in LOAD mode ──────────────────────────────
func _on_load_game_pressed() -> void:
	_open_picker(PICKER_SCRIPT.Mode.LOAD)

# ─── Quit ───────────────────────────────────────────────────────────────
func _on_quit_pressed() -> void:
	quit_to_main_menu()

# ═══════════════════════════════════════════════════════════════════════
#  SLOT PICKER HELPERS
# ═══════════════════════════════════════════════════════════════════════

func _open_picker(mode: int) -> void:
	if _picker and is_instance_valid(_picker):
		_picker.queue_free()
	_picker_mode = mode
	_picker = PICKER_SCENE.instantiate()
	# Add to the CanvasLayer parent so it renders above everything
	get_parent().add_child(_picker)
	_picker.slot_selected.connect(_on_slot_selected)
	_picker.picker_closed.connect(_on_picker_closed)
	_picker.open(mode)

func _on_slot_selected(slot: int) -> void:
	if _picker_mode == PICKER_SCRIPT.Mode.SAVE:
		overworld.save_game_to_slot(slot)
	elif _picker_mode == PICKER_SCRIPT.Mode.LOAD:
		# Unpause first so the game can run the load logic
		get_tree().paused = false
		overworld.load_game_from_slot(slot)
		hide()
	_cleanup_picker()

func _on_picker_closed() -> void:
	_cleanup_picker()

func _cleanup_picker() -> void:
	if _picker and is_instance_valid(_picker):
		_picker.queue_free()
		_picker = null
	_picker_mode = -1
