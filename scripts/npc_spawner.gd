extends Node
class_name NPCSpawner

@export var npc_scene: PackedScene = preload("res://scenes/npc.tscn")

## Set by AreaContainer when loading a settlement scene.
var settlement_data: MapConfig = null
## Set by AreaContainer when loading a wilderness / procedural area.
var wilderness_metadata: TileMetadata = null

var spawned_npcs: Array = []
var rng := RandomNumberGenerator.new()

# Pixel bounds of the local map (LocationGenerator.WIDTH/HEIGHT * TILE_SIZE).
const MAP_PIXELS_X: int = 80 * 16
const MAP_PIXELS_Y: int = 80 * 16
# Margin so NPCs don't spawn right on the edge.
const SPAWN_MARGIN: int = 32

func _ready():
	pass

func clear():
	for n in spawned_npcs:
		if is_instance_valid(n):
			n.queue_free()
			n.remove_from_group("NPCs")
	spawned_npcs.clear()

# ─── Settlement spawning ───────────────────────────────────────────────────────

func spawn_settlement_npcs() -> void:
	if not settlement_data:
		push_warning("NPCSpawner: no settlement_data set")
		return
	clear()

	var settlement_entry := _find_settlement_entry()
	if settlement_entry.is_empty():
		push_warning("NPCSpawner: no MainGameState entry for '%s' — falling back to building_density counts" % settlement_data.map_name)

	# Use the entry seed if available, otherwise fall back to the MapConfig SEED.
	if not settlement_entry.is_empty():
		_assign_seed(settlement_entry)
	elif settlement_data.SEED != 0:
		rng.seed = settlement_data.SEED
	else:
		rng.randomize()

	var counts_map: Dictionary = MainGameState.settlement_npc_counts.get(int(settlement_data.building_density), {})

	# Building positions are preferred but optional — NPCs fall back to random
	# positions within the map bounds if none are available.
	var building_positions := _extract_building_positions(settlement_data.buildings)
	var homes := building_positions.duplicate()
	if not homes.is_empty():
		homes.shuffle()
	var home_index := 0

	for npc_type: MainGameState.NpcType in counts_map.keys():
		var target_count: int = counts_map[npc_type]
		for i in target_count:
			var world_pos: Vector2
			if not homes.is_empty():
				var home_tile: Vector2i = homes[home_index % homes.size()]
				home_index += 1
				world_pos = _tile_to_world(home_tile)
			else:
				world_pos = Vector2(
					rng.randi_range(SPAWN_MARGIN, MAP_PIXELS_X - SPAWN_MARGIN),
					rng.randi_range(SPAWN_MARGIN, MAP_PIXELS_Y - SPAWN_MARGIN)
				)
			var npc := _spawn_npc(npc_type, world_pos)
			npc.set_locations(world_pos)
			npc.npc_id = "%s_%s_%d" % [settlement_data.map_name, str(npc_type), i]
			spawned_npcs.append(npc)

## Looks up the settlement entry in MainGameState by map_name first,
## then by overworld_tile key (make_settlement_key), so both hand-crafted
## and dynamically-generated settlements are found.
func _find_settlement_entry() -> Dictionary:
	if not settlement_data:
		return {}
	# 1. Direct name lookup (covers hardcoded entries like "town_1")
	var map_name := settlement_data.map_name
	if MainGameState.settlements.has(map_name):
		return MainGameState.settlements[map_name]
	# 2. Tile-based key lookup (covers dynamically-created settlements)
	if settlement_data.overworld_tile != Vector2i.ZERO:
		for mtype in MapConfig.MapType.values():
			var key := MainGameState.make_settlement_key(mtype, settlement_data.overworld_tile)
			if MainGameState.settlements.has(key):
				return MainGameState.settlements[key]
	return {}

# ─── Wilderness spawning ───────────────────────────────────────────────────────

## Spawns wildlife/monsters for a procedural area.
## Count is auto-derived from encounter_difficulty in wilderness_metadata if not
## specified explicitly (pass a non-negative value to override).
func spawn_wilderness_npcs(count: int = -1) -> void:
	clear()
	if not npc_scene:
		return

	var difficulty: int = 1
	if wilderness_metadata:
		difficulty = wilderness_metadata.encounter_difficulty
		rng.seed = wilderness_metadata.seed

	# Derive count from difficulty if not provided: 2–8 creatures.
	if count < 0:
		count = clamp(2 + (difficulty - 1) * 2, 2, 8)

	for _i in count:
		var npc_type := _wilderness_npc_type()
		var pos := Vector2(
			rng.randi_range(SPAWN_MARGIN, MAP_PIXELS_X - SPAWN_MARGIN),
			rng.randi_range(SPAWN_MARGIN, MAP_PIXELS_Y - SPAWN_MARGIN)
		)
		var npc := _spawn_npc(npc_type, pos)
		npc.set_locations(pos)
		spawned_npcs.append(npc)

