extends Node
@onready var overworld_map = $OverworldMap
@onready var player: CharacterBody2D = $Player
@onready var pause: Control = $CanvasLayer/pause
@onready var area_container: Node2D = $AreaContainer

var _save := SaveGameResource.new()
var world_tile_data: Dictionary = {}
var _play_timer: float = 0.0        ## Accumulated play-time for the current session
var _current_slot: int = -1          ## Slot we last loaded / saved into (-1 = none)

# ═══════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════

func _ready() -> void:
	create_or_load_save()
	# Check if the main menu requested we load a specific slot
	if MainGameState.has_meta("pending_load_slot"):
		var slot: int = MainGameState.get_meta("pending_load_slot")
		MainGameState.remove_meta("pending_load_slot")
		# Defer so the scene tree is fully set up first
		call_deferred("load_game_from_slot", slot)

func _process(delta: float) -> void:
	_play_timer += delta

# ═══════════════════════════════════════════════════════════════════════
#  DETERMINISTIC SEED
# ═══════════════════════════════════════════════════════════════════════

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
	# On a fresh "New Game" there is no slot yet — just initialise defaults.
	# When the player explicitly picks "Load Game" from the menu / pause screen
	# load_game_slot(slot) is called instead.
	_save = SaveGameResource.new()
	_save.player_overworld_position = player.global_position
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path
	generate_world_metadata()

func show_or_hide_overworld_scene(_scene_path: String, _show: bool) -> void:
	pass

func load_or_generate_local_map():
	pass

# ═══════════════════════════════════════════════════════════════════════
#  SAVE / LOAD — MULTI-SLOT
# ═══════════════════════════════════════════════════════════════════════

## Gather *all* game state into a SaveGameResource and write it to the given slot.
func save_game_to_slot(slot: int, slot_name: String = "") -> void:
	_save.slot_index = slot
	if slot_name != "":
		_save.slot_name = slot_name
	elif _save.slot_name == "":
		_save.slot_name = "Save %d" % (slot + 1)

	# ── Player position ────────────────────────────────────────
	_save.player_overworld_position = player.overworld_tile_pos if player.in_local_area else player.global_position
	_save.player_in_local_area = player.in_local_area
	_save.player_overworld_tile = player.overworld_tile
	if player.in_local_area:
		_save.player_local_position = player.global_position
	else:
		_save.player_local_position = Vector2.ZERO
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path

	# ── Player stats ───────────────────────────────────────────
	_save.player_health = player.current_health
	_save.player_max_health = player.max_health
	_save.player_mana = player.current_mana
	_save.player_max_mana = player.max_mana
	_save.player_stamina = player.current_stamina
	_save.player_max_stamina = player.max_stamina
	_save.player_gold = player.gold

	# ── Inventory ──────────────────────────────────────────────
	if player.inventory:
		_save.inventory_data = player.inventory.to_dict()

	# ── Spells ─────────────────────────────────────────────────
	var paths := PackedStringArray()
	for spell in player.learned_spells:
		if spell.resource_path != "":
			paths.append(spell.resource_path)
	_save.learned_spell_paths = paths

	# ── World tile metadata (only discovered / visited tiles) ──
	_save.world_tile_data.clear()
	for pos_key in world_tile_data:
		var meta: TileMetadata = world_tile_data[pos_key]
		if meta.discovered:
			var key_str := "%d,%d" % [pos_key.x, pos_key.y]
			_save.world_tile_data[key_str] = meta.to_dict()

	# ── Settlements ────────────────────────────────────────────
	_save.settlements_data = MainGameState.settlements.duplicate(true)

	# ── Local-area bookmark (so we can re-enter on load) ───────
	if player.in_local_area and area_container.current_area:
		var settlement_path = overworld_map.settlement_at_tile(player.overworld_tile)
		if settlement_path != "":
			_save.local_area_settlement_path = settlement_path
			_save.local_area_metadata = {}
		elif world_tile_data.has(player.overworld_tile):
			_save.local_area_settlement_path = ""
			_save.local_area_metadata = (world_tile_data[player.overworld_tile] as TileMetadata).to_dict()
	else:
		_save.local_area_settlement_path = ""
		_save.local_area_metadata = {}

	# ── Play time ──────────────────────────────────────────────
	_save.play_time_seconds += _play_timer
	_play_timer = 0.0

	_save.write_to_slot(slot)
	_current_slot = slot
	print("[SaveSystem] Saved to slot %d  (%s)" % [slot, _save.slot_name])

