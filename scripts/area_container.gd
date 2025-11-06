extends Node2D

@onready var area: Node2D = $area
@onready var spawn_tile: Area2D = $spawn_tile
var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var settlement_scene
var current_area: Node2D

func set_local_area():
	current_area = local_area_scene.instantiate()
	area.add_child(current_area)

func clear_local_area_scene():
	if current_area:
		current_area.queue_free()
		current_area = null

func set_settlement():
	pass
