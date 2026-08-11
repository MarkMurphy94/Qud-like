extends Node
## The stripped-back world runs on `world_map` (scenes/alternate_mode) with no
## local areas. OverworldMap is looked up optionally for compatibility with
## older scene layouts.
@onready var world_map = get_node_or_null("world_map")
@onready var overworld_map = get_node_or_null("OverworldMap")
@onready var player: CharacterBody2D = $Player
@onready var pause: Control = $CanvasLayer/pause
## MapGenerator instance that hosts the current tile's local map.
@onready var local_scene = get_node_or_null("local_scene")
## Populates the current local map with NPCs. Lives inside local_scene.tscn so
## its NPCs share the map's lifetime.
@onready var npc_spawner = local_scene.get_node_or_null("npc_spawner") if local_scene else null
## Stands lootable containers on the cells the generator marked for them. Also
## lives inside local_scene.tscn, for the same lifetime reason.
@onready var container_spawner = local_scene.get_node_or_null("container_spawner") if local_scene else null

var _save := SaveGameResource.new()
var world_tile_data: Dictionary = {}
## Key = Vector2i tile.  Value = int seed used to generate that tile's local
## map scene. Rolled once per land tile when the world is created, then owned
## by the save file so local maps regenerate identically for a whole save.
var overworld_tile_seeds: Dictionary = {}
## Key = area identifier (scene path or "x,y").  Value = Array of item-key strings.
## Populated at runtime and persisted through save/load to prevent re-spawning.
var area_picked_up_items: Dictionary = {}
## Key = area identifier.  Value = { "cell_x,cell_y" -> container dict }.
## Only containers the player has actually looted are recorded — everything
## else re-rolls from the map seed, so an untouched chest costs nothing.
var area_container_state: Dictionary = {}
var _play_timer: float = 0.0        ## Accumulated play-time for the current session
var _current_slot: int = -1          ## Slot we last loaded / saved into (-1 = none)
## Province the player was last known to be standing in, so entering a new one
## can be announced once instead of every turn. See _announce_province_change().
var _last_province: int = -1
## Same, for the people whose land the player is walking through.
var _last_culture: int = -1
## Same, for whoever's writ runs where the player is standing.
var _last_faction: int = -1