## Load all state from a specific slot and apply it.
func load_game_from_slot(slot: int) -> bool:
	var loaded := SaveGameResource.load_slot(slot)
	if loaded == null:
		push_warning("[SaveSystem] Slot %d does not exist." % slot)
		return false

	_save = loaded
	_current_slot = slot
	_play_timer = 0.0

	# ── Settlements ────────────────────────────────────────────
	if not _save.settlements_data.is_empty():
		MainGameState.settlements = _save.settlements_data.duplicate(true)

	# ── World metadata ─────────────────────────────────────────
	generate_world_metadata()
	# Overlay saved discovered-tile state on top of the freshly-generated metadata
	for key_str in _save.world_tile_data:
		var parts := (key_str as String).split(",")
		if parts.size() == 2:
			var pos := Vector2i(int(parts[0]), int(parts[1]))
			if world_tile_data.has(pos):
				var saved_meta: Dictionary = _save.world_tile_data[key_str]
				var meta: TileMetadata = world_tile_data[pos]
				meta.discovered = saved_meta.get("discovered", false)
				meta.last_visited = saved_meta.get("last_visited", 0)
				meta.dynamic_state = saved_meta.get("dynamic_state", meta.dynamic_state)
				meta.flags = saved_meta.get("flags", meta.flags)

	# ── Player stats ───────────────────────────────────────────
	player.current_health = _save.player_health
	player.max_health = _save.player_max_health
	player.current_mana = _save.player_mana
	player.max_mana = _save.player_max_mana
	player.current_stamina = _save.player_stamina
	player.max_stamina = _save.player_max_stamina
	player.gold = _save.player_gold

	player.hud.update_hp(player.current_health, player.max_health)
	player.hud.update_mp(player.current_mana, player.max_mana)
	player.hud.update_sp(player.current_stamina, player.max_stamina)

	# ── Inventory ──────────────────────────────────────────────
	if not _save.inventory_data.is_empty() and player.inventory:
		player.inventory.from_dict(_save.inventory_data)

	# ── Spells ─────────────────────────────────────────────────
	player.learned_spells.clear()
	for path in _save.learned_spell_paths:
		var spell: Spell = load(path) as Spell
		if spell:
			player.learned_spells.append(spell)

	# ── Position & local-area re-entry ─────────────────────────
	if _save.player_in_local_area:
		# Put the player on the overworld tile first, then descend
		player.global_position = _save.player_overworld_position
		player.overworld_tile = _save.player_overworld_tile
		player.overworld_tile_pos = _save.player_overworld_position
		# Re-enter the local area
		if _save.local_area_settlement_path != "":
			area_container.set_settlement_scene(_save.local_area_settlement_path)
		elif not _save.local_area_metadata.is_empty():
			var meta := TileMetadata.from_dict(_save.local_area_metadata)
			area_container.set_local_area(meta)
		await get_tree().process_frame
		player.map_rect = area_container.current_area.tilemaps["GROUND"].get_used_rect()
		player.global_position = _save.player_local_position
		overworld_map.hide()
		player.in_local_area = true
		player.update_camera_limits()
	else:
		# Overworld
		if player.in_local_area:
			area_container.clear_local_area_scene()
			overworld_map.show()
			player.in_local_area = false
		player.global_position = _save.player_overworld_position
		player.update_camera_limits()

	print("[SaveSystem] Loaded slot %d  (%s)" % [slot, _save.slot_name])
	return true

## Legacy wrappers (called from old pause.gd flow) ─────────────────────
func save_game() -> void:
	if _current_slot < 0:
		_current_slot = SaveGameResource.next_free_slot()
		if _current_slot < 0:
			_current_slot = 0 # overwrite first slot as last resort
	save_game_to_slot(_current_slot)

func load_game() -> void:
	var slot := SaveGameResource.most_recent_slot()
	if slot >= 0:
		load_game_from_slot(slot)

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
