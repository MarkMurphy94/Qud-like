extends CharacterBody2D

@export var move_speed: float = 100.0
@export var grid_size: int = 16 # Size of each tile in pixels

@onready var overworld = $"../OverworldGenerator"
var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var current_local_area: Node2D = null
var in_local_area: bool = false

var target_position: Vector2
var is_moving: bool = false

func _ready() -> void:
	# Initialize starting position to first walkable tile
	position = Vector2.ZERO
	find_valid_starting_position()
	target_position = position

func find_valid_starting_position() -> void:
	var grid_pos = Vector2i.ZERO
	for y in overworld.HEIGHT:
		for x in overworld.WIDTH:
			if overworld.is_walkable(Vector2i(x, y)):
				grid_pos = Vector2i(x, y)
				position = Vector2(grid_pos) * grid_size
				return

func _process(_delta: float) -> void:
	if not is_moving:
		check_movement_input()
	
	# Check for descend/ascend input
	if Input.is_action_just_pressed("ui_accept"): # Space bar
		if not in_local_area:
			descend_to_local_area()
		else:
			return_to_overworld()

func check_movement_input() -> void:
	var direction = Vector2.ZERO
	
	# Check for held input
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
	var grid_pos = (position / grid_size).floor()
	var new_grid_pos = grid_pos + direction
	
	# if overworld.is_walkable(Vector2i(new_grid_pos.x, new_grid_pos.y)):
	target_position = new_grid_pos * grid_size
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
	var grid_pos = (position / grid_size).floor()
	var tile_type = overworld.get_tile_type(Vector2i(grid_pos.x, grid_pos.y))
	
	# Create new local area
	current_local_area = local_area_scene.instantiate()
	get_tree().current_scene.add_child(current_local_area)
	current_local_area.initialize(tile_type, Vector2i(grid_pos.x, grid_pos.y))
	
	# Position player in local area
	position = Vector2(current_local_area.WIDTH / 2, current_local_area.HEIGHT / 2) * grid_size
	
	# Hide overworld and show local area
	overworld.hide()
	in_local_area = true

func return_to_overworld() -> void:
	if current_local_area:
		current_local_area.queue_free()
		current_local_area = null
	
	overworld.show()
	in_local_area = false
	
	# Ensure player is on grid
	var grid_pos = (position / grid_size).floor()
	position = grid_pos * grid_size
