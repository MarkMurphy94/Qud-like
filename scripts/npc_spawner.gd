extends Node
class_name NPCSpawner

@export var npc_scene: PackedScene = preload("res://scenes/npc.tscn") # create this scene with an NPC root
var settlement_data: AreaConfig
var spawned_npcs: Array = []
var rng := RandomNumberGenerator.new()

func _ready():
	pass
	# Try to locate MainGameState (autoload or ancestor)
	# if not MainGameState:
	#	 MainGameState = get_tree().get_first_node_in_group("MainGameState")

func clear():
	for n in spawned_npcs:
		if is_instance_valid(n):
			n.queue_free()
	spawned_npcs.clear()

func spawn_settlement_npcs():
	if not settlement_data:
		push_warning("No settlement_data set on NPCSpawner")
		return
	clear()
	var settlement_name = settlement_data.settlement_name
	if not MainGameState.settlements.has(settlement_name):
		push_warning("MainGameState missing settlement entry for %s" % settlement_name)
		return

	var settlement_entry = MainGameState.settlements[settlement_name]
	var counts_map = MainGameState.settlement_npc_counts.get(settlement_entry.type, {})
	_assign_seed(settlement_entry)
	var building_positions = _extract_building_positions(settlement_data.buildings)
	
	# Allocate homes (simple round-robin)
	var home_index = 0
	var homes = building_positions.duplicate()
	homes.shuffle()

	for npc_type in counts_map.keys():
		var target_count: int = counts_map[npc_type]
		for i in target_count:
			var home_tile: Vector2i = homes[home_index % homes.size()]
			home_index += 1
			var world_pos = _tile_to_world(home_tile)
			var npc = _spawn_npc(npc_type, world_pos)
			npc.set_locations(world_pos)
			npc.npc_id = "%s_%s_%d" % [settlement_name, str(npc_type), i]
			spawned_npcs.append(npc)

func spawn_wilderness_npcs(count: int = 5):
	clear()
	if not npc_scene:
		return
	for i in count:
		var npc_type = MainGameState.NpcType.ANIMAL
		var pos = Vector2(rng.randi_range(0, 1200), rng.randi_range(0, 1200))
		var npc = _spawn_npc(npc_type, pos)
		npc.set_locations(pos)
		spawned_npcs.append(npc)

func _spawn_npc(npc_type: MainGameState.NpcType, world_pos: Vector2) -> NPC:
	var inst: NPC = npc_scene.instantiate()
	inst.npc_type = npc_type
	add_child(inst)
	inst.global_position = world_pos
	inst.apply_type_profile()
	return inst

func _extract_building_positions(buildings: Array) -> Array:
	var out: Array = []
	for b in buildings:
		if b.get("POSITION"):
			out.append(b.get("POSITION"))
	return out

func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile.x, tile.y) * MainGameState.TILE_SIZE

func _assign_seed(entry: Dictionary):
	if entry.has("seed"):
		rng.seed = entry.seed
	else:
		rng.randomize()
