extends Node2D

const SAVE_PATH := "user://save_game_file.tres"

var save_game_file: SaveGameResource = null

func _on_new_game_pressed() -> void:
	save_game_file = null
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	
func _on_load_game_pressed() -> void:
	load_game()

func _on_quit_pressed() -> void:
	get_tree().quit()

func load_game() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		save_game_file = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	else:
		save_game_file = SaveGameResource.new()
	get_tree().change_scene_to_file(save_game_file.player_current_scene_path)
