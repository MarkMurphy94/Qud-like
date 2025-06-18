extends CharacterBody2D

@export var move_speed: float = 80.0
@export var grid_size: int = 16
@export var move_interval: float = 0.5 # seconds between moves
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete
@export var npc_type: GlobalGameState.NpcType = GlobalGameState.NpcType.PEASANT

var overworld: Node2D
var rng = RandomNumberGenerator.new()
var target_position: Vector2
var is_moving: bool = false
var move_timer: float = 0.0
var last_direction: Vector2 = Vector2.ZERO
var sprite: Sprite2D
var home_position: Vector2 # The position this NPC considers "home"
var wander_radius: float = 5.0 # How far from home position the NPC will wander (in tiles)
var state: String = "idle" # Current behavior state
var interaction_range: float = 32.0 # Range for interacting with other NPCs

# NPC Type-specific properties
var npc_properties = {
	GlobalGameState.NpcType.PEASANT: {
		"move_speed": 80.0,
		"move_interval": 0.5,
		"wander_radius": 5.0,
		"sprite_region_coords": Rect2i(0, 160, 32, 32),
		"behavior": "wander_near_home"
	},
	GlobalGameState.NpcType.SOLDIER: {
		"move_speed": 100.0,
		"move_interval": 0.4,
		"wander_radius": 8.0,
		"sprite_region_coords": Rect2i(64, 32, 32, 32),
		"behavior": "patrol"
	},
	GlobalGameState.NpcType.MERCHANT: {
		"move_speed": 70.0,
		"move_interval": 0.6,
		"wander_radius": 3.0,
		"sprite_region_coords": Rect2i(96, 160, 32, 32),
		"behavior": "stay_near_shop"
	},
	GlobalGameState.NpcType.NOBLE: {
		"move_speed": 60.0,
		"move_interval": 0.7,
		"wander_radius": 4.0,
		"sprite_region_coords": Rect2i(160, 160, 32, 32),
		"behavior": "stay_in_manor"
	},
	GlobalGameState.NpcType.BANDIT: {
		"move_speed": 120.0,
		"move_interval": 0.3,
		"wander_radius": 10.0,
		"sprite_region_coords": Rect2i(19, 0, 32, 32),
		"behavior": "aggressive"
	},
	GlobalGameState.NpcType.ANIMAL: {
		"move_speed": 90.0,
		"move_interval": 0.4,
		"wander_radius": 6.0,
		"sprite_region_coords": Rect2i(128, 96, 32, 32),
		"behavior": "flee_on_approach"
	},
	GlobalGameState.NpcType.MONSTER: {
		"move_speed": 110.0,
		"move_interval": 0.3,
		"wander_radius": 12.0,
		"sprite_region_coords": Rect2i(128, 32, 32, 32),
		"behavior": "hunt"
	}
}

func _ready() -> void:
	rng.randomize()
	sprite = $Sprite2D
	if not sprite:
		push_error("Sprite2D node not found!")
	
	# Set up collision (layer 1 for NPCs)
	collision_layer = 1
	collision_mask = 1
	
	# Apply NPC type-specific properties
	var properties = npc_properties[npc_type]
	move_speed = properties["move_speed"]
	move_interval = properties["move_interval"]
	wander_radius = properties["wander_radius"]
	if sprite:
		sprite.region_rect = properties["sprite_region_coords"]
	
	if not overworld:
		set_physics_process(false)
		set_process(false)

func initialize(overworld_map: Node2D, start_pos: Vector2 = Vector2.ZERO) -> void:
	overworld = overworld_map
	if start_pos != Vector2.ZERO:
		position = start_pos
		home_position = start_pos
	else:
		# Find valid starting position
		var found = false
		for _i in 100:
			var x = rng.randi_range(0, overworld.WIDTH - 1)
			var y = rng.randi_range(0, overworld.HEIGHT - 1)
			var grid_pos = Vector2i(x, y)
			if is_valid_position(grid_pos):
				position = overworld.map_to_world(grid_pos)
				home_position = position
				found = true
				break
		
		if not found:
			push_error("Could not find valid starting position for NPC")
			queue_free()
			return
	
	# Enable processing
	set_physics_process(true)
	set_process(true)

