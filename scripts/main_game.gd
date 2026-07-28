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

var _save := SaveGameResource.new()
var world_tile_data: Dictionary = {}
## Key = Vector2i tile.  Value = int seed used to generate that tile's local
## map scene. Rolled once per land tile when the world is created, then owned
## by the save file so local maps regenerate identically for a whole save.
var overworld_tile_seeds: Dictionary = {}
## Key = area identifier (scene path or "x,y").  Value = Array of item-key strings.
## Populated at runtime and persisted through save/load to prevent re-spawning.
var area_picked_up_items: Dictionary = {}
var _play_timer: float = 0.0        ## Accumulated play-time for the current session
var _current_slot: int = -1          ## Slot we last loaded / saved into (-1 = none)

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

func create_or_load_save():
	# On a fresh "New Game" there is no slot yet — just initialise defaults.
	# When the player explicitly picks "Load Game" from the menu / pause screen
	# load_game_slot(slot) is called instead.
	_save = SaveGameResource.new()
	_save.player_overworld_position = player.global_position
	_save.player_current_scene_path = get_tree().current_scene.scene_file_path
	area_picked_up_items.clear()  # fresh world — nothing picked up yet
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

	var terrain: int = local_scene.OverworldTile.GRASS
	if world_map.mountains.get_cell_source_id(tile) != -1:
		terrain = local_scene.OverworldTile.MOUNTAIN

	local_scene.generate_local_map({
		"coords": tile,
		"seed": map_seed,
		"terrain": terrain,
		"biome": world_map.biome_at(tile),
	})
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
	print("[MainGame] Entered local map for tile %s (seed %d)" % [tile, map_seed])

## Return to the overworld tile the player descended from.
func exit_local_map() -> void:
	if world_map == null or not player.in_local_area:
		return
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
	# ── Overworld tile seeds ─────────────────────────────────
	_save.overworld_tile_seeds.clear()
	for tile: Vector2i in overworld_tile_seeds:
		_save.overworld_tile_seeds["%d,%d" % [tile.x, tile.y]] = overworld_tile_seeds[tile]
	# ── Item pickup records ─────────────────────────────────────
	_save.area_picked_up_items = area_picked_up_items.duplicate(true)

	# ── Local-area bookmark (so we can re-enter on load) ───────
	if player.in_local_area and local_scene:
		_save.local_area_settlement_path = ""
		var meta: TileMetadata = world_tile_data.get(player.overworld_tile)
		if meta:
			_save.local_area_metadata = meta.to_dict()
		else:
			var terrain: int = local_scene.OverworldTile.GRASS
			if world_map and world_map.mountains.get_cell_source_id(player.overworld_tile) != -1:
				terrain = local_scene.OverworldTile.MOUNTAIN
			_save.local_area_metadata = {
				"coords": player.overworld_tile,
				"seed": get_tile_seed(player.overworld_tile),
				"terrain": terrain,
				"biome": world_map.biome_at(player.overworld_tile) if world_map else "temperate",
			}
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

	# ── Item pickup records ─────────────────────────────────────
	area_picked_up_items = _save.area_picked_up_items.duplicate(true)
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
			meta_dict = {
				"coords": player.overworld_tile,
				"seed": get_tile_seed(player.overworld_tile),
				"terrain": local_scene.OverworldTile.GRASS,
				"biome": world_map.biome_at(player.overworld_tile),
			}
			if world_map.mountains.get_cell_source_id(player.overworld_tile) != -1:
				meta_dict["terrain"] = local_scene.OverworldTile.MOUNTAIN

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
	else:
		# Overworld. A save taken inside a local area lands the player back on
		# the overworld tile they descended from.
		if player.in_local_area:
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
