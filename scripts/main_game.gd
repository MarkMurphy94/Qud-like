extends Node
@onready var overworld_map = $OverworldMap
@onready var player: CharacterBody2D = $Player
@onready var pause: Node2D = $CanvasLayer/pause
@onready var area_container: Node2D = $AreaContainer

const SAVE_PATH := "user://save_game_file.tres"
var _save := SaveGameResource.new()
var world_tile_data: Dictionary = {}

# Optional: call this from your Game.gd on startup with your overworld MainGameState.settlements
# entries: [{ "type": SettlementType.TOWN, "pos": Vector2i(13,21), "seed": 123 }, ...]

func _ready() -> void:
	# If you already know MainGameState.settlements at launch, call:
	create_or_load_save()
	#Dialogic.start("test_dialogic_timeline")

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
	generate_world_metadata()
	load_game_data()

func _on_pause_button_pressed() -> void:
	get_tree().paused = true
	pause.show()

func show_or_hide_overworld_scene(scene_path: String, show: bool) -> void:
	pass
	# to easier use with save/load:
	# if player.current_scene != overworld_map:
		# overworld.hide()
	# else:
		# overworld.show()

func load_or_generate_local_map():
	# take code from player.descend_to_local_area() here
	pass


func load_game_data() -> void:
	player.global_position = _save.player_position
	# player.current_scene = _save.player_current_scene_path
	# TODO load in player current scene the same way player.descend_to_local_area does it

func save_game() -> void:
	_save.player_position = player.global_position
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path
	_save.write_savegame()

func generate_world_metadata() -> void:
	world_tile_data.clear()
	var width = int(overworld_map.WIDTH)
	var height = int(overworld_map.HEIGHT)
	print("Creating local maps for %d tiles" % (width * height))
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			# Ensure map data is initialized
			if y >= overworld_map.map_data.size() or x >= overworld_map.map_data[y].size():
				continue
				
			var tile_data = overworld_map.map_data[y][x]
			if tile_data == null:
				continue
			
			# Skip if settlement
			if tile_data.settlement != overworld_map.Settlement.NONE or tile_data.terrain == overworld_map.Terrain.WATER:
				continue
				
			var terrain = tile_data.terrain
			var seed_val = _deterministic_seed(terrain, pos)
			var rng = RandomNumberGenerator.new()
			rng.seed = seed_val

			# Build TileMetadata Resource for non-settlement tiles
			var meta := TileMetadata.new()
			meta.coords = pos
			meta.seed = seed_val
			meta.terrain = terrain
			meta.climate = _get_climate(terrain, y)
			# Simple biome derivation from climate
			# meta.biome = meta.climate == "temperate" ? "temperate_forest" : (meta.climate == "cold" ? "boreal" : (meta.climate == "arid" ? "steppe" : "unknown"))
			meta.elevation = float(y) / float(height)
			# Suggested features
			meta.water_features = {"river": rng.randf() < 0.1, "lake": rng.randf() < 0.05, "spring": false, "marsh": false}
			meta.dungeon_entrance = {"exists": rng.randf() < 0.03, "depth_hint": 1 + (rng.randi() % 3), "theme": "ruins"}
			# meta.camp = {"exists": rng.randf() < 0.04, "owner": "", "size": (rng.randf() < 0.5 ? "small" : "medium"), "permanence": 0.25}
			meta.farm_plot = {"exists": (terrain == overworld_map.Terrain.GRASS) and (rng.randf() < 0.05), "crop": "wheat", "size": 1 + (rng.randi() % 3), "owner": ""}
			meta.feature_weights = {"lake": 0.2, "river": 0.1, "meadow": 0.6, "boulder_field": 0.3}
			meta.foliage_profile = {"tree_density": 0.35, "bush_density": 0.25, "rock_density": 0.15}
			meta.encounter_difficulty = 1 + (rng.randi() % 3)
			meta.discovered = false
			world_tile_data[pos] = meta
	print("Created local maps for %d tiles" % world_tile_data.size())

	# { "seed": 6904785133, "terrain": 1, "climate": "cold", "farm": false, "hamlet": false, "dungeon_entrance": false, "camp": false, "coords": (92, 10) }

func _get_climate(terrain: int, y: int) -> String:
	if terrain == overworld_map.Terrain.MOUNTAIN:
		return "alpine"
	# Map height is roughly 81 tiles
	if y < 15:
		return "cold"
	elif y > 65:
		return "arid"
	else:
		return "temperate"
