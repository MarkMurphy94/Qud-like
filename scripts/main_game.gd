extends Node
@onready var overworld_map: Node2D = $OverworldMap


# Optional: call this from your Game.gd on startup with your overworld MainGameState.settlements
# entries: [{ "type": SettlementType.TOWN, "pos": Vector2i(13,21), "seed": 123 }, ...]
func bootstrap_settlements() -> void:
	for s in MainGameState.settlements.values():
		MainGameState.ensure_settlement_config(s.type, s.pos, s.get("seed", 0))

func _ready() -> void:
	# If you already know MainGameState.settlements at launch, call:
	bootstrap_settlements()

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
	var config := SettlementConfig.new()
	# Decide a filename using your existing key maker
	var pos := Vector2i(13, 21)
	var stype := MainGameState.SettlementType.TOWN
	var key := MainGameState.make_settlement_key(stype, pos) # scripts/main_game_state.gd
	var path := "res://resources/settlements/%s.tres" % key

	# Create and save
	var result := SettlementConfig.create_and_save(path, {
		"area_type": SettlementConfig.AreaType.TOWN,
		"settlement_name": "Ravenford",
		"climate": "temperate",
		"culture": "midlands"
	})
	if result.error == OK:
		print("Saved: ", path)
		var cfg := load(path) as SettlementConfig
		print("Loaded settlement name: ", cfg.settlement_name)
	else:
		push_error("Failed to save SettlementConfig: %s" % result.error)
	return config
