extends Node2D
# Types of settlements
enum SettlementType {TOWN, CITY, CASTLE}
# Types of buildings
enum BuildingType {HOUSE, TAVERN, SHOP, MANOR, BARRACKS, CHURCH, KEEP}
enum NpcType {PEASANT, SOLDIER, MERCHANT, NOBLE, BANDIT, ANIMAL, MONSTER}

const TILE_SIZE = 16 # Size of each tile in pixels

var global_game_state: Dictionary = {
	"player_position": Vector2.ZERO,
	"current_local_area": null,
	"in_local_area": false,
	"overworld_grid_pos": Vector2i.ZERO,
	"settlement_type": "TOWN", # Default settlement type
}

var settlement_data: Dictionary = {
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
		"npcs": {}
	}
}

var settlement_npc_counts = {
	SettlementType.TOWN: {
		NpcType.PEASANT: 10,
		NpcType.SOLDIER: 2,
		NpcType.MERCHANT: 1,
		NpcType.NOBLE: 0
	},
	SettlementType.CITY: {
		NpcType.PEASANT: 20,
		NpcType.SOLDIER: 3,
		NpcType.MERCHANT: 3,
		NpcType.NOBLE: 4
	},
	SettlementType.CASTLE: {
		NpcType.PEASANT: 4,
		NpcType.SOLDIER: 0,
		NpcType.MERCHANT: 0,
		NpcType.NOBLE: 1
	}
}