## Determines the NPC type for a wilderness spawn.
## Uses wildlife.common from wilderness_metadata when populated;
## defaults to ANIMAL.
func _wilderness_npc_type() -> MainGameState.NpcType:
	if wilderness_metadata:
		var common: Array = wilderness_metadata.wildlife.get("common", [])
		if not common.is_empty():
			const TYPE_MAP = {
				"animal": MainGameState.NpcType.ANIMAL,
				"monster": MainGameState.NpcType.MONSTER,
				"bandit": MainGameState.NpcType.BANDIT,
				"soldier": MainGameState.NpcType.SOLDIER,
			}
			var pick: String = common[rng.randi() % common.size()].to_lower()
			if TYPE_MAP.has(pick):
				return TYPE_MAP[pick]
	return MainGameState.NpcType.ANIMAL

# ─── Shared helpers ────────────────────────────────────────────────────────────

func _spawn_npc(npc_type: MainGameState.NpcType, world_pos: Vector2, variant: String = "") -> NPC:
	var inst: NPC = npc_scene.instantiate()
	inst.npc_type = npc_type
	if variant.is_empty():
		variant = _get_random_variant_for_type(npc_type)
	inst.npc_variant = variant
	add_child(inst)
	inst.global_position = world_pos
	inst.apply_type_profile()
	inst.add_to_group("NPCs")
	return inst

## Extracts tile-space positions from an Array of Structure resources or legacy Dictionaries.
func _extract_building_positions(buildings: Array) -> Array:
	var out: Array = []
	for b in buildings:
		if b is Structure:
			if b.POSITION != Vector2i.ZERO:
				out.append(b.POSITION)
		elif b is Dictionary and b.has("POSITION"):
			out.append(b["POSITION"])
	return out

func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile) * MainGameState.TILE_SIZE

func _assign_seed(entry: Dictionary) -> void:
	if entry.has("seed") and entry["seed"] != null:
		rng.seed = entry["seed"]
	else:
		rng.randomize()

func _get_random_variant_for_type(npc_type: MainGameState.NpcType) -> String:
	# Define available variants for each type
	# This is a simplified version - could be loaded from data or pulled from NPC class
	var variants_map = {
		MainGameState.NpcType.SOLDIER: ["default", "archer", "knight", "heavy_knight", "crossbowman", "longswordsman", "fencer", "warrior_monk", "battlemage", "dwarf_warrior", "elven_archer"],
		MainGameState.NpcType.PEASANT: ["default", "farmer", "baker", "blacksmith", "scholar", "crone", "hermit", "forester"],
		MainGameState.NpcType.MERCHANT: ["default"],
		MainGameState.NpcType.NOBLE: ["default", "priest", "cleric", "monk", "druid", "witch", "wizard", "warlock", "dwarf_wizard"],
		MainGameState.NpcType.BANDIT: ["default", "thief", "elven_rogue", "barbarian", "heavy_barbarian", "hill_tribe_warrior", "dark_priest"],
		MainGameState.NpcType.ANIMAL: ["default"],
		MainGameState.NpcType.MONSTER: ["default"]
	}
	
	var variants = variants_map.get(npc_type, ["default"])
	return variants[rng.randi() % variants.size()]

func _get_variant_for_role(npc_type: MainGameState.NpcType, role: String = "") -> String:
	# Helper to select appropriate variants based on role/context
	# You can expand this later with more sophisticated logic
	match npc_type:
		MainGameState.NpcType.SOLDIER:
			if role == "guard":
				return "default"
			elif role == "elite":
				return "knight"
			else:
				return _get_random_variant_for_type(npc_type)
		MainGameState.NpcType.PEASANT:
			if role == "worker":
				var workers = ["farmer", "blacksmith", "baker"]
				return workers[rng.randi() % workers.size()]
			else:
				return _get_random_variant_for_type(npc_type)
		_:
			return _get_random_variant_for_type(npc_type)
