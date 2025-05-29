extends CharacterBody2D

@export var move_speed: float = 100.0
@export var grid_size: int = 16 # Size of each tile in pixels

@onready var overworld = $"../OverworldGenerator"

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
