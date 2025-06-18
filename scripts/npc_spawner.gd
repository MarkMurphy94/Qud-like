extends Node

class_name NPCSpawner

const NpcType = GlobalGameState.NpcType
const SettlementType = GlobalGameState.SettlementType

# Building type to NPC type mappings
const BUILDING_NPC_TYPES = {
	GlobalGameState.BuildingType.HOUSE: [NpcType.PEASANT],
	GlobalGameState.BuildingType.TAVERN: [NpcType.PEASANT, NpcType.MERCHANT],
	GlobalGameState.BuildingType.SHOP: [NpcType.MERCHANT],
	GlobalGameState.BuildingType.MANOR: [NpcType.NOBLE],
	GlobalGameState.BuildingType.BARRACKS: [NpcType.SOLDIER],
	GlobalGameState.BuildingType.CHURCH: [NpcType.PEASANT],
	GlobalGameState.BuildingType.KEEP: [NpcType.SOLDIER, NpcType.NOBLE]
}

# Reference to the NPC scene
var npc_scene: PackedScene
var rng: RandomNumberGenerator

func _init():
	rng = RandomNumberGenerator.new()
	rng.randomize()
	npc_scene = preload("res://scenes/npc.tscn") # Make sure this path is correct

func spawn_settlement_npcs(settlement_data: Dictionary, parent_node: Node2D) -> Array[Node]:
	var spawned_npcs: Array[Node] = []
	var settlement_type = settlement_data.get("type", SettlementType.TOWN)
	
	# Get NPC counts for this settlement type
	var npc_counts = GlobalGameState.settlement_npc_counts[settlement_type]
	
	# Spawn NPCs for each type
	for npc_type in npc_counts:
		var count = npc_counts[npc_type]
		for _i in range(count):
			var npc = spawn_npc(npc_type, parent_node)
			if npc:
				# Find appropriate building for this NPC type
				var building = find_suitable_building(npc_type, settlement_data)
				if building:
					var building_pos = building["pos"]
					var spawn_pos = Vector2(
						building_pos.x * GlobalGameState.TILE_SIZE,
						building_pos.y * GlobalGameState.TILE_SIZE
					)
					npc.initialize(parent_node, spawn_pos)
				spawned_npcs.append(npc)
	
	return spawned_npcs

func spawn_wilderness_npcs(_area_size: Vector2i, parent_node: Node2D, wilderness_type: String = "normal") -> Array[Node]:
	var spawned_npcs: Array[Node] = []
	var spawn_types = []
	var spawn_counts = {}
	
	match wilderness_type:
		"normal":
			spawn_types = [NpcType.ANIMAL, NpcType.PEASANT, NpcType.BANDIT]
			spawn_counts = {
				NpcType.ANIMAL: rng.randi_range(2, 5),
				NpcType.PEASANT: rng.randi_range(0, 2),
				NpcType.BANDIT: rng.randi_range(0, 2)
			}
		"dangerous":
			spawn_types = [NpcType.MONSTER, NpcType.BANDIT]
			spawn_counts = {
				NpcType.MONSTER: rng.randi_range(1, 3),
				NpcType.BANDIT: rng.randi_range(2, 4)
			}
		"peaceful":
			spawn_types = [NpcType.ANIMAL, NpcType.PEASANT]
			spawn_counts = {
				NpcType.ANIMAL: rng.randi_range(3, 6),
				NpcType.PEASANT: rng.randi_range(1, 2)
			}
	
	for npc_type in spawn_types:
		var count = spawn_counts[npc_type]
		for _i in range(count):
			var npc = spawn_npc(npc_type, parent_node)
			if npc:
				spawned_npcs.append(npc)
	
	return spawned_npcs

func spawn_npc(npc_type: GlobalGameState.NpcType, parent_node: Node2D) -> Node:
	var npc = npc_scene.instantiate()
	parent_node.add_child(npc)
	npc.npc_type = npc_type
	return npc

func find_suitable_building(npc_type: GlobalGameState.NpcType, settlement_data: Dictionary) -> Dictionary:
	var buildings = settlement_data.get("buildings", {})
	var suitable_buildings = []
	
	for building in buildings.values():
		var building_type = building.get("type")
		if building_type in BUILDING_NPC_TYPES:
			if npc_type in BUILDING_NPC_TYPES[building_type]:
				suitable_buildings.append(building)
	
	if suitable_buildings.is_empty():
		return {}
	
	return suitable_buildings[rng.randi() % suitable_buildings.size()]
