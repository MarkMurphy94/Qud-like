extends Node2D

@onready var area: Node2D = $area
@onready var spawn_tile: Area2D = $spawn_tile
var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var npc_spawner_scene = preload("res://scenes/npc_spawner.tscn")
var area_config: AreaConfig
var current_area: Node2D
var npc_spawner: Node2D

# TODO: consolidate repeated code

func set_local_area(metadata: Dictionary = {}):
	current_area = local_area_scene.instantiate()
	current_area.auto_generate_on_ready = false
	npc_spawner = npc_spawner_scene.instantiate()
	if "config" in current_area:
		npc_spawner.settlement_data = current_area.config
	area.add_child(current_area)
	
	current_area.generate_local_map(metadata)
		
	current_area.add_child(npc_spawner)
	npc_spawner.spawn_wilderness_npcs()

func clear_local_area_scene():
	if current_area:
		current_area.queue_free()
		current_area = null

func set_settlement_scene(scene_path: String):
	var scene = load(scene_path)
	current_area = scene.instantiate()
	npc_spawner = npc_spawner_scene.instantiate()
	npc_spawner.settlement_data = current_area.config
	area.add_child(current_area)
	current_area.add_child(npc_spawner)
	npc_spawner.spawn_settlement_npcs()
