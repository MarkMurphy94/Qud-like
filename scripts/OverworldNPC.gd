extends CharacterBody2D

@export var move_speed: float = 80.0
@export var grid_size: int = 16
@export var move_interval: float = 0.5 # seconds between moves
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete

var overworld: Node2D
var rng = RandomNumberGenerator.new()
var target_position: Vector2
var is_moving: bool = false
var move_timer: float = 0.0
var last_direction: Vector2 = Vector2.ZERO
var sprite: Sprite2D

func _ready() -> void:
	rng.randomize() # Initialize random number generator
	sprite = $Sprite2D # Make sure to add a Sprite2D node as child
	if not sprite:
		push_error("Sprite2D node not found!")
	
	# Set up collision (layer 1 for NPCs)
	collision_layer = 1
	collision_mask = 1
	
	if not overworld:
		set_physics_process(false)
		set_process(false)
	else:
		# Start the movement timer
		move_timer = move_interval

func initialize(overworld_map: Node2D) -> void:
	overworld = overworld_map
	# Start at a random walkable tile
	var found = false
	for _i in 1000:
		var x = rng.randi_range(0, overworld.WIDTH - 1)
		var y = rng.randi_range(0, overworld.HEIGHT - 1)
		var grid_pos = Vector2i(x, y)
		if overworld.is_walkable(grid_pos):
			position = overworld.map_to_world(grid_pos)
			target_position = position
			found = true
			break
	if not found:
		push_error("No walkable tile found for NPC!")
	
	# Enable processing after initialization
	set_physics_process(true)
	set_process(true)

func _process(delta: float) -> void:
	if not is_moving:
		move_timer -= delta
		if move_timer <= 0:
			choose_next_move()
			move_timer = move_interval

func _physics_process(delta: float) -> void:
	if is_moving:
		var move_delta = target_position - position
		if move_delta.length() < movement_threshold:
			position = target_position
			is_moving = false
		else:
			var movement = move_delta.normalized() * move_speed * delta
			position += movement

func choose_next_move() -> void:
	var current_grid_pos = overworld.world_to_map(position)
	var valid_moves = overworld.get_valid_move_positions(current_grid_pos)
	
	if valid_moves.is_empty():
		return
		
	# Prefer continuing in same direction if possible
	if last_direction != Vector2.ZERO:
		var preferred_pos = current_grid_pos + Vector2i(last_direction)
		if preferred_pos in valid_moves and randf() < 0.7: # 70% chance to continue direction
			target_position = overworld.map_to_world(preferred_pos)
			is_moving = true
			return
	
	# Otherwise choose random valid move
	var new_pos = valid_moves[rng.randi() % valid_moves.size()]
	target_position = overworld.map_to_world(new_pos)
	last_direction = (new_pos - current_grid_pos).limit_length(1)
	is_moving = true
	
	# Update sprite direction
	if sprite:
		if last_direction.x > 0:
			sprite.flip_h = false
		elif last_direction.x < 0:
			sprite.flip_h = true
