extends Node2D

const SAVE_PATH := "user://save_game_file.tres"

@onready var player: CharacterBody2D = $"../../Player"
@onready var overworld: Node2D = $"../.."

var _save: SaveGameResource

func _ready():
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_save = overworld._save

func _on_resume_pressed() -> void:
	hide()
	get_tree().paused = false

func quit_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_save_game_pressed() -> void:
	overworld.save_game()
	
func _on_load_game_pressed() -> void:
	overworld.load_game()
	
func _on_quit_pressed() -> void:
	quit_to_main_menu()
