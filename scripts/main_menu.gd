extends Node2D

## ─── Save-slot picker (shared scene) ──────────────────────────────────
const PICKER_SCENE := preload("res://scenes/save_slot_picker.tscn")
const PICKER_SCRIPT := preload("res://scripts/save_slot_picker.gd")
var _picker: Node = null

func _ready() -> void:
	# Disable Load Game button if there are no saves
	var load_btn = $ButtonManager/VBoxContainer/load_game
	load_btn.disabled = not SaveGameResource.any_save_exists()

# ═══════════════════════════════════════════════════════════════════════
#  NEW GAME — starts a blank game (no save loaded)
# ═══════════════════════════════════════════════════════════════════════

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

# ═══════════════════════════════════════════════════════════════════════
#  LOAD GAME — open slot picker in Load mode
# ═══════════════════════════════════════════════════════════════════════

func _on_load_game_pressed() -> void:
	if not SaveGameResource.any_save_exists():
		return
	_open_picker(PICKER_SCRIPT.Mode.LOAD)

func _open_picker(mode: int) -> void:
	if _picker and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = PICKER_SCENE.instantiate()
	add_child(_picker)
	_picker.slot_selected.connect(_on_slot_selected)
	_picker.picker_closed.connect(_on_picker_closed)
	_picker.open(mode)

func _on_slot_selected(slot: int) -> void:
	# Store the chosen slot index in a temporary autoload-friendly place
	# so game.tscn can pick it up after scene change.
	MainGameState.set_meta("pending_load_slot", slot)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_picker_closed() -> void:
	if _picker and is_instance_valid(_picker):
		_picker.queue_free()
		_picker = null

# ═══════════════════════════════════════════════════════════════════════
#  QUIT
# ═══════════════════════════════════════════════════════════════════════

func _on_quit_pressed() -> void:
	get_tree().quit()
