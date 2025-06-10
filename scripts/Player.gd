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
	target_position = global_position

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
		print('current position: ', position)

func try_move(direction: Vector2) -> void:
	var current_grid_pos: Vector2i
	var new_grid_pos: Vector2i
	
	if in_local_area:
		current_grid_pos = Vector2i(position / grid_size)
		new_grid_pos = current_grid_pos + Vector2i(direction)
		if is_local_tile_walkable(new_grid_pos):
			target_position = Vector2(new_grid_pos) * grid_size
			is_moving = true
	else:
		current_grid_pos = overworld.world_to_map(global_position)
		new_grid_pos = current_grid_pos + Vector2i(direction)
		if overworld.is_walkable(new_grid_pos):
			target_position = overworld.map_to_world(new_grid_pos)
			is_moving = true

func is_local_tile_walkable(pos: Vector2i) -> bool:
	if not current_local_area or not current_local_area.tilemap:
		return false
		
	# Get bounds from the tilemap
	var map_rect = current_local_area.tilemap.get_used_rect()
	
	# Check bounds
	if pos.x < map_rect.position.x or pos.x >= map_rect.end.x or \
	   pos.y < map_rect.position.y or pos.y >= map_rect.end.y:
		print("Position out of bounds: ", pos)
		return false
	
	return current_local_area.is_walkable(pos)

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
	var grid_pos = overworld.world_to_map(global_position)
	var tile_type = overworld.get_tile_data(grid_pos).terrain
	
	if tile_type == overworld.Terrain.WATER:
		print("Can't descend on water")
		return
		
	overworld_position = position
	
	if overworld.has_settlement(grid_pos):
		current_local_area = settlement_scene.instantiate()
		current_local_area.SETTLEMENT_TYPE = overworld.get_settlement(grid_pos)
		get_tree().current_scene.add_child(current_local_area)
		# Wait one frame for tilemap to initialize
		await get_tree().process_frame
		# Place player in a walkable position near the center
		find_valid_local_position()
	else:
		current_local_area = local_area_scene.instantiate()
		get_tree().current_scene.add_child(current_local_area)
		current_local_area.initialize(tile_type, grid_pos)
		# Wait one frame for map generation to complete
		await get_tree().process_frame
		# Find valid starting position
		find_valid_local_position()
	
	overworld.hide()
	in_local_area = true
	print('position in local area: ', position)

func find_valid_local_position() -> void:
	if not current_local_area or not current_local_area.tilemap:
		return
		
	# Get map bounds
	var map_rect = current_local_area.tilemap.get_used_rect()
	var center = Vector2i(
		map_rect.position.x + map_rect.size.x / 2,
		map_rect.position.y + map_rect.size.y / 2
	)
	
	var radius = 0
	var found = false
	
	while radius < 10 and not found: # Limit search radius to avoid infinite loop
		# Check tiles in a square pattern around the center
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var test_pos = center + Vector2i(x, y)
				if is_local_tile_walkable(test_pos):
					position = Vector2(test_pos) * grid_size
					found = true
					break
			if found:
				break
		radius += 1
	
	if not found:
		# Fallback to center if no walkable tile found
		position = Vector2(center) * grid_size

func return_to_overworld() -> void:
	if current_local_area:
		current_local_area.queue_free()
		current_local_area = null
	
	overworld.show()
	in_local_area = false
	position = overworld_position
	print('position in overworld: ', position)
