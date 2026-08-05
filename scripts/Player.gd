extends CharacterBody2D

# ═══════════════════════════════════════════════════════════════════════
#  BASIC PLAYER — movement, collision, camera
#
#  The world is turn-based (see TurnManager): nothing moves until the player
#  does something, and every player action lets every nearby actor act too.
#
#  The player moves one 16 px tile at a time. Two input sources feed the
#  same single-step primitive (try_step), so they can never disagree:
#    • WASD / arrow keys — hold a key to keep stepping
#    • left mouse button — walks an A* route to the clicked tile
#
#  A step is instantaneous in game-logic terms — the body teleports a whole
#  tile and the sprite tweens to catch up — so a turn never resolves halfway.
#
#  Collision is decided by the grid, not by physics overlap:
#    • terrain and props come from the world map's is_walkable()
#    • other actors come from TurnManager.actor_at()
#    • routes come from AStarGrid2D (via the PointAndClickPath overlay)
#  Physics never gets a vote, so two bodies that somehow overlap — a spawn on
#  top of an NPC, say — can always walk apart again instead of wedging.
# ═══════════════════════════════════════════════════════════════════════

@export var tile_size: int = 16
## Turn speed. TurnManager.NORMAL_SPEED (100) = one action per standard turn;
## higher means the player's actions cost less world time, so NPCs get fewer
## turns per player turn.
@export var speed: int = 100

# ── Scene references ─────────────────────────────────────────────────────
# The cross-scene ones are deliberately untyped: they are reached by path and
# resolved dynamically, so a missing node degrades to null instead of failing
# to load the script.
@onready var camera: Camera2D = $Camera2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var hud = $HUD
## Optional — the scene currently shows the static Sprite2D instead.
@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

## Supplies terrain walkability and tile↔world conversion.
@onready var world_map = get_node_or_null("../world_map")
## A* route finding plus the breadcrumb / destination visuals.
@onready var path_overlay = get_node_or_null("../PointAndClickPath")
@onready var pause_menu: Control = get_node_or_null("../CanvasLayer/pause")

# ── Movement state ───────────────────────────────────────────────────────
## A direction key pressed while a turn was resolving, replayed once it ends.
var _buffered_dir: Vector2i = Vector2i.ZERO
## Tiles still to walk on the active point-and-click route.
var _nav_path: Array[Vector2i] = []
## Thing to interact with once the active route finishes — set when the player
## clicks a chest or a dropped item that is too far away to reach right now.
var _pending_interaction: Node = null
## Tween that slides the visual sprite into the tile the body already moved to.
var _slide_tween: Tween = null

# ── Camera panning ───────────────────────────────────────────────────────
## Holding the middle mouse button drags the view around the map, the way a
## paper map is shoved across a table. Letting go leaves the view where it was
## dragged — a left click is what brings it back to the player.
var _is_panning: bool = false
## Current camera displacement from the player, in world pixels.
var _pan_offset: Vector2 = Vector2.ZERO
var _pan_recenter_tween: Tween = null
## How long the camera takes to glide back to the player on release.
const PAN_RECENTER_DURATION: float = 0.15

## Tiles searched for something to interact with, nearest first: the one the
## player stands on, then the four cardinal neighbours. Reaching diagonally
## would let the player open a chest through a wall corner.
const INTERACT_OFFSETS: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
]

## Movement actions and the tile offset each one requests.
const MOVE_ACTIONS: Dictionary = {
	&"move_up": Vector2i.UP,
	&"move_down": Vector2i.DOWN,
	&"move_left": Vector2i.LEFT,
	&"move_right": Vector2i.RIGHT,
}

# ── Local areas (not rebuilt yet) ────────────────────────────────────────
## Placeholders kept so the save system and the item/spell code below still
## work while the local-area system is rebuilt. `in_local_area` stays false,
## which short-circuits every branch that reads the others.
var in_local_area: bool = false
var overworld_tile: Vector2i = Vector2i.ZERO
var overworld_tile_pos: Vector2 = Vector2.ZERO
var current_tile: LocalMapTile = null
var map_rect = null
@onready var local_scene = get_node_or_null("../local_scene")

# ── NPC interaction ──────────────────────────────────────────────────────
var available_npcs: Array = []
var current_interacting_npc: NPC = null

# ── Stats ────────────────────────────────────────────────────────────────
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 50
var current_mana: int = 50
var max_stamina: int = 100
var current_stamina: int = 100
var gold: int = 0

