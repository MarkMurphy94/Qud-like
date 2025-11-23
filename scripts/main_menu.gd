extends Node2D

const SAVE_PATH := "user://save_game_file.tres"

var save_game_file: SaveGameResource = null

func _on_new_game_pressed() -> void:
	SaveGameResource.reset_savegame()
	if SaveGameResource.save_exists():
		save_game_file = SaveGameResource.load_savegame()
	else:
		save_game_file = SaveGameResource.new()
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	
func _on_load_game_pressed() -> void:
	load_game()

func load_game() -> void:
	if SaveGameResource.save_exists():
		save_game_file = SaveGameResource.load_savegame()
	else:
		save_game_file = SaveGameResource.new()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
