extends Node
@onready var overworld_map: Node2D = $OverworldMap

# Optional: call this from your Game.gd on startup with your overworld MainGameState.settlements
# entries: [{ "type": SettlementType.TOWN, "pos": Vector2i(13,21), "seed": 123 }, ...]
func bootstrap_settlements(entries: Array) -> void:
	for e in entries:
		MainGameState.ensure_settlement_config(e.type, e.pos, e.get("seed", 0))

func _ready() -> void:
	# If you already know MainGameState.settlements at launch, call:
	bootstrap_settlements(get_all_settlements())
	pass


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