# ═══════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# The local-map host starts empty and hidden — any content painted into the
	# scene in the editor is test data, and its collision would bleed through
	# into the overworld (tile collision ignores visibility).
	if local_scene:
		local_scene.clear_all_layers()
		local_scene.visible = false
	_spawn_message_log()
	create_or_load_save()
	TurnManager.turn_resolved.connect(_on_turn_resolved)
	# Check if the main menu requested we load a specific slot
	if MainGameState.has_meta("pending_load_slot"):
		var slot: int = MainGameState.get_meta("pending_load_slot")
		MainGameState.remove_meta("pending_load_slot")
		# Defer so the scene tree is fully set up first
		call_deferred("load_game_from_slot", slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_provinces"):
		_toggle_province_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_cultures"):
		_toggle_culture_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_factions"):
		_toggle_faction_overlay()
		get_viewport().set_input_as_handled()

## The turn log lives with the game scene rather than as an autoload so it dies
## with the run and never overlaps the main menu.
func _spawn_message_log() -> void:
	var scene: PackedScene = load("res://scenes/message_log.tscn")
	if scene == null:
		push_warning("[MainGame] message_log.tscn not found")
		return
	add_child(scene.instantiate())

func _process(delta: float) -> void:
	_play_timer += delta

# ═══════════════════════════════════════════════════════════════════════
#  PROVINCES, CULTURES AND FACTIONS
# ═══════════════════════════════════════════════════════════════════════

## The overworld's political map, or null in scene layouts that have none.
func province_map():
	return world_map.get_node_or_null("provinces") if world_map else null


## The overworld's map of peoples, or null in scene layouts that have none.
func culture_map():
	return world_map.get_node_or_null("cultures") if world_map else null


## The overworld's map of organisations, or null in scene layouts that have none.
func faction_map():
	return world_map.get_node_or_null("factions") if world_map else null


func _toggle_province_overlay() -> void:
	var provinces = province_map()
	if provinces == null:
		return
	var shown := bool(provinces.toggle_overlay())
	TurnManager.log_message("Political map %s." % ("shown" if shown else "hidden"), "info")


func _toggle_culture_overlay() -> void:
	var cultures = culture_map()
	if cultures == null:
		return
	var shown := bool(cultures.toggle_overlay())
	TurnManager.log_message("Culture map %s." % ("shown" if shown else "hidden"), "info")


func _toggle_faction_overlay() -> void:
	var factions = faction_map()
	if factions == null:
		return
	var shown := bool(factions.toggle_overlay())
	TurnManager.log_message("Faction map %s." % ("shown" if shown else "hidden"), "info")


## Name the territory the player walks into. Driven off resolved turns rather
## than a per-frame position check, because that is the only time the player's
## tile can have changed.
func _on_turn_resolved(_world_time: int) -> void:
	_announce_province_change()
	_announce_culture_change()
	_announce_faction_change()


func _announce_province_change() -> void:
	var provinces = province_map()
	if provinces == null or player == null or player.in_local_area:
		return
	var current := int(provinces.province_at(world_map.world_to_tile(player.global_position)))
	if current == _last_province:
		return
	_last_province = current
	var province = provinces.get_province(current)
	if province == null:
		return
	var holder: String = "" if province.ruling_faction == "unclaimed" else " (%s)" % province.ruling_faction
	TurnManager.log_message("You enter %s%s." % [province.display_name, holder], "info")


## Name the people whose land the player crosses into. Separate from the
## province announcement because the two borders deliberately do not line up.
func _announce_culture_change() -> void:
	var cultures = culture_map()
	if cultures == null or player == null or player.in_local_area:
		return
	var current := int(cultures.culture_at(world_map.world_to_tile(player.global_position)))
	if current == _last_culture:
		return
	_last_culture = current
	var culture = cultures.get_culture(current)
	if culture == null:
		return
	TurnManager.log_message("This is %s country." % culture.display_name, "info")


## Name whoever's writ runs here. Ruled land names its holder and the liege
## behind them; land that is only influenced says so in weaker words, because
## that difference is the whole point of the faction map.
func _announce_faction_change() -> void:
	var factions = faction_map()
	if factions == null or player == null or player.in_local_area:
		return
	var tile: Vector2i = world_map.world_to_tile(player.global_position)
	var current := int(factions.faction_at(tile))
	if current == _last_faction:
		return
	_last_faction = current
	var faction = factions.get_faction(current)
	if faction == null:
		return
	if int(factions.ruler_at(tile)) != current:
		TurnManager.log_message("%s hold sway here." % faction.display_name, "info")
		return
	var liege = factions.liege_of(faction.faction_id)
	var sworn: String = "" if liege == null else ", sworn to %s" % liege.display_name
	var failed: String = " \u2014 or claims to" if faction.causes_failed_state() else ""
	TurnManager.log_message("%s rules here%s%s." % [faction.display_name, sworn, failed], "info")

# ═══════════════════════════════════════════════════════════════════════
#  DETERMINISTIC SEED
# ═══════════════════════════════════════════════════════════════════════

func _deterministic_seed(settlement_type: int, pos: Vector2i) -> int:
	var v := int(settlement_type) * 83492791 ^ (pos.x * 73856093) ^ (pos.y * 19349663)
	return abs(v) # stable across runs

func create_or_load_save():
	# On a fresh "New Game" there is no slot yet — just initialise defaults.
	# When the player explicitly picks "Load Game" from the menu / pause screen
	# load_game_slot(slot) is called instead.
	_save = SaveGameResource.new()
	_save.player_overworld_position = player.global_position
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path
	area_picked_up_items.clear()  # fresh world — nothing picked up yet
	area_container_state.clear()  # …and nothing looted
	generate_world_metadata()
	generate_overworld_tile_seeds()

## Roll a permanent local-map seed for every land tile of the overworld.
## Called once on "New Game"; on "Load Game" the seeds come back from the save
## file instead. Existing entries are never re-rolled, so calling this on a
## loaded world only fills in tiles that gained land since the save was made.
func generate_overworld_tile_seeds() -> void:
	if world_map == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bounds: Rect2i = world_map.bounds
	var added := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if overworld_tile_seeds.has(tile):
				continue
			if not world_map.is_land(tile):
				continue
			overworld_tile_seeds[tile] = rng.randi()
			added += 1
	if added > 0:
		print("[MainGame] Rolled local-map seeds for %d land tiles (%d total)"
			% [added, overworld_tile_seeds.size()])

## The permanent local-map seed for an overworld tile, or -1 for water /
## off-map tiles that have no local map.
func get_tile_seed(tile: Vector2i) -> int:
	return overworld_tile_seeds.get(tile, -1)

func _terrain_for_tile(tile: Vector2i) -> int:
	if local_scene == null:
		return 0
	if world_map and world_map.mountains.get_cell_source_id(tile) != -1:
		return local_scene.OverworldTile.MOUNTAIN
	return local_scene.OverworldTile.GRASS

func _tile_has_settlement(tile: Vector2i) -> bool:
	if world_map == null:
		return false
	if world_map.has_method("has_location"):
		return bool(world_map.has_location(tile))
	var locations_layer: TileMapLayer = world_map.get_node_or_null("locations")
	return locations_layer != null and locations_layer.get_cell_source_id(tile) != -1

func _tile_is_forest(tile: Vector2i) -> bool:
	if world_map == null:
		return false
	var forests_layer: TileMapLayer = world_map.get_node_or_null("forests")
	return forests_layer != null and forests_layer.get_cell_source_id(tile) != -1

func _build_local_map_metadata(tile: Vector2i, seed_value: int, base_metadata: Dictionary = {}) -> Dictionary:
	var meta: Dictionary = base_metadata.duplicate(true)
	var terrain: int = _terrain_for_tile(tile)
	meta["coords"] = tile
	meta["seed"] = seed_value
	meta["terrain"] = terrain
	meta["biome"] = world_map.biome_at(tile) if world_map else "temperate"

	var overworld_data: Dictionary = {}
	var existing_overworld = meta.get("overworld", {})
	if existing_overworld is Dictionary:
		overworld_data = (existing_overworld as Dictionary).duplicate(true)
	overworld_data["has_settlement"] = _tile_has_settlement(tile)
	overworld_data["is_forest"] = _tile_is_forest(tile)
	overworld_data["terrain"] = terrain
	overworld_data["biome"] = meta["biome"]
	meta["overworld"] = overworld_data

	# Resolve the tile's people here, once, rather than handing the culture map
	# down to every system that names something.
	var cultures = culture_map()
	var culture = cultures.culture_for_tile(tile) if cultures else null
	meta["culture_id"] = culture.culture_id if culture else ""
	meta["name_profiles"] = {
		"place": Culture.profile_for(culture, "place"),
		"npc": Culture.profile_for(culture, "npc"),
	}

	# Keep top-level aliases for backward-compatible readers.
	meta["has_settlement"] = overworld_data["has_settlement"]
	meta["is_forest"] = overworld_data["is_forest"]
	return meta

# ═════════════════════════════════════════════════════════════════════
#  LOCAL MAP ENTER / EXIT
# ═════════════════════════════════════════════════════════════════════

## Descend into the procedurally generated local map for the overworld tile
## the player is standing on. No-op for tiles without a seed (water/off-map).
func enter_local_map() -> void:
	if local_scene == null or world_map == null or player.in_local_area:
		return
	var tile: Vector2i = player.get_current_tile()
	var map_seed := get_tile_seed(tile)
	if map_seed == -1:
		print("[MainGame] No local map for tile %s" % tile)
		return

	# Remember where to resurface.
	player.overworld_tile = tile
	player.overworld_tile_pos = player.global_position

	var meta := _build_local_map_metadata(tile, map_seed)
	local_scene.generate_local_map(meta)
	_apply_area_pickup_records(_area_key_from_tile(tile), local_scene)

	world_map.visible = false
	local_scene.visible = true
	player.in_local_area = true
	player.world_map = local_scene
	player.cancel_navigation()

	# Freshly painted tile collision registers on the next physics step — wait
	# for it so spawn placement and the nav grid see the real geometry.
	await get_tree().physics_frame
	var centre := Vector2i(local_scene.WIDTH / 2, local_scene.HEIGHT / 2)
	var spawn: Vector2i = local_scene.nearest_walkable(centre)
	player.global_position = local_scene.tile_to_world(spawn)
	player.snap_to_grid()
	player.update_camera_limits()
	player.rebuild_nav_grid()
	if npc_spawner:
		npc_spawner.populate_local_map(meta)
	if container_spawner:
		container_spawner.populate_local_map(1, _container_state_for_tile(tile))
	print("[MainGame] Entered local map for tile %s (seed %d)" % [tile, map_seed])

## Return to the overworld tile the player descended from.
func exit_local_map() -> void:
	if world_map == null or not player.in_local_area:
		return
	if npc_spawner:
		# NPCs belong to the map that is being torn down; leaving them alive would
		# strand them under a hidden local_scene.
		npc_spawner.clear()
	# Harvest looted containers before the spawner drops them, or the record of
	# what the player emptied dies with the map.
	_store_container_state(player.overworld_tile)
	if container_spawner:
		container_spawner.clear()
	if local_scene:
		# Wiping the layers also drops their collision, which would otherwise
		# keep blocking overworld tiles while the local map sits hidden.
		local_scene.clear_all_layers()
		local_scene.visible = false
	world_map.visible = true
	player.in_local_area = false
	player.world_map = world_map
	player.cancel_navigation()
	player.global_position = player.overworld_tile_pos

	await get_tree().physics_frame
	player.snap_to_grid()
	player.update_camera_limits()
	player.rebuild_nav_grid()
	print("[MainGame] Returned to overworld tile %s" % player.overworld_tile)

## First-visit hook for procedural wilderness tiles. Rolls the tile's
## permanent seed on the first descent (replacing the derived placeholder from
## generate_world_metadata) and stamps discovery state. Rolled seeds are saved
## with discovered tiles and restored on load, so an already-visited area
## survives future changes to worldgen formulas or the overworld map.
func prepare_tile_visit(tile: Vector2i) -> TileMetadata:
	var meta: TileMetadata = world_tile_data.get(tile)
	if meta == null:
		return null
	var now := int(Time.get_unix_time_from_system())
	if not meta.discovered:
		meta.seed = randi()
		meta.discovered = true
		meta.generated_at = now
	meta.last_visited = now
	return meta

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
	# ── Province ownership ─────────────────────────────────────
	# Only who holds what: the borders themselves are regrown on load.
	var provinces = province_map()
	if provinces:
		_save.province_ownership = provinces.ownership_dict()
	# ── Overworld tile seeds ─────────────────────────────────
	_save.overworld_tile_seeds.clear()
	for tile: Vector2i in overworld_tile_seeds:
		_save.overworld_tile_seeds["%d,%d" % [tile.x, tile.y]] = overworld_tile_seeds[tile]
	# ── Item pickup records ─────────────────────────────────────
	_save.area_picked_up_items = area_picked_up_items.duplicate(true)
	# ── Container records ───────────────────────────────────────
	# The live map's containers are only in memory until now.
	if player.in_local_area:
		_store_container_state(player.overworld_tile)
	_save.area_container_state = area_container_state.duplicate(true)

	# ── Local-area bookmark (so we can re-enter on load) ───────
	if player.in_local_area and local_scene:
		_save.local_area_settlement_path = ""
		var meta: TileMetadata = world_tile_data.get(player.overworld_tile)
		if meta:
			_save.local_area_metadata = _build_local_map_metadata(
				player.overworld_tile,
				get_tile_seed(player.overworld_tile),
				meta.to_dict())
		else:
			_save.local_area_metadata = _build_local_map_metadata(
				player.overworld_tile,
				get_tile_seed(player.overworld_tile))
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

	# ── Province ownership ─────────────────────────────────────
	# The provinces were already grown from the map when world_map entered the
	# tree; this only hands them back to their owners.
	var provinces = province_map()
	if provinces and not _save.province_ownership.is_empty():
		provinces.apply_ownership(_save.province_ownership)
	_last_province = -1

	# ── Item pickup records ─────────────────────────────────────
	area_picked_up_items = _save.area_picked_up_items.duplicate(true)
	area_container_state = _save.area_container_state.duplicate(true)
	# ── Overworld tile seeds ─────────────────────────────────
	overworld_tile_seeds.clear()
	for key_str in _save.overworld_tile_seeds:
		var parts := (key_str as String).split(",")
		if parts.size() == 2:
			overworld_tile_seeds[Vector2i(int(parts[0]), int(parts[1]))] = int(_save.overworld_tile_seeds[key_str])
	# Older saves (or map edits) may leave land tiles unseeded — top them up
	# without touching the seeds that were restored above.
	generate_overworld_tile_seeds()
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
				# Restore the seed rolled on first visit so already-explored
				# areas regenerate identically in this save, even if worldgen
				# formulas or the overworld map change between game versions.
				meta.seed = saved_meta.get("seed", meta.seed)
				meta.generated_at = saved_meta.get("generated_at", meta.generated_at)

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
	if _save.player_in_local_area and local_scene and world_map:
		# Put the player on the overworld tile first, then descend
		player.global_position = _save.player_overworld_position
		player.overworld_tile = _save.player_overworld_tile
		player.overworld_tile_pos = _save.player_overworld_position

		# Re-enter the local map from saved metadata (or synthesize minimal data).
		var meta_dict: Dictionary = _save.local_area_metadata.duplicate(true)
		if meta_dict.is_empty():
			meta_dict = _build_local_map_metadata(
				player.overworld_tile,
				get_tile_seed(player.overworld_tile))
		else:
			meta_dict = _build_local_map_metadata(
				player.overworld_tile,
				int(meta_dict.get("seed", get_tile_seed(player.overworld_tile))),
				meta_dict)

		local_scene.generate_local_map(meta_dict)
		_apply_area_pickup_records(_area_key_from_tile(player.overworld_tile), local_scene)
		world_map.visible = false
		local_scene.visible = true
		await get_tree().physics_frame
		player.map_rect = local_scene.bounds
		player.global_position = _save.player_local_position
		player.in_local_area = true
		player.world_map = local_scene
		player.snap_to_grid()
		player.rebuild_nav_grid()
		player.update_camera_limits()
		if npc_spawner:
			npc_spawner.populate_local_map(meta_dict)
		if container_spawner:
			container_spawner.populate_local_map(1, _container_state_for_tile(player.overworld_tile))
	else:
		# Overworld. A save taken inside a local area lands the player back on
		# the overworld tile they descended from.
		if player.in_local_area:
			if npc_spawner:
				npc_spawner.clear()
			if container_spawner:
				container_spawner.clear()
			if local_scene:
				local_scene.clear_all_layers()
				local_scene.visible = false
			if world_map:
				world_map.visible = true
			player.in_local_area = false
			player.world_map = world_map
		player.global_position = _save.player_overworld_position
		player.snap_to_grid()
		player.rebuild_nav_grid()
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
	# Per-tile wilderness metadata describes local maps, which the stripped-back
	# world does not generate yet. Nothing to build without the old OverworldMap.
	if overworld_map == null:
		return
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
			meta.foliage_profile = _get_foliage_profile(terrain, meta.climate, rng)
			meta.encounter_difficulty = 1 + (rng.randi() % 3)
			meta.discovered = false
			world_tile_data[pos] = meta
	print("Created local maps for %d tiles" % world_tile_data.size())

	# Second pass: assign road exits so that adjacent tiles always have matching
	# exits (e.g. tile A EAST ↔ tile B WEST).  Each shared edge is evaluated once
	# using a deterministic hash of the "left/upper" tile's position so the result
	# is the same no matter which side triggers the query.
	_assign_road_exits()

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

## Returns a foliage_profile Dictionary appropriate for the given terrain and climate.
## Values are kept deliberately low so that open plains feel open.
func _get_foliage_profile(terrain: int, climate: String, tile_rng: RandomNumberGenerator) -> Dictionary:
	match terrain:
		overworld_map.Terrain.GRASS:
			match climate:
				"cold":
					return {
						"tree_density": tile_rng.randf_range(0.02, 0.10),
						"bush_density": tile_rng.randf_range(0.02, 0.06),
						"rock_density": tile_rng.randf_range(0.03, 0.07)
					}
				"arid":
					return {
						"tree_density": tile_rng.randf_range(0.0, 0.04),
						"bush_density": tile_rng.randf_range(0.02, 0.05),
						"rock_density": tile_rng.randf_range(0.06, 0.14)
					}
				_: # temperate
					return {
						"tree_density": tile_rng.randf_range(0.03, 0.15),
						"bush_density": tile_rng.randf_range(0.04, 0.10),
						"rock_density": tile_rng.randf_range(0.02, 0.05)
					}
		overworld_map.Terrain.MOUNTAIN:
			return {
				"tree_density": tile_rng.randf_range(0.0, 0.06),
				"bush_density": tile_rng.randf_range(0.01, 0.04),
				"rock_density": tile_rng.randf_range(0.18, 0.30)
			}
		_:
			return {"tree_density": 0.0, "bush_density": 0.0, "rock_density": 0.0}

# ═══════════════════════════════════════════════════════════════════════
#  ROAD EXIT ASSIGNMENT
# ═══════════════════════════════════════════════════════════════════════

## Probability (0–100) that a shared edge between two non-settlement tiles
## gets a road.  Roughly 18 % of edges, tunable here.
const ROAD_EDGE_PROBABILITY := 18

## Deterministic hash for a single shared edge.
## 'canonical' is always the left (east-check) or upper (south-check) tile.
## 'axis' 0 = east edge, 1 = south edge.
func _edge_has_road(canonical: Vector2i, axis: int) -> bool:
	var h: int = abs(canonical.x * 73856093 ^ canonical.y * 19349663 ^ axis * 16777619)
	return (h % 100) < ROAD_EDGE_PROBABILITY

## Iterate all generated tiles and assign their road_exits bitmask so that
## every pair of adjacent tiles has matching exits on their shared edge.
func _assign_road_exits() -> void:
	for pos: Vector2i in world_tile_data:
		var meta: TileMetadata = world_tile_data[pos]
		var exits := 0

		# East edge — canonical tile is the current one (left of the pair)
		var east := pos + Vector2i(1, 0)
		if world_tile_data.has(east) and _edge_has_road(pos, 0):
			exits |= MapConfig.RoadExit.EAST

		# South edge — canonical tile is the current one (upper of the pair)
		var south := pos + Vector2i(0, 1)
		if world_tile_data.has(south) and _edge_has_road(pos, 1):
			exits |= MapConfig.RoadExit.SOUTH

		# West edge — canonical tile is the neighbour to the left
		var west := pos + Vector2i(-1, 0)
		if world_tile_data.has(west) and _edge_has_road(west, 0):
			exits |= MapConfig.RoadExit.WEST

		# North edge — canonical tile is the neighbour above
		var north := pos + Vector2i(0, -1)
		if world_tile_data.has(north) and _edge_has_road(north, 1):
			exits |= MapConfig.RoadExit.NORTH

		meta.road_exits = exits

# ═══════════════════════════════════════════════════════════════════════
#  WORLD ITEM PICKUP TRACKING
# ═══════════════════════════════════════════════════════════════════════

func _area_key_from_tile(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]

## Saved state for the containers of one overworld tile, or {} if the player
## has never looted anything there.
func _container_state_for_tile(tile: Vector2i) -> Dictionary:
	return area_container_state.get(_area_key_from_tile(tile), {})

## Fold the live map's looted containers back into the persistent record.
## Called before the containers are freed, since their state only exists on
## the nodes themselves.
func _store_container_state(tile: Vector2i) -> void:
	if container_spawner == null:
		return
	var dirty: Dictionary = container_spawner.get_dirty_state()
	if dirty.is_empty():
		return
	var area_key := _area_key_from_tile(tile)
	var existing: Dictionary = area_container_state.get(area_key, {})
	existing.merge(dirty, true)
	area_container_state[area_key] = existing

## Connects WorldItem pickup signals and removes already-collected items for
## a generated local area.
func _apply_area_pickup_records(area_key: String, area_root: Node) -> void:
	if area_key == "" or not is_instance_valid(area_root):
		return

	var recorded: Array = area_picked_up_items.get(area_key, [])

	for wi: WorldItem in area_root.find_children("*", "WorldItem", true, false):
		if not is_instance_valid(wi) or not wi.item_resource:
			continue

		var key := _make_item_key(wi.item_resource, wi.global_position)
		if key in recorded:
			wi.queue_free()
		else:
			wi.picked_up.connect(
				func(_item: Item, _qty: int, pos: Vector2) -> void:
					_record_item_pickup(_item, pos, area_key)
			)

## Appends an item key to the pickup record for the given area.
func _record_item_pickup(item: Item, pos: Vector2, area_key: String) -> void:
	var key := _make_item_key(item, pos)
	if not area_picked_up_items.has(area_key):
		area_picked_up_items[area_key] = []
	if key not in area_picked_up_items[area_key]:
		area_picked_up_items[area_key].append(key)

## Builds a stable string key for a WorldItem from its item id and tile position.
## Format: "item_id@tile_x,tile_y"  (tile coords = world pixels / 16)
func _make_item_key(item: Item, pos: Vector2) -> String:
	var item_id: String
	if item.id != "":
		item_id = item.id
	elif item.resource_path != "":
		item_id = item.resource_path.get_file().get_basename()
	else:
		item_id = item.display_name.to_lower().replace(" ", "_")
	var tile_x := int(round(pos.x / 16.0))
	var tile_y := int(round(pos.y / 16.0))
	return "%s@%d,%d" % [item_id, tile_x, tile_y]
