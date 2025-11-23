extends Node
@onready var overworld_map: Node2D = $OverworldMap
@onready var player: CharacterBody2D = $Player
@onready var pause: Node2D = $CanvasLayer/pause

const SAVE_PATH := "user://save_game_file.tres"
var _save := SaveGameResource.new()

# Optional: call this from your Game.gd on startup with your overworld MainGameState.settlements
# entries: [{ "type": SettlementType.TOWN, "pos": Vector2i(13,21), "seed": 123 }, ...]
func bootstrap_settlements() -> void:
	for s in MainGameState.settlements.values():
		MainGameState.ensure_settlement_config(s.type, s.pos, s.get("seed", 0))

func _ready() -> void:
	# If you already know MainGameState.settlements at launch, call:
	create_or_load_save()
	# bootstrap_settlements()

func _deterministic_seed(settlement_type: int, pos: Vector2i) -> int:
	var v := int(settlement_type) * 83492791 ^ (pos.x * 73856093) ^ (pos.y * 19349663)
	return abs(v) # stable across runs

func get_all_settlements() -> Array:
	var out: Array = []
	for s in MainGameState.settlements.values():
		print("Found settlement: ", s)
		var t: int = s.type
		var p: Vector2i = s.pos
		out.append({
			"type": t,
			"pos": p,
			"seed": _deterministic_seed(t, p)
		})
	return out

func create_new_settlement_config():
	var config := AreaConfig.new()
	# Decide a filename using your existing key maker
	var pos := Vector2i(13, 21)
	var stype := MainGameState.SettlementType.TOWN
	var key := MainGameState.make_settlement_key(stype, pos) # scripts/main_game_state.gd
	var path := "res://resources/settlements/%s.tres" % key

	# Create and save
	var result := AreaConfig.create_and_save(path, {
		"area_type": AreaConfig.AreaType.TOWN,
		"settlement_name": "Ravenford",
		"climate": "temperate",
		"culture": "midlands"
	})
	if result.error == OK:
		print("Saved: ", path)
		var cfg := load(path) as AreaConfig
		print("Loaded settlement name: ", cfg.settlement_name)
	else:
		push_error("Failed to save AreaConfig: %s" % result.error)
	return config

func create_or_load_save():
	if SaveGameResource.save_exists():
		_save = SaveGameResource.load_savegame()
	else:
		_save = SaveGameResource.new()
		_save.player_position = player.global_position
		_save.player_current_scene_path = get_tree().current_scene.scene_file_path
		_save.write_savegame()
	load_game()

func _on_pause_button_pressed() -> void:
	get_tree().paused = true
	pause.show()


func load_game() -> void:
	player.global_position = _save.player_position
	# player.current_scene = _save.player_current_scene_path

	# if ResourceLoader.exists(SAVE_PATH):
	# 	_save = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	# else:
	# 	_save = SaveGameResource.new()

func save_game() -> void:
	_save.player_position = player.global_position
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path
	_save.write_savegame()
