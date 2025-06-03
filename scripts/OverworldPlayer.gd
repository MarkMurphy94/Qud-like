extends CharacterBody2D

@export var move_speed: float = 100.0
@export var grid_size: int = 16 # Size of each tile in pixels

@onready var overworld = $"../OverworldMap"
var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var settlement_scene = preload("res://scenes/settlement_generator.tscn")
var current_local_area: Node2D = null
var in_local_area: bool = false

var target_position: Vector2
var is_moving: bool = false
var overworld_position: Vector2

func _ready() -> void:
	# find_valid_starting_position()
	target_position = position

func find_valid_starting_position() -> void:
	var grid_pos = Vector2i.ZERO
	for y in overworld.HEIGHT:
		for x in overworld.WIDTH:
			if overworld.is_walkable(Vector2i(x, y)):
				grid_pos = Vector2i(x, y)
				position = overworld.map_to_world(grid_pos)
				return

func _process(_delta: float) -> void:
	if not is_moving:
		check_movement_input()
	
	if Input.is_action_just_pressed("ui_accept"): # Space bar
		if not in_local_area:
			descend_to_local_area()
		else:
			return_to_overworld()

func check_movement_input() -> void:
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction = Vector2.RIGHT
	elif Input.is_action_pressed("ui_left"):
		direction = Vector2.LEFT
	elif Input.is_action_pressed("ui_up"):
		direction = Vector2.UP
	elif Input.is_action_pressed("ui_down"):
		direction = Vector2.DOWN
	
	if direction != Vector2.ZERO:
		try_move(direction)

func try_move(direction: Vector2) -> void:
	var current_grid_pos = overworld.world_to_map(position)
	var new_grid_pos = current_grid_pos + Vector2i(direction)
	
	if overworld.is_walkable(new_grid_pos):
		target_position = overworld.map_to_world(new_grid_pos)
		is_moving = true

func _physics_process(delta: float) -> void:
	if is_moving:
		var move_delta = target_position - position
		var movement = move_delta.normalized() * move_speed * delta
		
		if movement.length() > move_delta.length():
			position = target_position
			is_moving = false
		else:
			position += movement

func descend_to_local_area() -> void:
	var grid_pos = overworld.world_to_map(position)
	var tile_type = overworld.get_tile_data(grid_pos).terrain
	
	if tile_type == overworld.Terrain.WATER:
		print("Can't descend on water")
		return
		
	overworld_position = position
	
	if overworld.has_settlement(grid_pos):
		current_local_area = settlement_scene.instantiate()
		get_tree().current_scene.add_child(current_local_area)
	else:
		current_local_area = local_area_scene.instantiate()
		get_tree().current_scene.add_child(current_local_area)
		current_local_area.initialize(tile_type, grid_pos)
	
	position = Vector2(current_local_area.WIDTH / 2, current_local_area.HEIGHT / 2) * grid_size
	overworld.hide()
	in_local_area = true

func return_to_overworld() -> void:
	if current_local_area:
		current_local_area.queue_free()
		current_local_area = null
	
	overworld.show()
	in_local_area = false
	position = overworld_position