## Base stats read by the combat systems.
var stats: Dictionary = {
	"strength": 12,
	"agility": 12,
	"intelligence": 10,
	"endurance": 12,
	"charisma": 10,
	"initiative": 12,
}

# ── Inventory ────────────────────────────────────────────────────────────
var inventory: Inventory = null
@export var inventory_slots: int = 20
@export var max_carry_weight: float = 100.0

## Equipment slots. Keys match ItemArmor.ArmorType names (lowercased) plus
## "right_hand" / "left_hand".
var equipped_items: Dictionary = {
	"head": null,
	"chest": null,
	"legs": null,
	"right_hand": null,
	"left_hand": null,
}

# ── Spells ───────────────────────────────────────────────────────────────
var learned_spells: Array[Spell] = []
var spell_cooldowns: Dictionary = {}   ## spell_id -> turns remaining

## Targeting state, set while a spell waits for the player to click a target.
var _is_aiming: bool = false
var _pending_spell: Spell = null
var _targeting_label: Label = null
var _reticle: Node2D = null


# region Lifecycle═══════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("Player")
	add_to_group("player")   # WorldItem looks for the lowercase name

	if hud:
		hud.pause_requested.connect(_on_pause_requested)
	TurnManager.turn_resolved.connect(_on_turn_resolved)

	_initialize_inventory()
	_setup_inventory_screen()
	_refresh_hud_bars()

	# The world map computes its bounds in its own _ready(), and the Player
	# sits earlier in the scene tree — defer anything that reads them.
	_enter_world.call_deferred()

	# --- DEBUG: learn fireball at startup ---
	var fireball: Spell = load("res://resources/spells/spell_templates/fireball_test.tres")
	if fireball:
		learn_spell(fireball)
	# ----------------------------------------


## Everything that needs the world map to have finished loading: put the
## player on the grid, clamp the camera, build the A* route grid.
func _enter_world() -> void:
	snap_to_grid()
	update_camera_limits()
	rebuild_nav_grid()
	# NPCs are spawned into local maps long after this runs, so watch the tree
	# rather than only wiring up whoever happens to exist right now.
	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)
	_connect_to_existing_npcs()


func _process(_delta: float) -> void:
	_update_path_preview()
	_keep_pan_in_bounds()

	if Input.is_action_just_pressed("ui_inventory"):
		_toggle_inventory_screen()
	if Input.is_action_just_pressed("ui_interact"):
		_try_interact()
	if Input.is_action_just_pressed("ui_descend"):
		_toggle_local_map()
	if Input.is_action_just_pressed("ui_attack"):
		attack_adjacent()
	if Input.is_action_just_pressed("ui_wait") and can_act():
		TurnManager.wait()


func _physics_process(_delta: float) -> void:
	_buffer_movement_input()
	if not TurnManager.resolving:
		_choose_next_step()


