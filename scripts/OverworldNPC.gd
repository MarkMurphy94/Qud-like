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

func initialize(overworld_generator: Node2D) -> void:
	overworld = overworld_generator
	# Start at a random walkable tile
	var found = false
	for _i in 1000:
		var x = rng.randi_range(0, overworld.WIDTH - 1)
		var y = rng.randi_range(0, overworld.HEIGHT - 1)
		if overworld.is_walkable(Vector2i(x, y)):
			position = Vector2(x, y) * grid_size
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
		if move_timer <= 0.0:
			move_timer = move_interval
			choose_random_direction()
	
	# Update sprite flip based on movement direction
	if sprite and last_direction != Vector2.ZERO:
		sprite.flip_h = last_direction.x < 0

func choose_random_direction() -> void:
	var directions = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	
	# Prefer continuing in the same direction or turning 90 degrees
	if last_direction != Vector2.ZERO:
		directions.sort_custom(func(a, b):
			var a_dot = abs(a.dot(last_direction))
			var b_dot = abs(b.dot(last_direction))
			return a_dot > b_dot
		)
	else:
		directions.shuffle()
	
	var grid_pos = (position / grid_size).floor()
	for dir in directions:
		var new_grid_pos = grid_pos + dir
		if overworld.is_walkable(Vector2i(new_grid_pos.x, new_grid_pos.y)):
			# Check for other NPCs
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsRayQueryParameters2D.create(
				position,
				new_grid_pos * grid_size
			)
			query.collision_mask = collision_mask
			query.exclude = [get_rid()] # Exclude self from collision check
			var result = space_state.intersect_ray(query)
			
			if not result:
				target_position = new_grid_pos * grid_size
				last_direction = dir
				is_moving = true
				return

func _physics_process(_delta: float) -> void:
	if is_moving:
		var move_delta = target_position - position
		if move_delta.length() < movement_threshold:
			position = target_position
			is_moving = false
			move_timer = move_interval # Reset timer for next move
		else:
			# Use move_and_slide for proper collision handling
			velocity = move_delta.normalized() * move_speed
			move_and_slide()
			
			# Check if we're stuck
			if get_slide_collision_count() > 0:
				is_moving = false
				move_timer = 0.0 # Try to move in a different direction immediately
