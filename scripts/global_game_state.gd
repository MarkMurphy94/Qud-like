extends Node2D

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
        "buildings": {
            "house_1": {
                "pos": Vector2i(13, 21),
                "size": Vector2i(2, 2), # possibly need interior_size, ie excluding walls
                "type": "house",
                "inhabitants": ["npc_1", "npc_2"],
            }
        }
	}
}
