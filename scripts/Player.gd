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
@onready var hud = $HUD
@onready var pause_menu: Control = $"../CanvasLayer/pause"

var local_area_scene = preload("res://scenes/local_area_generator.tscn")
var current_local_area: Node2D = null
var map_rect = null
var in_local_area: bool = false

var overworld_tile: Vector2i
var overworld_tile_pos: Vector2
var current_tile: LocalMapTile = null

# Tile-based movement variables for overworld
# var target_position: Vector2
var is_moving: bool = false
var movement_threshold: float = 1.0

# NPC Interaction
var available_npcs: Array = []
var current_interacting_npc: NPC = null

# Player Stats and Inventory
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 50
var current_mana: int = 50
var max_stamina: int = 100
var current_stamina: int = 100
var gold: int = 0

# Inventory system
var inventory: Inventory = null
@export var inventory_slots: int = 20
@export var max_carry_weight: float = 100.0

# Spell system
var learned_spells: Array[Spell] = []  ## Array of learned Spell resources
var spell_cooldowns: Dictionary = {}  ## spell_id -> cooldown_remaining

# Targeting / aiming state (set when a spell needs a mouse-click target)
var _is_aiming: bool = false
var _pending_spell: Spell = null
var _targeting_label: Label = null
var _reticle: Node2D = null

# Point-and-click navigation
var path_overlay: Node2D = null          ## Reference to PointAndClickPath node
var _nav_path: Array[Vector2i] = []     ## Remaining tiles to walk
var _nav_active: bool = false

func _ready() -> void:
	# Set up player collision layers
	# collision_layer = 2 # Player is on layer 2
	# collision_mask = 1 # Player can collide with NPCs and walls (layer 1)
	# target_position = global_position
	add_to_group("Player")
	add_to_group("player")  # Lowercase for WorldItem detection
	update_camera_limits()
	hud.pause_requested.connect(_on_pause_requested)
	# Connect point-and-click nav overlay (scene sibling; gracefully absent)
	path_overlay = get_node_or_null("../PointAndClickPath")
	if path_overlay:
		# Defer so OverworldMap._ready() (which populates map_data) runs first
		_rebuild_nav_grid.call_deferred()
	
	# Initialize inventory
	_initialize_inventory()
	
	# Setup inventory screen
	_setup_inventory_screen()
	
	# Initialize with starting values
	hud.update_hp(current_health, max_health)
	hud.update_mp(current_mana, max_mana)
	hud.update_sp(current_stamina, max_stamina)

	# --- DEBUG: learn fireball at startup ---
	var _fireball: Spell = load("res://resources/spells/spell_templates/fireball_test.tres")
	if _fireball:
		learn_spell(_fireball)
	# ----------------------------------------

func _process(_delta: float) -> void:
	# Update spell cooldowns
	_update_spell_cooldowns(_delta)

	# Update path-overlay hover preview (skip while aiming or a UI screen is open)
	if path_overlay and not _is_aiming:
		var ui_open: bool = (inventory_screen and inventory_screen.visible) or \
					  (spell_book_screen and spell_book_screen.visible)
		if not ui_open:
			path_overlay.update_preview(global_position, get_global_mouse_position())
		else:
			path_overlay.clear_preview()

	# Handle input for entering/exiting areas
	if Input.is_action_just_pressed("ui_accept"):
		if in_local_area:
			return_to_overworld()
		else:
			descend_to_local_area()
	
	# Handle inventory screen toggle
	if Input.is_action_just_pressed("ui_inventory"):
		_toggle_inventory_screen()
	
	# Handle NPC interaction
	if Input.is_action_just_pressed("ui_interact"):
		_try_interact_with_npc()

