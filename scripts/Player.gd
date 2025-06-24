extends CharacterBody2D

@export var move_speed: float = 200.0
@export var tile_size: int = 16

@onready var overworld = $"../OverworldMap"
@onready var camera = $Camera2D
var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var settlement_scene = preload("res://scenes/settlement_generator.tscn")
var current_local_area: Node2D = null
var map_rect = null
var in_local_area: bool = false

var target_position: Vector2
var is_moving: bool = false
var overworld_grid_pos: Vector2

func _ready() -> void:
	target_position = global_position
	update_camera_limits()

func _process(_delta: float) -> void:
	if not is_moving:
		check_movement_input()
	if Input.is_action_just_pressed("ui_accept"):
		if in_local_area:
			return_to_overworld()
		else:
			descend_to_local_area()

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
	var current_grid_pos: Vector2i
	var new_grid_pos: Vector2i
	if in_local_area:
		current_grid_pos = Vector2i(position / tile_size)
		new_grid_pos = current_grid_pos + Vector2i(direction)
		if is_local_tile_walkable(new_grid_pos):
			target_position = Vector2(new_grid_pos) * tile_size
			is_moving = true
	else:
		current_grid_pos = overworld.world_to_map(global_position)
		new_grid_pos = current_grid_pos + Vector2i(direction)
		if overworld.is_walkable(new_grid_pos):
			target_position = overworld.map_to_world(new_grid_pos)
			is_moving = true

func descend_to_local_area() -> void:
	overworld_grid_pos = overworld.world_to_map(global_position)
	var tile_type = overworld.get_tile_data(overworld_grid_pos).terrain
	if tile_type == overworld.Terrain.WATER:
		print("Can't descend on water")
		return
	if overworld.has_settlement(overworld_grid_pos):
		current_local_area = settlement_scene.instantiate()
		current_local_area.SEED = overworld.get_settlement_from_seed(overworld_grid_pos)
		get_tree().current_scene.add_child(current_local_area)
		await get_tree().process_frame
		map_rect = current_local_area.tilemaps["GROUND"].get_used_rect()
		find_valid_local_position()
	else:
		current_local_area = local_area_scene.instantiate()
		get_tree().current_scene.add_child(current_local_area)
		current_local_area.initialize(tile_type, overworld_grid_pos)
		await get_tree().process_frame
		map_rect = current_local_area.tilemaps["GROUND"].get_used_rect()
		find_valid_local_position()
		print('overworld_grid_pos: ', overworld_grid_pos)
	overworld.hide()
	in_local_area = true
	update_camera_limits()

func find_valid_local_position() -> void:
	if not current_local_area or not current_local_area.tilemaps or not current_local_area.tilemaps.has("GROUND"):
		return
	var start_pos = Vector2i(map_rect.position)
	for y in map_rect.size.y:
		for x in map_rect.size.x:
			var test_pos = start_pos + Vector2i(x, y)
			if is_local_tile_walkable(test_pos):
				position = Vector2(test_pos) * tile_size
				return
	position = Vector2(start_pos) * tile_size

func is_local_tile_walkable(pos: Vector2i) -> bool:
	if not current_local_area or not current_local_area.tilemaps or not current_local_area.tilemaps.has("GROUND"):
		return false
	if pos.x < map_rect.position.x or pos.x >= map_rect.end.x or \
	   pos.y < map_rect.position.y or pos.y >= map_rect.end.y:
		print("Position out of bounds: ", pos)
		return false
	# print('map_rect position: ', pos)
	return current_local_area.is_walkable(pos)

func _physics_process(_delta: float) -> void:
	if is_moving:
		var move_delta = target_position - position
		if move_delta.length() < 1.0:
			position = target_position
			velocity = Vector2.ZERO
			is_moving = false
			return
		velocity = move_delta.normalized() * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
	
	if in_local_area:
		_update_roof_visibility()

# Hide/show roof based on whether player is inside a building
func _update_roof_visibility() -> void:
	if not current_local_area or not current_local_area.tilemaps:
		return
	var roof_map = current_local_area.tilemaps.get("ROOF")
	if not roof_map:
		return
	var interior_map = current_local_area.tilemaps.get("INTERIOR_FLOOR")
	var grid_pos = Vector2i(position / tile_size)
	var is_inside = interior_map.get_cell_tile_data(Vector2i(grid_pos.x, grid_pos.y))
	roof_map.visible = not is_inside

func return_to_overworld() -> void:
	if current_local_area:
		current_local_area.queue_free()
		current_local_area = null
		map_rect = null
	overworld.show()
	in_local_area = false
	position = overworld.map_to_world(overworld_grid_pos)
	update_camera_limits()

func update_camera_limits() -> void:
	if not camera:
		return
	if in_local_area and current_local_area and map_rect:
		var margin = 0
		camera.limit_left = map_rect.position.x * tile_size - margin
		camera.limit_right = (map_rect.end.x) * tile_size + margin
		camera.limit_top = map_rect.position.y * tile_size - margin
		camera.limit_bottom = (map_rect.end.y) * tile_size + margin
	else:
		camera.limit_left = 0
		camera.limit_right = overworld.WIDTH * tile_size
		camera.limit_top = 0
		camera.limit_bottom = overworld.HEIGHT * tile_size
