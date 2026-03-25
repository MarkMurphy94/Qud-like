extends Node

## NPC types — canonical list used by NPCSpawner, NPC, and dialogue systems.
enum NpcType {PEASANT, SOLDIER, MERCHANT, NOBLE, BANDIT, ANIMAL, MONSTER}

## Map types and building sizes are now defined in MapConfig.
## • MapConfig.MapType       — what kind of local map (NON_SETTLEMENT, SETTLEMENT, CASTLE_INTERIOR, DUNGEON)
## • MapConfig.BuildingDensity — how large a settlement is (NONE → CITY)
## • Structure.StructureType  — individual building types (HOUSE, TAVERN, SHOP …)

const TILE_SIZE = 16

var player_turn = false

# ─── Settlements ──────────────────────────────────────────────────────────────────────────

## Runtime state for each known settlement, keyed by make_settlement_key() or a
## human-readable name for hand-crafted settlements.
var settlements = {
	"town_1": {
		"name": "First town",
		"pos": Vector2i(13, 21),
		"seed": 1605628986,
		"map_type": MapConfig.MapType.SETTLEMENT,
		"density": MapConfig.BuildingDensity.LARGE_TOWN,
		"buildings": {
			"house_1": {
				"pos": Vector2i(13, 21),
				"size": Vector2i(2, 2),
				"type": "house",
				"inhabitants": ["npc_1", "npc_2"],
			}
		},
		"important_npcs": {}
	},
	"town_2": {
		"name": "town_2",
		"map_type": MapConfig.MapType.SETTLEMENT,
		"density": MapConfig.BuildingDensity.LARGE_VILLAGE,
		"pos": Vector2i(17, 18),
		"seed": 1471873267,
		"width": 80,
		"height": 80,
		"buildings": {},
		"important_npcs": {}
	},
	"town_3": {
		"name": "town_3",
		"map_type": MapConfig.MapType.CASTLE_INTERIOR,
		"density": MapConfig.BuildingDensity.NONE,
		"pos": Vector2i(7, 22),
	},
}

# ─── NPC counts per density tier ────────────────────────────────────────────────────────

## Keyed by MapConfig.BuildingDensity. NPCSpawner reads settlement_data.building_density
## to look up the appropriate counts rather than using a separate "type" field.
var settlement_npc_counts: Dictionary = {
	MapConfig.BuildingDensity.NONE: {
		NpcType.ANIMAL: 3,
	},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		NpcType.PEASANT: 5,
		NpcType.SOLDIER: 1,
		NpcType.MERCHANT: 1,
		NpcType.ANIMAL: 3,
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		NpcType.PEASANT: 8,
		NpcType.SOLDIER: 2,
		NpcType.MERCHANT: 2,
		NpcType.NOBLE: 1,
		NpcType.ANIMAL: 2,
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		NpcType.PEASANT: 10,
		NpcType.SOLDIER: 2,
		NpcType.MERCHANT: 3,
		NpcType.NOBLE: 1,
		NpcType.ANIMAL: 2,
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		NpcType.PEASANT: 15,
		NpcType.SOLDIER: 4,
		NpcType.MERCHANT: 5,
		NpcType.NOBLE: 2,
		NpcType.BANDIT: 1,
		NpcType.ANIMAL: 2,
	},
	MapConfig.BuildingDensity.CITY: {
		NpcType.PEASANT: 30,
		NpcType.SOLDIER: 5,
		NpcType.MERCHANT: 10,
		NpcType.NOBLE: 3,
		NpcType.BANDIT: 2,
		NpcType.ANIMAL: 2,
	},
}

# All important NPCs, keyed by unique ID
var important_npcs = {}

# ─── Settlement helpers ──────────────────────────────────────────────────────────────────

func add_settlement(id: String, data: Dictionary) -> void:
	settlements[id] = data
	print(settlements[id])

func get_settlement(id: String) -> Dictionary:
	return settlements.get(id, {})

func add_npc(id: String, data: Dictionary) -> void:
	important_npcs[id] = data

func get_npc(id: String) -> Dictionary:
	return important_npcs.get(id, {})

func world_to_map(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / TILE_SIZE)

func map_to_world(map_pos: Vector2i) -> Vector2:
	return Vector2(map_pos * TILE_SIZE)

## Build a stable key from MapConfig.MapType + world position.
## e.g. settlement at (13, 21) → "settlement_13_21"
func make_settlement_key(map_type: int, world_pos: Vector2i) -> String:
	const TYPE_NAMES: Dictionary = {
		0: "area",        # MapConfig.MapType.NON_SETTLEMENT
		1: "settlement",  # MapConfig.MapType.SETTLEMENT
		2: "castle",      # MapConfig.MapType.CASTLE_INTERIOR
		3: "dungeon",     # MapConfig.MapType.DUNGEON
	}
	var tname: String = TYPE_NAMES.get(map_type, "unknown")
	return "%s_%d_%d" % [tname, world_pos.x, world_pos.y]

## Ensure a minimal runtime entry exists for a settlement; returns the entry.
## map_type should be a MapConfig.MapType value.
func ensure_settlement_config(map_type: int, world_pos: Vector2i, seed_value: int = 0) -> Dictionary:
	var key := make_settlement_key(map_type, world_pos)
	var conf := get_settlement(key)
	if conf.is_empty():
		if seed_value == 0:
			seed_value = randi()
		conf = {
			"name": key,
			"map_type": map_type,
			"pos": world_pos,
			"seed": seed_value,
			"width": 80,
			"height": 80,
			"buildings": {},
			"important_npcs": {}
		}
	else:
		# Backfill missing fields for older saves
		if not conf.has("map_type"): conf["map_type"] = map_type
		if not conf.has("pos"): conf["pos"] = world_pos
		if not conf.has("seed") or conf["seed"] == null:
			conf["seed"] = seed_value if seed_value != 0 else randi()
		if not conf.has("width"): conf["width"] = 80
		if not conf.has("height"): conf["height"] = 80
		if not conf.has("buildings"): conf["buildings"] = {}
	add_settlement(key, conf)
	return conf
