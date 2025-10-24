extends Node

# Types of settlements
enum SettlementType {TOWN, CITY, CASTLE}
# Types of buildings
enum BuildingType {HOUSE, TAVERN, SHOP, MANOR, BARRACKS, CHURCH, KEEP}
enum NpcType {PEASANT, SOLDIER, MERCHANT, NOBLE, BANDIT, ANIMAL, MONSTER}

# Building templates and other static data
const TILE_SIZE = 16
const BUILDING_TEMPLATES = {}
const NPC_TEMPLATES = {}
const FACTIONS = {}

var player_turn = false

# All settlements, keyed by unique ID or coordinates
var settlements = {
	"town_1": {
		"pos": Vector2i(13, 21),
		"seed": 1605628986,
		"type": SettlementType.TOWN,
		"buildings": {
			"house_1": {
				"pos": Vector2i(13, 21),
				"size": Vector2i(2, 2), # possibly need interior_size, ie excluding walls
				"type": "house",
				"inhabitants": ["npc_1", "npc_2"],
			}
		},
		"important_npcs": {}
	},
	"town_2_full": {
		"type": SettlementType.TOWN,
		"pos": Vector2i(17, 18),
		"seed": null,
		"width": 80,
		"height": 80,
		"buildings": {
			"tavern_at_29_41": {
				"id": "tavern_at_29_41",
				"type": BuildingType.TAVERN,
				"pos": Vector2i(29, 41),
				"size": Vector2i(7, 7),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"shop_at_56_34": {
				"id": "shop_at_56_34",
				"type": BuildingType.SHOP,
				"pos": Vector2i(56, 34),
				"size": Vector2i(6, 7),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_34_32": {
				"id": "house_at_34_32",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(34, 32),
				"size": Vector2i(4, 6),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_40_31": {
				"id": "house_at_40_31",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(40, 31),
				"size": Vector2i(6, 5),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_39_51": {
				"id": "house_at_39_51",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(39, 51),
				"size": Vector2i(5, 4),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_26_14": {
				"id": "house_at_26_14",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(26, 14),
				"size": Vector2i(6, 4),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_18_46": {
				"id": "house_at_18_46",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(18, 46),
				"size": Vector2i(6, 5),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_50_44": {
				"id": "house_at_50_44",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(50, 44),
				"size": Vector2i(5, 6),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_39_42": {
				"id": "house_at_39_42",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(39, 42),
				"size": Vector2i(5, 6),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_33_23": {
				"id": "house_at_33_23",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(33, 23),
				"size": Vector2i(4, 5),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_20_39": {
				"id": "house_at_20_39",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(20, 39),
				"size": Vector2i(6, 5),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			},
			"house_at_40_56": {
				"id": "house_at_40_56",
				"type": BuildingType.HOUSE,
				"pos": Vector2i(40, 56),
				"size": Vector2i(6, 4),
				"zones": [],
				"inhabitants": [],
				"interior_features": {},
				"scripted_content": null
			}
		},
		"important_npcs": {}
	}
}

var settlement_npc_counts = {
	SettlementType.TOWN: {
		NpcType.PEASANT: 10,
		NpcType.SOLDIER: 2,
		NpcType.MERCHANT: 3,
		NpcType.NOBLE: 1,
		NpcType.ANIMAL: 5,
	},
	SettlementType.CITY: {
		NpcType.PEASANT: 30,
		NpcType.SOLDIER: 5,
		NpcType.MERCHANT: 10,
		NpcType.NOBLE: 3,
		NpcType.BANDIT: 2,
		NpcType.ANIMAL: 2,
	},
	SettlementType.CASTLE: {
		NpcType.PEASANT: 20,
		NpcType.SOLDIER: 10,
		NpcType.MERCHANT: 5,
		NpcType.NOBLE: 5,
		NpcType.ANIMAL: 10
	}
}

# All important NPCs, keyed by unique ID
var important_npcs = {}

# Example: Add, get, update, and remove functions for settlements and NPCs
func add_settlement(id: String, data: Dictionary) -> void:
	settlements[id] = data

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
	
# Create a stable key from type+world position
func make_settlement_key(settlement_type: int, world_pos: Vector2i) -> String:
	var tname = ["town", "city", "castle"][settlement_type]
	return "%s_%d_%d" % [tname, world_pos.x, world_pos.y]

# Ensure a minimal config exists for a settlement; returns the config
func ensure_settlement_config(settlement_type: int, world_pos: Vector2i, seed_value: int = 0) -> Dictionary:
	var key := make_settlement_key(settlement_type, world_pos)
	var conf = get_settlement(key)
	if conf.is_empty():
		if seed_value == 0:
			seed_value = randi()
		conf = {
			"type": settlement_type,
			"pos": world_pos,
			"seed": seed_value,
			"width": 80,
			"height": 80,
			"buildings": {}, # filled after first entry
			"important_npcs": {}
		}
		settlements[key] = conf
	else:
		# Backfill missing fields for older saves
		if not conf.has("type"): conf.type = settlement_type
		if not conf.has("pos"): conf.pos = world_pos
		if not conf.has("seed") or conf.seed == null: conf.seed = (seed_value if seed_value != 0 else randi())
		if not conf.has("width"): conf.width = 80
		if not conf.has("height"): conf.height = 80
		if not conf.has("buildings"): conf.buildings = {}
		settlements[key] = conf
	return conf