func _physics_process(_delta: float) -> void:
	# if not in_local_area:
	# 	if not overworld.is_walkable(new_grid_pos):
	# 		return

	# Any keyboard input cancels point-and-click navigation
	var kb_pressed := (
		Input.is_action_just_pressed("ui_right") or
		Input.is_action_just_pressed("ui_left")  or
		Input.is_action_just_pressed("ui_up")    or
		Input.is_action_just_pressed("ui_down")
	)
	if kb_pressed and _nav_active:
		_nav_cancel()

	if Input.is_action_just_pressed("ui_right") and !right.is_colliding():
		_move(Vector2.RIGHT)
	if Input.is_action_just_pressed("ui_left") and !left.is_colliding():
		_move(Vector2.LEFT)
	if Input.is_action_just_pressed("ui_up") and !up.is_colliding():
		_move(Vector2.UP)
	if Input.is_action_just_pressed("ui_down") and !down.is_colliding():
		_move(Vector2.DOWN)

	# Advance point-and-click path one tile at a time (wait for sprite tween)
	if _nav_active and _nav_path.size() > 0:
		if sprite_node_pos_tween == null or not sprite_node_pos_tween.is_running():
			_nav_step()

	# Use Godot's built-in physics with collision detection
	move_and_slide()

	# Update roof visibility
	_update_roof_visibility()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _is_aiming:
				# Spell targeting: fire toward click
				_fire_pending_spell(get_global_mouse_position())
				_exit_targeting_mode()
			else:
				# Point-and-click navigation
				_on_nav_click(get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and _is_aiming:
			print("Spell targeting cancelled")
			_exit_targeting_mode()
			get_viewport().set_input_as_handled()
			return

	if _is_aiming and event.is_action_pressed("ui_cancel"):
		print("Spell targeting cancelled")
		_exit_targeting_mode()
		get_viewport().set_input_as_handled()


func _move(dir: Vector2):
	global_position += dir * tile_size
	$Sprite2D.global_position -= dir * tile_size
	# print("current_tile:", get_current_tile())

	if sprite_node_pos_tween:
		sprite_node_pos_tween.kill()
	sprite_node_pos_tween = create_tween()
	sprite_node_pos_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sprite_node_pos_tween.tween_property($Sprite2D, "global_position", global_position, 0.185).set_trans(Tween.TRANS_SINE)

# =============================
# POINT-AND-CLICK NAVIGATION
# =============================

func _on_nav_click(world_pos: Vector2) -> void:
	"""Handle a left-click: compute a path and start walking it."""
	if not path_overlay:
		return
	# Don't navigate while a UI screen is open
	var ui_open: bool = (inventory_screen and inventory_screen.visible) or \
					   (spell_book_screen and spell_book_screen.visible)
	if ui_open:
		return
	var path: Array[Vector2i] = path_overlay.get_tile_path(global_position, world_pos)
	if path.size() > 1:
		_nav_path = path.slice(1)  # Skip the tile the player is already on
		_nav_active = true
		path_overlay.set_nav_destination(world_pos)
	else:
		_nav_cancel()


func _nav_step() -> void:
	"""Advance one tile along the current nav path."""
	if _nav_path.is_empty():
		_nav_cancel()
		return

	var next_tile: Vector2i = _nav_path.pop_front()
	var curr_tile := Vector2i(
		int(floorf(global_position.x / tile_size)),
		int(floorf(global_position.y / tile_size))
	)
	var diff := next_tile - curr_tile

	# Only accept cardinal 1-tile steps (A* with DIAGONAL_MODE_NEVER guarantees this)
	if abs(diff.x) + abs(diff.y) != 1:
		_nav_cancel()
		return

	# Walkability re-check in case something changed since path was computed
	var tile_clear: bool = false
	if in_local_area and area_container.current_area:
		tile_clear = _local_area_is_walkable(area_container.current_area, next_tile)
	else:
		tile_clear = overworld.is_walkable(next_tile)

	if not tile_clear:
		_nav_cancel()
		return

	_move(Vector2(diff))

	if _nav_path.is_empty():
		_nav_active = false
		if path_overlay:
			path_overlay.clear_nav_destination()


func _nav_cancel() -> void:
	"""Stop point-and-click navigation immediately."""
	_nav_path = []
	_nav_active = false
	if path_overlay:
		path_overlay.clear_nav_destination()


func _rebuild_nav_grid() -> void:
	"""(Re)build the A* pathfinding grid for the current context."""
	if not path_overlay:
		return
	if in_local_area and area_container and area_container.current_area and map_rect:
		var area: Node2D = area_container.current_area
		path_overlay.setup_grid(
			map_rect,
			func(tile: Vector2i) -> bool: return _local_area_is_walkable(area, tile)
		)
	else:
		var ow: Node2D = overworld
		var ow_rect := Rect2i(0, 0, int(ow.WIDTH), int(ow.HEIGHT))
		path_overlay.setup_grid(
			ow_rect,
			func(tile: Vector2i) -> bool: return ow.is_walkable(tile)
		)

func _local_area_is_walkable(area: Node2D, tile: Vector2i) -> bool:
	"""Walkability check that works for both LocationGenerator subclasses
	(procedural maps) and plain settlement Node2D scenes (e.g. town_1_new.gd)."""
	# LocationGenerator subclasses expose is_walkable directly
	if area.has_method("is_walkable"):
		return area.is_walkable(tile)
	# Fallback: read tilemaps directly — blocked if there's a wall tile or no ground
	if not area.get("tilemaps"):
		return false
	var maps: Dictionary = area.tilemaps
	# A wall tile present → not walkable
	var walls = maps.get("WALLS")
	if walls and walls.get_cell_source_id(tile) != -1:
		return false
	# No ground tile → not walkable
	var ground = maps.get("GROUND")
	if ground and ground.get_cell_source_id(tile) == -1:
		return false
	return true
	
func descend_to_local_area() -> void:
	overworld_tile_pos = global_position

	# Resolve the two values we need: a scene path and/or tile metadata.
	var scene_path := ""
	var metadata: TileMetadata = null
	if current_tile:
		scene_path = current_tile.scene_path
		metadata = current_tile.tile_metadata
		overworld_tile = metadata.coords if metadata else Vector2i(overworld.world_to_map(global_position))
	else:
		overworld_tile = Vector2i(overworld.world_to_map(global_position))
		scene_path = overworld.settlement_at_tile(overworld_tile)
		metadata = get_parent().world_tile_data.get(overworld_tile)

	if scene_path == "" and metadata == null:
		push_warning("No world data for tile %s" % overworld_tile)
		return

	# Water check
	var tile_data = overworld.get_tile_data(overworld_tile)
	if tile_data.terrain == overworld.Terrain.WATER:
		print("Can't descend on water")
		return

	area_container.load_area(scene_path, metadata)

	await get_tree().process_frame
	map_rect = area_container.current_area.tilemaps["GROUND"].get_used_rect()
	position = get_spawn_tile()
	_connect_to_existing_npcs()
	
	# TODO: call show_or_hide_overworld_scene()
	overworld.hide()
	in_local_area = true
	update_camera_limits()
	_rebuild_nav_grid()

func return_to_overworld() -> void:
	if in_local_area:
		area_container.clear()
		map_rect = null
	overworld.show()
	in_local_area = false
	position = overworld_tile_pos
	update_camera_limits()
	_nav_cancel()
	_rebuild_nav_grid()

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

# =============================
# NPC INTERACTION SYSTEM
# =============================

func _connect_to_existing_npcs() -> void:
	"""Connect to all NPCs already in the scene"""
	var npcs = get_tree().get_nodes_in_group("NPCs")
	print("npcs found: ", npcs.size())
	for npc in npcs:
		if npc.has_signal("npc_interaction_available"):
			print("Player entered interaction range of %s" % (npc.npc_name if npc.npc_name else "an unnamed NPC"))
			if not npc.npc_interaction_available.is_connected(_on_npc_interaction_available):
				npc.npc_interaction_available.connect(_on_npc_interaction_available)
		if npc.has_signal("npc_interaction_unavailable"):
			if not npc.npc_interaction_unavailable.is_connected(_on_npc_interaction_unavailable):
				npc.npc_interaction_unavailable.connect(_on_npc_interaction_unavailable)

func _on_npc_interaction_available(npc: NPC) -> void:
	"""Called when an NPC becomes available for interaction"""
	if npc not in available_npcs:
		available_npcs.append(npc)
		print("NPC available for interaction: %s" % npc.npc_name if npc.npc_name else "Unnamed NPC")

func _on_npc_interaction_unavailable(npc: NPC) -> void:
	"""Called when an NPC is no longer available for interaction"""
	if npc in available_npcs:
		available_npcs.erase(npc)
		print("NPC no longer in range")

func _try_interact_with_npc() -> void:
	"""Attempt to interact with the closest available NPC"""
	# Don't interact if already in dialogue
	if Dialogic.current_timeline != null:
		return
	
	if current_interacting_npc:
		return
	
	if available_npcs.is_empty():
		print("No NPCs in range")
		return
	
	# Find the closest NPC
	var closest_npc: NPC = null
	var min_priority = INF
	
	for npc in available_npcs:
		if not is_instance_valid(npc):
			continue
		
		if not npc.can_interact():
			continue
		
		var priority = npc.get_interaction_priority()
		if priority < min_priority:
			min_priority = priority
			closest_npc = npc
	
	if closest_npc:
		_interact_with_npc(closest_npc)
	else:
		print("No valid NPCs to interact with")

func _interact_with_npc(npc: NPC) -> void:
	"""Start interaction with a specific NPC"""
	if not npc or not is_instance_valid(npc):
		return
	
	var success = npc.start_interaction(self)
	
	if success:
		current_interacting_npc = npc
		
		# Connect to dialogue signals
		if not npc.npc_dialogue_ended.is_connected(_on_npc_dialogue_ended):
			npc.npc_dialogue_ended.connect(_on_npc_dialogue_ended)
		
		# Start Dialogic timeline
		_start_dialogic_conversation(npc)
	else:
		print("Failed to start interaction with NPC")

func _start_dialogic_conversation(npc: NPC) -> void:
	"""Start a Dialogic timeline based on NPC properties"""
	# Determine which timeline to use based on NPC type, faction, or name
	var timeline_name = _get_timeline_for_npc(npc)
	
	if timeline_name == "":
		print("No dialogue timeline found for this NPC")
		timeline_name = "test_dialogic_timeline"
		# _end_npc_interaction()
		# return
	
	# Set Dialogic variables that can be used in the timeline
	# Dialogic.VAR.npc_name = npc.npc_name if npc.npc_name else "Stranger"
	# Dialogic.VAR.npc_faction = npc.faction
	# Dialogic.VAR.can_trade = npc.can_trade
	
	# Start the timeline
	Dialogic.start(timeline_name)
	
	# Connect to timeline end signal
	Dialogic.timeline_ended.connect(_on_dialogic_timeline_ended)

func _get_timeline_for_npc(npc: NPC) -> String:
	"""Determine which Dialogic timeline to use for this NPC"""
	# Priority: specific NPC name > NPC variant > NPC type > faction > default
	
	# Check if NPC has a custom timeline specified
	if npc.dialogue_tree.has("timeline"):
		return npc.dialogue_tree["timeline"]
	
	# Check by NPC name (if set)
	if npc.npc_name != "":
		var name_timeline = "npc_" + npc.npc_name.to_lower().replace(" ", "_")
		if _dialogic_timeline_exists(name_timeline):
			return name_timeline
	
	# Check by NPC variant
	if npc.npc_variant != "default":
		var variant_timeline = "npc_" + npc.npc_variant
		if _dialogic_timeline_exists(variant_timeline):
			return variant_timeline
	
	# Check by NPC type
	var type_name = MainGameState.NpcType.keys()[npc.npc_type].to_lower()
	var type_timeline = "npc_" + type_name
	if _dialogic_timeline_exists(type_timeline):
		return type_timeline
	
	# Check by faction
	var faction_timeline = "faction_" + npc.faction.to_lower()
	if _dialogic_timeline_exists(faction_timeline):
		return faction_timeline
	
	# Default generic timeline
	if _dialogic_timeline_exists("npc_default"):
		return "npc_default"
	
	return ""

func _dialogic_timeline_exists(timeline_name: String) -> bool:
	"""Check if a Dialogic timeline exists"""
	# Try to check if the timeline exists in Dialogic
	var timeline_path = "res://dialogic/timelines/" + timeline_name + ".dtl"
	return FileAccess.file_exists(timeline_path)

func _on_dialogic_timeline_ended() -> void:
	"""Called when Dialogic timeline finishes"""
	Dialogic.timeline_ended.disconnect(_on_dialogic_timeline_ended)
	_end_npc_interaction()

func _on_npc_dialogue_ended(npc: NPC) -> void:
	"""Called when NPC dialogue ends"""
	if npc.npc_dialogue_ended.is_connected(_on_npc_dialogue_ended):
		npc.npc_dialogue_ended.disconnect(_on_npc_dialogue_ended)

func _end_npc_interaction() -> void:
	"""Clean up after NPC interaction ends"""
	if current_interacting_npc and is_instance_valid(current_interacting_npc):
		current_interacting_npc.end_interaction()
		current_interacting_npc = null

func _on_pause_requested() -> void:
	var pausing := !get_tree().paused
	get_tree().paused = pausing
	if pause_menu:
		if pausing:
			pause_menu.show()
		else:
			pause_menu.hide()

# =============================
# INVENTORY SYSTEM
# =============================

func _initialize_inventory() -> void:
	"""Set up the player's inventory"""
	if not inventory:
		inventory = Inventory.new()
		inventory.max_slots = inventory_slots
		inventory.max_weight = max_carry_weight
		add_child(inventory)
		
		# Connect to inventory signals
		inventory.inventory_changed.connect(_on_inventory_changed)
		inventory.inventory_full.connect(_on_inventory_full)
		inventory.item_added.connect(_on_item_added)
		inventory.item_removed.connect(_on_item_removed)

func add_item_to_inventory(item: Item, quantity: int = 1) -> bool:
	"""Add an item to the player's inventory. Returns true if successful."""
	if not inventory:
		_initialize_inventory()
	# TODO: save map state + save game- item should not respawn when map loads again
	return inventory.add_item(item, quantity)

func remove_item_from_inventory(item_id: String, quantity: int = 1) -> int:
	"""Remove an item from inventory. Returns the actual quantity removed."""
	if not inventory:
		return 0
	
	return inventory.remove_item(item_id, quantity)

func has_item(item_id: String, quantity: int = 1) -> bool:
	"""Check if player has a specific item"""
	if not inventory:
		return false
	
	return inventory.has_item(item_id, quantity)

func pickup_item(item: Item, quantity: int = 1) -> bool:
	"""Alternative method name for compatibility with WorldItem"""
	return add_item_to_inventory(item, quantity)

func drop_item(item_id: String, quantity: int = 1) -> bool:
	"""Drop an item from inventory and spawn it in the world"""
	if not inventory:
		return false
	
	var item = inventory.get_item_by_id(item_id)
	if not item:
		return false
	
	var removed = inventory.remove_item(item_id, quantity)
	if removed > 0:
		_spawn_world_item(item, removed)
		return true
	
	return false

func _spawn_world_item(item: Item, quantity: int) -> void:
	"""Spawn an item in the world at the player's position"""
	var world_item_scene = preload("res://scenes/world_item.tscn")
	var world_item = world_item_scene.instantiate()
	world_item.item_resource = item
	world_item.quantity = quantity
	
	# Spawn slightly in front of the player
	var spawn_offset = Vector2(0, tile_size)
	world_item.global_position = global_position + spawn_offset
	
	# Add to the current scene
	if in_local_area and area_container.current_area:
		area_container.current_area.add_child(world_item)
	else:
		get_parent().add_child(world_item)
	
	print("Dropped %d x %s" % [quantity, item.get_display_name()])

# Inventory signal handlers
func _on_inventory_changed() -> void:
	"""Called when inventory contents change"""
	# Update UI if needed
	pass

func _on_inventory_full() -> void:
	"""Called when trying to add to a full inventory"""
	print("Inventory is full!")
	# TODO: Show UI notification

func _on_item_added(item: Item, quantity: int) -> void:
	"""Called when an item is successfully added"""
	print("Added %d x %s to inventory" % [quantity, item.get_display_name()])
	# TODO: Show UI notification

func _on_item_removed(item: Item, quantity: int) -> void:
	"""Called when an item is removed"""
	print("Removed %d x %s from inventory" % [quantity, item.get_display_name()])
	# TODO: Show UI notification

func get_inventory() -> Inventory:
	"""Get the player's inventory for external access"""
	return inventory

# =============================
# INVENTORY SCREEN
# =============================

var inventory_screen = null
var spell_book_screen = null

func _setup_inventory_screen():
	"""Load and setup the inventory screen"""
	var inventory_screen_scene = load("res://scenes/inventory_screen.tscn")
	if inventory_screen_scene:
		inventory_screen = inventory_screen_scene.instantiate()
		add_child(inventory_screen)
		inventory_screen.inventory_closed.connect(_on_inventory_screen_closed)
	else:
		push_error("Failed to load inventory_screen.tscn")
	
	# Setup spell book screen
	var spell_book_scene = load("res://scenes/spell_book_screen.tscn")
	if spell_book_scene:
		spell_book_screen = spell_book_scene.instantiate()
		add_child(spell_book_screen)
		spell_book_screen.spell_book_closed.connect(_on_spell_book_closed)
		spell_book_screen.spell_cast_requested.connect(_on_spell_cast_requested)
	else:
		push_error("Failed to load spell_book_screen.tscn")

func _toggle_inventory_screen():
	"""Open or close the inventory screen"""
	if not inventory_screen:
		return
	
	if inventory_screen.visible:
		inventory_screen.close_inventory()
	else:
		inventory_screen.open_inventory(inventory)

func _on_inventory_screen_closed():
	"""Called when inventory screen is closed"""
	pass


func open_spell_book():
	"""Open the spell book screen"""
	if not spell_book_screen:
		return
	
	if spell_book_screen.visible:
		spell_book_screen.close_spell_book()
	else:
		spell_book_screen.open_spell_book(self)


func _on_spell_book_closed():
	"""Called when spell book is closed"""
	pass


func _on_spell_cast_requested(spell: Spell):
	"""Called when player wants to cast a spell from spell book"""
	if not spell:
		return

	if not spell.can_cast(self):
		print("Cannot cast %s" % spell.get_display_name())
		return

	# Enter aiming/targeting mode — the spell fires on the next left-click
	_pending_spell = spell
	_is_aiming = true
	_show_targeting_label("[TARGETING] %s  |  Left-click to aim & fire  |  Right-click / ESC to cancel" \
		% spell.get_display_name())
	_spawn_reticle(spell)


func _show_targeting_label(text: String) -> void:
	"""Create (or reuse) a HUD label that tells the player they are in targeting mode."""
	if not _targeting_label:
		_targeting_label = Label.new()
		_targeting_label.add_theme_font_size_override("font_size", 13)
		_targeting_label.add_theme_color_override("font_color", Color.YELLOW)
		_targeting_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		_targeting_label.add_theme_constant_override("shadow_offset_x", 1)
		_targeting_label.add_theme_constant_override("shadow_offset_y", 1)
		# Anchor to bottom-left of the viewport via the HUD CanvasLayer
		_targeting_label.anchor_top    = 1.0
		_targeting_label.anchor_bottom = 1.0
		_targeting_label.anchor_left   = 0.0
		_targeting_label.anchor_right  = 1.0
		_targeting_label.offset_top    = -50
		_targeting_label.offset_bottom = -20
		_targeting_label.offset_left   = 10
		_targeting_label.offset_right  = -10
		hud.add_child(_targeting_label)
	_targeting_label.text = text
	_targeting_label.show()


func _exit_targeting_mode() -> void:
	"""Leave targeting mode and hide the indicator."""
	_is_aiming = false
	_pending_spell = null
	if _targeting_label:
		_targeting_label.hide()
	if _reticle and is_instance_valid(_reticle):
		_reticle.queue_free()
		_reticle = null


func _spawn_reticle(p_spell: Spell) -> void:
	"""Instantiate the targeting reticle and attach it to this node."""
	if _reticle and is_instance_valid(_reticle):
		_reticle.queue_free()
	var reticle_script: GDScript = load("res://scripts/spell_target_reticle.gd")
	_reticle = Node2D.new()
	_reticle.set_script(reticle_script)
	add_child(_reticle)
	_reticle.call("setup", p_spell)


func _fire_pending_spell(world_target: Vector2) -> void:
	"""Spawn a ProjectileSpell aimed at world_target and deduct mana/start cooldown."""
	if not _pending_spell:
		return

	var spell: Spell = _pending_spell

	# Consume mana and start cooldown now that we are actually firing
	current_mana = max(0, current_mana - spell.get_mana_cost())
	hud.update_mp(current_mana, max_mana)
	start_spell_cooldown(spell.id, spell.cooldown)

	# Determine which scene node should own the projectile
	var scene_parent: Node
	if in_local_area and area_container and area_container.current_area:
		scene_parent = area_container.current_area
	else:
		scene_parent = get_parent()

	# Instantiate and position the projectile
	var projectile_scene: PackedScene = preload("res://scenes/projectile_spell.tscn")
	var projectile: Node2D = projectile_scene.instantiate()
	scene_parent.add_child(projectile)
	projectile.global_position = global_position

	# Aim and initialise — clamp click distance to the spell's max range
	var to_target: Vector2 = world_target - global_position
	var max_range_px: float = spell.spell_range * 16.0
	var stop_px: float = minf(to_target.length(), max_range_px)
	var dir: Vector2 = to_target.normalized()
	projectile.setup(spell, self, dir, stop_px)

	print("Cast %s toward %s (damage: %d, AOE radius: %.0f px)" \
		% [spell.get_display_name(), world_target, spell.get_damage(), spell.aoe_radius * 16.0])



# =============================
# SPELL SYSTEM
# =============================

func learn_spell(spell: Spell) -> bool:
	"""Learn a new spell if not already known. Returns true if learned."""
	if not spell:
		return false
	
	# Check if already learned
	if has_spell(spell.id):
		print("You already know %s" % spell.get_display_name())
		return false
	
	# Check if requirements are met
	if not _meets_spell_requirements(spell):
		print("You don't meet the requirements to learn %s" % spell.get_display_name())
		return false
	
	# Learn the spell
	learned_spells.append(spell)
	print("Learned spell: %s" % spell.get_display_name())
	return true

func has_spell(spell_id: String) -> bool:
	"""Check if player has learned a specific spell"""
	for spell in learned_spells:
		if spell.id == spell_id:
			return true
	return false

func get_spell_by_id(spell_id: String) -> Spell:
	"""Get a learned spell by its ID"""
	for spell in learned_spells:
		if spell.id == spell_id:
			return spell
	return null

func get_learned_spells() -> Array[Spell]:
	"""Get all learned spells"""
	return learned_spells

func _meets_spell_requirements(_spell: Spell) -> bool:
	"""Check if player meets the requirements to learn a spell"""
	# For now, just return true - can be extended later
	# Could check: level, skill requirements, etc.
	return true

func get_current_mana() -> int:
	"""Get current mana value"""
	return current_mana

func get_level() -> int:
	"""Get player level - placeholder for now"""
	return 1  # TODO: Implement proper leveling system

func get_skill_level(_skill: String) -> int:
	"""Get skill level - placeholder for now"""
	return 1  # TODO: Implement proper skill system

func is_spell_on_cooldown(spell_id: String) -> bool:
	"""Check if a spell is currently on cooldown"""
	return spell_cooldowns.has(spell_id) and spell_cooldowns[spell_id] > 0.0

func start_spell_cooldown(spell_id: String, cooldown: float) -> void:
	"""Start cooldown timer for a spell"""
	spell_cooldowns[spell_id] = cooldown

func _update_spell_cooldowns(delta: float) -> void:
	"""Update all spell cooldowns (should be called in _process)"""
	for spell_id in spell_cooldowns.keys():
		spell_cooldowns[spell_id] -= delta
		if spell_cooldowns[spell_id] <= 0.0:
			spell_cooldowns.erase(spell_id)