func _unhandled_input(event: InputEvent) -> void:
	# Reaching _unhandled_input already means no Control consumed the event,
	# so clicks that land on the HUD never get here.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_set_panning(event.pressed)
		get_viewport().set_input_as_handled()
		return

	if _is_panning and event is InputEventMouseMotion:
		_pan_camera((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Any left click ends a look-around and brings the view home first,
			# so the click always acts on a view centred on the player.
			_recenter_camera()
			if _is_aiming:
				_fire_pending_spell(get_global_mouse_position())
				_exit_targeting_mode()
			elif click_to_interact(get_global_mouse_position()):
				pass   # handled: opened it, or set off walking toward it
			elif not _nav_path.is_empty():
				# Clicking mid-route means "stop here", not "start a new route".
				cancel_navigation()
			else:
				navigate_to(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _is_aiming:
			_exit_targeting_mode()
			get_viewport().set_input_as_handled()
		return

	if _is_aiming and event.is_action_pressed("ui_cancel"):
		_exit_targeting_mode()
		get_viewport().set_input_as_handled()

# endregion






# region movement ═══════════════════════════════════════════════════════════════════════
#  MOVEMENT
# ═══════════════════════════════════════════════════════════════════════

## Try to act one tile in `dir`. Returns true if a turn was spent.
##
## Every movement source goes through this one gate, so keyboard and mouse
## movement obey identical rules. Walking into a hostile attacks it instead —
## bump-to-attack — while neutrals simply block (use `ui_attack` to hit those).
func try_step(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO or not can_act():
		return false

	var target_tile := get_current_tile() + dir

	# Bodies are checked before terrain so the bump reads the same whether the
	# NPC is standing on grass or in a doorway.
	var occupant: Node2D = TurnManager.actor_at(target_tile)
	if occupant != null and occupant != self:
		if is_hostile(occupant):
			_face(dir)
			return attack(occupant)
		cancel_navigation()
		return false

	if not is_tile_open(target_tile):
		return false

	_face(dir)
	_move_to_tile(target_tile)
	TurnManager.take_player_action()
	return true


## Is `node` an enemy the player may bump-attack? Openly hostile factions
## always count; so does anyone who has already picked a fight with us.
func is_hostile(node: Node) -> bool:
	if node is NPC:
		var npc: NPC = node
		if npc.state == NPC.NPCState.DEAD:
			return false
		return npc.is_hostile_toward(self)
	return false


## Put the body on `tile` immediately and let the sprite slide after it, so a
## turn is never left half-resolved.
func _move_to_tile(tile: Vector2i) -> void:
	var visual: Node2D = sprite
	if animated_sprite:
		visual = animated_sprite
	var from: Vector2 = visual.global_position if visual else Vector2.ZERO

	velocity = Vector2.ZERO
	global_position = tile_to_world(tile)
	_play_animation(&"walk")

	if visual == null:
		return
	if _slide_tween:
		_slide_tween.kill()
	visual.global_position = from
	_slide_tween = create_tween()
	_slide_tween.tween_property(visual, "global_position", global_position,
		TurnManager.STEP_DURATION).set_trans(Tween.TRANS_SINE)
	_slide_tween.finished.connect(func() -> void: _play_animation(&"idle"))


## Remember a direction key pressed while a turn was resolving so a quick tap
## is replayed afterwards rather than being swallowed.
func _buffer_movement_input() -> void:
	for action: StringName in MOVE_ACTIONS:
		if Input.is_action_just_pressed(action):
			_buffered_dir = MOVE_ACTIONS[action]
			return


## Decide what to do next. Keyboard input always wins over an active mouse
## route.
func _choose_next_step() -> void:
	var dir := _buffered_dir if _buffered_dir != Vector2i.ZERO else _held_direction()
	_buffered_dir = Vector2i.ZERO

	if dir != Vector2i.ZERO:
		cancel_navigation()
		try_step(dir)
		return

	if not _nav_path.is_empty():
		_advance_route()
		return

	# The route finished (or there never was one). Anything the player clicked
	# on to walk toward happens now, one physics frame after the last step, so
	# it never tries to spend a turn that is still resolving.
	if _pending_interaction != null:
		_resolve_pending_interaction()


## Direction of a movement key currently held down.
func _held_direction() -> Vector2i:
	for action: StringName in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			return MOVE_ACTIONS[action]
	return Vector2i.ZERO


## Is the player allowed to act right now? Only while the world is idle and
## no dialogue or full-screen UI is up — there is no "whose turn is it"
## question to ask, because the world only moves when the player does.
func can_act() -> bool:
	return not TurnManager.resolving \
		and current_interacting_npc == null \
		and not _is_ui_open()


## Terrain and static obstacles (walls, props, water). Actors are handled
## separately by TurnManager.actor_at() in try_step().
func is_tile_open(tile: Vector2i) -> bool:
	if world_map == null:
		return true
	return world_map.is_walkable(tile)

# endregion






# region nav and local map visits ═════════════════════════════════════════════════════════════════════
#  LOCAL MAP VISITS
# ═════════════════════════════════════════════════════════════════════

## Descend into (or resurface from) the local map for the overworld tile the
## player stands on. The heavy lifting lives in main_game.gd — this just asks
## the game root, which owns the maps and the per-tile seeds.
func _toggle_local_map() -> void:
	if not can_act():
		return
	var game := get_parent()
	if game == null:
		return
	if in_local_area:
		if game.has_method("exit_local_map"):
			game.exit_local_map()
	elif game.has_method("enter_local_map"):
		game.enter_local_map()

## Build a route to the clicked position and start walking it.
func navigate_to(world_pos: Vector2) -> void:
	if path_overlay == null or not can_act():
		return
	var route: Array[Vector2i] = path_overlay.get_tile_path(global_position, world_pos)
	if route.size() < 2:
		cancel_navigation()
		return
	_nav_path = route.slice(1)   # drop the tile already being stood on
	path_overlay.set_nav_destination(world_pos)


## Handle a left-click that landed on something interactable — a container, a
## dropped item. Returns true if the click was consumed.
##
## Clicking something already in reach interacts with it straight away;
## clicking something further off walks there first and interacts on arrival,
## which is the whole point of a point-and-click interface. Returns false when
## there is nothing there, letting the click fall through to plain movement.
func click_to_interact(world_pos: Vector2) -> bool:
	if not can_act():
		return false
	var tile := world_to_tile(world_pos)
	var target := interactable_at(tile)
	if target == null:
		return false

	if _tile_within_reach(tile):
		cancel_navigation()
		return interact_with(target)

	# Too far — walk up to it. Containers are solid props, so the route has to
	# stop beside them rather than on them.
	if path_overlay == null:
		return false
	var route: Array[Vector2i] = path_overlay.get_tile_path(global_position, tile_to_world(tile))
	if route.size() < 2:
		route = path_overlay.get_tile_path_adjacent(global_position, tile)
	if route.size() < 2:
		TurnManager.log_message("You can't reach that.", "info")
		return true   # consumed: the player clearly meant the object, not the floor

	cancel_navigation()
	_nav_path = route.slice(1)
	_pending_interaction = target
	path_overlay.set_nav_destination(tile_to_world(tile))
	return true


## Whatever the player can interact with on `tile`: a container first (it is
## the thing you can see), then an item lying there. Null if the tile holds
## neither.
func interactable_at(tile: Vector2i) -> Node:
	var container := ItemContainer.at(get_tree(), tile)
	if container != null:
		return container
	return _world_item_at(tile)


func _world_item_at(tile: Vector2i) -> WorldItem:
	for node in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var world_item: WorldItem = node
		if is_instance_valid(world_item) and world_to_tile(world_item.global_position) == tile:
			return world_item
	return null


## Is `tile` the player's own tile or one of its four neighbours?
func _tile_within_reach(tile: Vector2i) -> bool:
	var origin := get_current_tile()
	return INTERACT_OFFSETS.has(tile - origin)


## The tile an interactable stands on.
func _tile_of(target: Node) -> Vector2i:
	if target is ItemContainer:
		return (target as ItemContainer).tile
	return world_to_tile((target as Node2D).global_position)


## Interact with something in reach. Costs a turn. Returns true if it happened.
func interact_with(target: Node) -> bool:
	if not is_instance_valid(target) or not can_act():
		return false

	if target is ItemContainer:
		# Spend the turn before the loot screen pauses the tree, so the world
		# has already moved by the time the player is reading the contents.
		TurnManager.take_player_action()
		(target as ItemContainer).open(self)
		return true

	if target is WorldItem:
		var world_item: WorldItem = target
		var label := world_item.get_description()
		if not world_item.try_pickup(self):
			TurnManager.log_message("You cannot carry the %s." % label, "info")
			return false
		TurnManager.log_message("You pick up %s." % label, "info")
		TurnManager.take_player_action()
		return true

	return false


## Fire the interaction the player walked here for. The target may have been
## picked up en route (auto-pickup on the last step) or the route may have
## stopped short, so both are re-checked rather than assumed.
func _resolve_pending_interaction() -> void:
	var target := _pending_interaction
	_pending_interaction = null
	if not is_instance_valid(target):
		return
	if not _tile_within_reach(_tile_of(target)):
		return
	interact_with(target)


## Walk the next tile of the active route, re-checking as it goes so a route
## that has since been blocked is abandoned instead of walked into.
func _advance_route() -> void:
	var dir := _nav_path[0] - get_current_tile()
	# AStarGrid2D runs with DIAGONAL_MODE_NEVER, so every route step is one
	# cardinal tile. Anything else means the player is off-route.
	if absi(dir.x) + absi(dir.y) != 1 or not try_step(dir):
		cancel_navigation()
		return
	_nav_path.remove_at(0)
	if _nav_path.is_empty():
		path_overlay.clear_nav_destination()


func cancel_navigation() -> void:
	_nav_path.clear()
	_pending_interaction = null
	if path_overlay:
		path_overlay.clear_nav_destination()


## (Re)build the A* grid the overlay routes through. Call after anything that
## changes which tiles are walkable.
func rebuild_nav_grid() -> void:
	if path_overlay == null or world_map == null:
		return
	path_overlay.tile_size = tile_size
	path_overlay.setup_grid(world_map.bounds, is_tile_open, world_to_tile, tile_to_world)


## Refresh the hover path under the cursor, hiding it whenever a click would
## not start a route anyway.
func _update_path_preview() -> void:
	if path_overlay == null:
		return
	path_overlay.set_preview_suppressed(TurnManager.resolving or _is_panning)
	if _is_aiming or _is_panning or _is_ui_open() or get_viewport().gui_get_hovered_control() != null:
		path_overlay.clear_preview()
		path_overlay.set_interact_hover(PointAndClickPath.NO_TILE)
		return
	if not TurnManager.resolving and not _is_panning:
		var mouse := get_global_mouse_position()
		var hovered := world_to_tile(mouse)
		path_overlay.set_interact_hover(
			hovered if interactable_at(hovered) != null else PointAndClickPath.NO_TILE)
		path_overlay.update_preview(global_position, mouse)


func _is_ui_open() -> bool:
	return (inventory_screen != null and inventory_screen.visible) \
		or (spell_book_screen != null and spell_book_screen.visible) \
		or (trade_screen != null and trade_screen.visible)


## Fired once per resolved turn. Tick anything measured in turns, and abandon
## a long point-and-click route the moment something hostile turns up — walking
## blindly into an ambush is the classic roguelike death.
func _on_turn_resolved(_world_time: int) -> void:
	_tick_spell_cooldowns()
	if not _nav_path.is_empty() and _hostile_in_view():
		cancel_navigation()


func _hostile_in_view() -> bool:
	var alert_range := float(tile_size * 8)
	for npc in get_tree().get_nodes_in_group("NPCs"):
		if not is_instance_valid(npc) or not is_hostile(npc):
			continue
		if global_position.distance_to(npc.global_position) <= alert_range:
			return true
	return false

# endregion

# ═══════════════════════════════════════════════════════════════════════
#  GRID / CAMERA
# ═══════════════════════════════════════════════════════════════════════

func get_current_tile() -> Vector2i:
	return world_to_tile(global_position)


## Tile ↔ world conversion, delegated to the world map so the grid origin is
## owned in one place. Falls back to plain arithmetic in scenes with no map.
func world_to_tile(world_pos: Vector2) -> Vector2i:
	if world_map:
		return world_map.world_to_tile(world_pos)
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


func tile_to_world(tile: Vector2i) -> Vector2:
	if world_map:
		return world_map.tile_to_world(tile)
	return Vector2(tile * tile_size) + Vector2(tile_size, tile_size) * 0.5


## Line the player up exactly on a tile centre, relocating to the nearest
## walkable tile if the authored spawn point sits in water or off the map.
func snap_to_grid() -> void:
	var tile := get_current_tile()
	if world_map:
		tile = world_map.nearest_walkable(tile)
	global_position = tile_to_world(tile)
	velocity = Vector2.ZERO
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	# Entering a new map with a stale pan offset would drop the player off-screen.
	_is_panning = false
	if _pan_recenter_tween:
		_pan_recenter_tween.kill()
		_pan_recenter_tween = null
	_pan_offset = Vector2.ZERO
	if camera:
		camera.offset = Vector2.ZERO
	if sprite:
		sprite.global_position = global_position
	if animated_sprite:
		animated_sprite.global_position = global_position


## Clamp the camera to the painted extent of the world map.
func update_camera_limits() -> void:
	if camera == null or world_map == null:
		return
	var extent: Rect2 = world_map.bounds_px()
	camera.limit_left = int(extent.position.x)
	camera.limit_top = int(extent.position.y)
	camera.limit_right = int(extent.end.x)
	camera.limit_bottom = int(extent.end.y)


# ═══════════════════════════════════════════════════════════════════════
#  CAMERA PANNING
# ═══════════════════════════════════════════════════════════════════════

## Start or stop a middle-mouse drag. The view stays where it was dragged
## after the button comes up; only a left click recentres it.
func _set_panning(active: bool) -> void:
	if camera == null or _is_panning == active:
		return
	_is_panning = active
	if active:
		if _pan_recenter_tween:
			_pan_recenter_tween.kill()
			_pan_recenter_tween = null
		_pan_offset = camera.offset


## Drag the view by `screen_delta` (mouse movement in screen pixels). The view
## moves opposite to the drag so the map follows the cursor.
func _pan_camera(screen_delta: Vector2) -> void:
	if camera == null:
		return
	var zoom: Vector2 = camera.zoom
	var world_delta := Vector2(
		screen_delta.x / (zoom.x if zoom.x != 0.0 else 1.0),
		screen_delta.y / (zoom.y if zoom.y != 0.0 else 1.0))
	_pan_offset -= world_delta
	_clamp_pan_offset()
	camera.offset = _pan_offset


## Keep the panned view inside the map. Camera2D's limits clamp where the
## camera sits, but `offset` is applied on top of them and is free to wander
## off the map, so the pan is clamped by hand — against the visible rectangle,
## not the view centre, so no void is ever shown past an edge.
func _clamp_pan_offset() -> void:
	if camera == null or world_map == null:
		return
	var extent: Rect2 = world_map.bounds_px()
	var half: Vector2 = get_viewport_rect().size / camera.zoom * 0.5
	var min_centre := extent.position + half
	var max_centre := extent.end - half
	# A map smaller than the window can only ever sit centred.
	var map_centre := extent.get_center()
	if min_centre.x > max_centre.x:
		min_centre.x = map_centre.x
		max_centre.x = map_centre.x
	if min_centre.y > max_centre.y:
		min_centre.y = map_centre.y
		max_centre.y = map_centre.y
	# Measure from where the unpanned view actually is — the camera's limits have
	# already pulled it inside the map when the player stands near an edge.
	var base := Vector2(
		clampf(global_position.x, min_centre.x, max_centre.x),
		clampf(global_position.y, min_centre.y, max_centre.y))
	var centre := base + _pan_offset
	centre.x = clampf(centre.x, min_centre.x, max_centre.x)
	centre.y = clampf(centre.y, min_centre.y, max_centre.y)
	_pan_offset = centre - base


## Re-clamp a held pan as the player walks or the window resizes, so the view
## cannot drift off the map without the mouse moving.
func _keep_pan_in_bounds() -> void:
	if camera == null or _pan_offset == Vector2.ZERO:
		return
	_clamp_pan_offset()
	camera.offset = _pan_offset


## Slide the camera back onto the player.
func _recenter_camera() -> void:
	if camera == null:
		return
	if _pan_offset == Vector2.ZERO and camera.offset == Vector2.ZERO:
		return
	if _pan_recenter_tween:
		_pan_recenter_tween.kill()
	_pan_offset = Vector2.ZERO
	_pan_recenter_tween = create_tween()
	_pan_recenter_tween.tween_property(camera, "offset", Vector2.ZERO,
		PAN_RECENTER_DURATION).set_trans(Tween.TRANS_SINE)


# ═══════════════════════════════════════════════════════════════════════
#  APPEARANCE
# ═══════════════════════════════════════════════════════════════════════

## Face the direction of the last horizontal step; vertical steps keep the
## previous facing.
func _face(dir: Vector2i) -> void:
	if dir.x == 0:
		return
	var flip := dir.x < 0
	if sprite:
		sprite.flip_h = flip
	if animated_sprite:
		animated_sprite.flip_h = flip


## Play an animation only if the sprite actually has one by that name, so the
## static-sprite and animated setups can share this code.
func _play_animation(anim_name: StringName) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func _refresh_hud_bars() -> void:
	if hud == null:
		return
	hud.update_hp(current_health, max_health)
	hud.update_mp(current_mana, max_mana)
	hud.update_sp(current_stamina, max_stamina)


# ═══════════════════════════════════════════════════════════════════════
#  COMBAT
# ═══════════════════════════════════════════════════════════════════════

## Take damage from any source.
func take_damage(amount: int, source: Node2D = null) -> void:
	current_health = maxi(0, current_health - amount)
	if hud:
		hud.update_hp(current_health, max_health)
	TurnManager.log_message("You take %d damage. (%d/%d HP)"
		% [amount, current_health, max_health], "attack")

	if current_health <= 0:
		_play_animation(&"fall")
		cancel_navigation()
		TurnManager.log_message("You have been slain!", "death")
		print("Player died!")
		# TODO: game-over handling
		return

	# Being hit is reason enough to stop walking a route.
	if source != null:
		cancel_navigation()


## Melee `target`. Costs one turn. Returns true if the blow was struck.
func attack(target: Node2D) -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false

	_play_animation(&"attack")
	var damage := _melee_damage()
	target.take_damage(damage, self)

	var label: String = target.get("npc_name") if target.get("npc_name") else String(target.name)
	TurnManager.log_message("You hit %s for %d damage." % [label, damage], "attack")
	TurnManager.take_player_action()
	return true


## Explicit attack on whatever is adjacent — the way to hit a neutral, since
## bumping into one just blocks. Bound to `ui_attack`.
func attack_adjacent() -> void:
	if not can_act():
		return
	var best: Node2D = null
	var best_dist := float(tile_size) * 1.6   # one tile, including diagonals
	for npc in get_tree().get_nodes_in_group("NPCs"):
		if not is_instance_valid(npc) or npc.state == NPC.NPCState.DEAD:
			continue
		var dist := global_position.distance_to(npc.global_position)
		if dist < best_dist:
			best_dist = dist
			best = npc
	if best == null:
		TurnManager.log_message("Nothing within reach.", "info")
		return
	attack(best)


func _melee_damage() -> int:
	var weapon_bonus := 0
	var weapon = equipped_items.get("right_hand")
	if weapon == null:
		weapon = equipped_items.get("left_hand")
	if weapon != null and weapon.get("damage") != null:
		weapon_bonus = int(weapon.damage)
	return int(stats.get("strength", 12) * 0.5) + randi_range(1, 8) + weapon_bonus


# =============================
# NPC INTERACTION SYSTEM
# =============================

func _connect_to_existing_npcs() -> void:
	"""Connect to all NPCs already in the scene"""
	var npcs = get_tree().get_nodes_in_group("NPCs")
	print("npcs found: ", npcs.size())
	for npc in npcs:
		_connect_npc(npc)

## Fires for every node added anywhere in the tree. Only NPCs are of interest;
## this is what picks up NPCSpawner's runtime spawns.
func _on_tree_node_added(node: Node) -> void:
	if node is NPC:
		_connect_npc(node)

## Wire one NPC's interaction signals. Safe to call twice on the same NPC.
func _connect_npc(npc: Node) -> void:
	if not npc.has_signal("npc_interaction_available"):
		return
	if not npc.npc_interaction_available.is_connected(_on_npc_interaction_available):
		npc.npc_interaction_available.connect(_on_npc_interaction_available)
	if not npc.npc_interaction_unavailable.is_connected(_on_npc_interaction_unavailable):
		npc.npc_interaction_unavailable.connect(_on_npc_interaction_unavailable)
	# An NPC freed while still in range never emits "unavailable", which would
	# leave a dangling entry in available_npcs for every local map visited.
	if not npc.tree_exiting.is_connected(_on_npc_tree_exiting):
		npc.tree_exiting.connect(_on_npc_tree_exiting.bind(npc))

func _on_npc_tree_exiting(npc: Node) -> void:
	available_npcs.erase(npc)
	if current_interacting_npc == npc:
		current_interacting_npc = null

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

## Single interact key, resolved nearest-first: a container underfoot or
## beside you wins over dialogue, because a chest you are standing on is what
## you meant. Falls through to the NPC handler when there is nothing to open.
func _try_interact() -> void:
	if Dialogic.current_timeline != null:
		return
	if _try_open_adjacent_container():
		return
	_try_interact_with_npc()

## Open the container on the player's tile, or the first one orthogonally
## adjacent. Returns true if one was found — opening it costs a turn.
func _try_open_adjacent_container() -> bool:
	if not can_act():
		return false
	var origin := get_current_tile()
	for offset in INTERACT_OFFSETS:
		var container := ItemContainer.at(get_tree(), origin + offset)
		if container == null:
			continue
		return interact_with(container)
	return false

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

	# Connect Dialogic custom signals (e.g. "start_trade")
	if not Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.connect(_on_dialogic_signal)

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
	if Dialogic.signal_event.is_connected(_on_dialogic_signal):
		Dialogic.signal_event.disconnect(_on_dialogic_signal)
	_end_npc_interaction()

func _on_dialogic_signal(arg: String) -> void:
	"""Handle custom signals emitted from Dialogic timelines."""
	if arg == "start_trade":
		open_trade_screen(current_interacting_npc)

func open_trade_screen(npc: NPC) -> void:
	"""Open the trade screen with the given NPC."""
	if not trade_screen:
		return
	if not npc or not is_instance_valid(npc):
		push_warning("[Player] open_trade_screen called with invalid NPC")
		return
	# Ensure NPC has an inventory
	if not npc.inventory:
		npc._initialize_inventory()
	trade_screen.open_trade(self, npc)

func _on_trade_screen_closed() -> void:
	"""Called when the trade screen is closed."""
	pass

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
	if in_local_area and local_scene:
		local_scene.add_child(world_item)
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
	# Auto-add consumables to hotbar
	if hud and hud.has_method("notify_item_added"):
		hud.notify_item_added(item, quantity)

func _on_item_removed(item: Item, quantity: int) -> void:
	"""Called when an item is removed"""
	print("Removed %d x %s from inventory" % [quantity, item.get_display_name()])
	# TODO: Show UI notification

func get_inventory() -> Inventory:
	"""Get the player's inventory for external access"""
	return inventory

# =============================
# EQUIPMENT SYSTEM
# =============================

## Equip an item into its appropriate slot.
## Weapons go into right_hand (or left_hand if right_hand is occupied).
## Armor goes into the slot matching its ArmorType.
## Returns true on success.
func equip_item(item: Item, slot: String = "") -> bool:
	if item == null:
		return false
	var target_slot := slot
	if item.item_type == Item.ItemType.WEAPON:
		if target_slot == "":
			target_slot = "right_hand" if equipped_items["right_hand"] == null else "left_hand"
		if target_slot != "right_hand" and target_slot != "left_hand":
			return false
	elif item.item_type == Item.ItemType.ARMOR:
		var armor := item as ItemArmor
		if armor == null:
			return false
		if target_slot == "":
			match armor.armor_type:
				ItemArmor.ArmorType.HEAD:  target_slot = "head"
				ItemArmor.ArmorType.CHEST: target_slot = "chest"
				ItemArmor.ArmorType.LEGS, ItemArmor.ArmorType.FEET: target_slot = "legs"
				_: return false
		if not equipped_items.has(target_slot):
			return false
	else:
		return false
	# Unequip whatever is already in the slot
	if equipped_items[target_slot] != null:
		unequip_slot(target_slot)
	equipped_items[target_slot] = item
	if hud and hud.has_method("refresh_equipment_display"):
		hud.refresh_equipment_display()
	return true

## Unequip the item in the given slot and return it (or null).
func unequip_slot(slot: String) -> Item:
	if not equipped_items.has(slot):
		return null
	var item: Item = equipped_items[slot]
	equipped_items[slot] = null
	if hud and hud.has_method("refresh_equipment_display"):
		hud.refresh_equipment_display()
	return item

# =============================
# INVENTORY SCREEN
# =============================

var inventory_screen = null
var spell_book_screen = null
var trade_screen = null

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

	# Setup trade screen
	var trade_screen_scene = load("res://scenes/trade_screen.tscn")
	if trade_screen_scene:
		trade_screen = trade_screen_scene.instantiate()
		add_child(trade_screen)
		trade_screen.trade_closed.connect(_on_trade_screen_closed)
	else:
		push_error("Failed to load trade_screen.tscn")

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
	# Casting costs a turn, so it is refused mid-resolution for the same reason
	# a step is — one action per turn, no free shots.
	if not can_act():
		return

	var spell: Spell = _pending_spell

	# Consume mana and start cooldown now that we are actually firing
	current_mana = max(0, current_mana - spell.get_mana_cost())
	hud.update_mp(current_mana, max_mana)
	start_spell_cooldown(spell.id, spell.cooldown)

	# Determine which scene node should own the projectile
	var scene_parent: Node
	if in_local_area and local_scene:
		scene_parent = local_scene
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
	TurnManager.log_message("You cast %s!" % spell.get_display_name(), "spell")
	# Ranged attacks cost a turn just like a melee swing; the projectile itself
	# flies in real time as a pure visual, landing its damage when it arrives.
	TurnManager.take_player_action()



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
	# Auto-add spell to hotbar
	if hud and hud.has_method("notify_spell_learned"):
		hud.notify_spell_learned(spell)
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
	"""Put a spell on cooldown for `cooldown` turns"""
	if cooldown > 0.0:
		spell_cooldowns[spell_id] = cooldown

func _tick_spell_cooldowns() -> void:
	"""Burn one turn off every active cooldown. Driven by TurnManager."""
	for spell_id in spell_cooldowns.keys():
		spell_cooldowns[spell_id] -= 1.0
		if spell_cooldowns[spell_id] <= 0.0:
			spell_cooldowns.erase(spell_id)