func _process(delta: float) -> void:
	if not is_moving:
		move_timer += delta
		if move_timer >= move_interval:
			move_timer = 0.0
			choose_next_move()

func _physics_process(delta: float) -> void:
	if is_moving:
		var move_direction = (target_position - position).normalized()
		velocity = move_direction * move_speed * delta
		
		if position.distance_to(target_position) < movement_threshold:
			position = target_position
			is_moving = false
		else:
			move_and_slide()

func choose_next_move() -> void:
	match npc_properties[npc_type]["behavior"]:
		"wander_near_home":
			choose_wander_move()
		"patrol":
			choose_patrol_move()
		"stay_near_shop", "stay_in_manor":
			choose_restricted_move()
		"aggressive", "hunt":
			choose_hunting_move()
		"flee_on_approach":
			choose_fleeing_move()

func choose_wander_move() -> void:
	var current_grid_pos = overworld.world_to_map(position)
	var valid_moves = get_valid_moves_in_radius(current_grid_pos, wander_radius)
	
	if valid_moves.is_empty():
		return
	
	# Prefer moves that keep us within our wander radius of home
	var home_grid = overworld.world_to_map(home_position)
	valid_moves.sort_custom(func(a, b):
		return a.distance_to(home_grid) < b.distance_to(home_grid)
	)
	
	# Pick one of the best moves (with some randomness)
	var move_index = rng.randi() % min(3, valid_moves.size())
	var new_pos = valid_moves[move_index]
	set_move_target(new_pos)

func choose_patrol_move() -> void:
	var current_grid_pos = overworld.world_to_map(position)
	var valid_moves = get_valid_moves_in_radius(current_grid_pos, 1.0)
	
	if valid_moves.is_empty():
		return
	
	# Soldiers prefer to move along straight lines
	if last_direction != Vector2.ZERO:
		for move in valid_moves:
			if (move - current_grid_pos) == last_direction:
				set_move_target(move)
				return
	
	# If can't continue straight, choose a new random direction
	var new_pos = valid_moves[rng.randi() % valid_moves.size()]
	set_move_target(new_pos)

func choose_restricted_move() -> void:
	var current_grid_pos = overworld.world_to_map(position)
	var home_grid = overworld.world_to_map(home_position)
	
	# If too far from home, try to move back
	if current_grid_pos.distance_to(home_grid) > wander_radius:
		var valid_moves = get_valid_moves_in_radius(current_grid_pos, 1.0)
		valid_moves.sort_custom(func(a, b):
			return a.distance_to(home_grid) < b.distance_to(home_grid)
		)
		if not valid_moves.is_empty():
			set_move_target(valid_moves[0])
		return
	
	# Otherwise, just wander nearby
	choose_wander_move()

func choose_hunting_move() -> void:
	# TODO: Implement hunting behavior when target detection is added
	choose_wander_move()

func choose_fleeing_move() -> void:
	# TODO: Implement fleeing behavior when player detection is added
	choose_wander_move()

func get_valid_moves_in_radius(current_pos: Vector2i, max_radius: float) -> Array:
	var valid_moves = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			
			var new_pos = current_pos + Vector2i(dx, dy)
			if is_valid_position(new_pos) and new_pos.distance_to(current_pos) <= max_radius:
				valid_moves.append(new_pos)
	
	return valid_moves

func is_valid_position(grid_pos: Vector2i) -> bool:
	# Check map bounds
	if grid_pos.x < 0 or grid_pos.x >= overworld.WIDTH or grid_pos.y < 0 or grid_pos.y >= overworld.HEIGHT:
		return false
	
	# Check if position is walkable
	return true # TODO: Implement proper walkable check based on terrain

func set_move_target(grid_pos: Vector2i) -> void:
	target_position = overworld.map_to_world(grid_pos)
	last_direction = (grid_pos - overworld.world_to_map(position)).limit_length(1)
	is_moving = true
	
	# Update sprite direction
	if sprite:
		update_sprite_direction(last_direction)

func update_sprite_direction(_direction: Vector2) -> void:
	# TODO: Update sprite frame based on direction and NPC type
	pass
