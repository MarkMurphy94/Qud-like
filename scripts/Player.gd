extends CharacterBody2D

@export var move_speed: float = 200.0
@export var tile_size: int = 16
var sprite_node_pos_tween: Tween
@onready var up: RayCast2D = $up
@onready var down: RayCast2D = $down
@onready var left: RayCast2D = $left
@onready var right: RayCast2D = $right

@onready var overworld = $"../OverworldMap"
@onready var camera = $Camera2D
@onready var area_container: Node2D = $"../AreaContainer"

var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var current_local_area: Node2D = null
var map_rect = null
var in_local_area: bool = false

var overworld_tile: Vector2i
var overworld_tile_pos: Vector2

# Tile-based movement variables for overworld
# var target_position: Vector2
var is_moving: bool = false
var movement_threshold: float = 1.0

func _ready() -> void:
	# Set up player collision layers
	# collision_layer = 2 # Player is on layer 2
	# collision_mask = 1 # Player can collide with NPCs and walls (layer 1)
	# target_position = global_position
	update_camera_limits()

func _process(_delta: float) -> void:
	# Handle input for entering/exiting areas
	if Input.is_action_just_pressed("ui_accept"):
		if in_local_area:
			return_to_overworld()
		else:
			descend_to_local_area()

func _physics_process(_delta: float) -> void:
	# if not in_local_area:
	# 	if not overworld.is_walkable(new_grid_pos):
	# 		return
	if Input.is_action_just_pressed("ui_right") and !right.is_colliding():
		_move(Vector2.RIGHT)
	if Input.is_action_just_pressed("ui_left") and !left.is_colliding():
		_move(Vector2.LEFT)
	if Input.is_action_just_pressed("ui_up") and !up.is_colliding():
		_move(Vector2.UP)
	if Input.is_action_just_pressed("ui_down") and !down.is_colliding():
		_move(Vector2.DOWN)
	
	# Use Godot's built-in physics with collision detection
	move_and_slide()
	
	# Update roof visibility
	_update_roof_visibility()

func _move(dir: Vector2):
	global_position += dir * tile_size
	$Sprite2D.global_position -= dir * tile_size
	# print("current_tile:", get_current_tile())

	if sprite_node_pos_tween:
		sprite_node_pos_tween.kill()
	sprite_node_pos_tween = create_tween()
	sprite_node_pos_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sprite_node_pos_tween.tween_property($Sprite2D, "global_position", global_position, 0.185).set_trans(Tween.TRANS_SINE)

func descend_to_local_area() -> void:
	overworld_tile = Vector2i(overworld.world_to_map(global_position))
	overworld_tile_pos = global_position
	var tile_data = overworld.get_tile_data(overworld_tile)
	
	# Check if we can descend on this tile type
	if tile_data.terrain == overworld.Terrain.WATER:
		print("Can't descend on water")
		return
	
	var settlement_scene_path = overworld.settlement_at_tile(overworld_tile)
	if settlement_scene_path != "":
		area_container.set_settlement_scene(settlement_scene_path)
	else:
		# TODO: if no location already generated here, then:
		var main_game = get_parent()
		var metadata = {}
		# if main_game and "world_tile_data" in main_game:
		if main_game.world_tile_data.has(overworld_tile):
			metadata = main_game.world_tile_data[overworld_tile]
		else:
			print("Warning: No world data found for tile ", overworld_tile)
			
		area_container.set_local_area(metadata)
		print("metatada: ", metadata)
	
	await get_tree().process_frame
	map_rect = area_container.current_area.tilemaps["GROUND"].get_used_rect()
	position = get_spawn_tile()
	
	# TODO: call show_or_hide_overworld_scene()
	overworld.hide()
	in_local_area = true
	update_camera_limits()

func return_to_overworld() -> void:
	if in_local_area:
		area_container.clear_local_area_scene()
		map_rect = null
	overworld.show()
	in_local_area = false
	position = overworld_tile_pos
	update_camera_limits()

func get_spawn_tile():
	return area_container.spawn_tile.position

func find_valid_local_position() -> void:
	if not current_local_area or not current_local_area.tilemaps or not current_local_area.tilemaps.has("GROUND"):
		return
	
	# Calculate bottom center of the map
	var bottom_center = Vector2i(
		map_rect.position.x + map_rect.size.x / 2,
		map_rect.position.y + map_rect.size.y - 1
	)
	
	# Start with closest distance as infinity
	var closest_distance = INF
	var closest_valid_position = Vector2i(map_rect.position)
	var found_valid_position = false
	
	# Search all positions in the map to find the closest valid one to bottom center
	for y in map_rect.size.y:
		for x in map_rect.size.x:
			var test_pos = map_rect.position + Vector2i(x, y)
			if is_tile_within_bounds(test_pos):
				var distance = bottom_center.distance_to(test_pos)
				if distance < closest_distance:
					closest_distance = distance
					closest_valid_position = test_pos
					found_valid_position = true
	
	# Set position to the closest valid position found, or fallback to map start
	if found_valid_position:
		position = Vector2(closest_valid_position) * tile_size
	else:
		position = Vector2(map_rect.position) * tile_size

func is_tile_within_bounds(pos: Vector2i) -> bool:
	if not current_local_area or not current_local_area.tilemaps or not current_local_area.tilemaps.has("GROUND"):
		return false
	if pos.x < map_rect.position.x or pos.x >= map_rect.end.x or \
	   pos.y < map_rect.position.y or pos.y >= map_rect.end.y:
		print("Position out of bounds: ", pos)
		return false
	# print('map_rect position: ', pos)
	return current_local_area.is_walkable(pos)

func get_current_tile() -> Vector2i:
	"""Get the player's current tile position based on their world position and context."""
	if in_local_area:
		# In local area, convert position to tile coordinates
		return Vector2i(position / tile_size)
	else:
		# On overworld, use the overworld grid position
		return Vector2i(overworld.world_to_map(global_position))

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
