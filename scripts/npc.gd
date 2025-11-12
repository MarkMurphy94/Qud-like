extends CharacterBody2D
class_name NPC

# === EXPORTS AND CONFIGURATION ===
@export var move_speed: float = 80.0
@export var tile_size: int = 16
@export var grid_size: int = 16
@export var move_interval: float = 0.5 # seconds between moves
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete
var sprite_node_pos_tween: Tween
@export var npc_type: MainGameState.NpcType = MainGameState.NpcType.PEASANT
@export var vision_range: float = 8.0 # How many tiles the NPC can see
@export var hearing_range: float = 5.0 # How many tiles the NPC can hear
@export var max_health: int = 100

@onready var up: RayCast2D = $up
@onready var down: RayCast2D = $down
@onready var left: RayCast2D = $left
@onready var right: RayCast2D = $right

# === IDENTITY AND PERSISTENCE ===
var npc_id: String = "" # Unique identifier
var npc_name: String = ""
var faction: String = "NEUTRAL" # Group this NPC belongs to
var relationships: Dictionary = {} # NPC ID or faction -> relationship value (-100 to 100)
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"endurance": 10,
	"charisma": 10
}
var inventory: Array = []
var equipped_items: Dictionary = {}
var quest_flags: Dictionary = {}
var current_health: int = max_health
var gold: int = 0

# === STATE MACHINE ===
enum NPCState {
	IDLE,
	WANDER,
	PATROL,
	WORK,
	SLEEP,
	EAT,
	INTERACT,
	COMBAT,
	FLEE,
	FOLLOW,
	DEAD
}
var state = NPCState.WANDER
var previous_state = NPCState.IDLE
var state_timer: float = 0.0
var state_data: Dictionary = {} # Additional data for current state

# === MOVEMENT AND NAVIGATION ===
# NPCs are currently restricted to local area maps only and cannot transition to overworld
var environment: Node2D # Local area map only
var rng = RandomNumberGenerator.new()
var target_position: Vector2
var is_moving: bool = false
var move_timer: float = 7.0
var last_direction: Vector2 = Vector2.ZERO
var path: Array = [] # For pathfinding
var sprite: Sprite2D
var home_position: Vector2 # The position this NPC considers "home"
var work_position: Vector2 # Where this NPC works
var wander_radius: float = 5.0 # How far from home position the NPC will wander (in tiles)
var interaction_range: float = 32.0 # Range for interacting with other NPCs

# === SCHEDULE AND ROUTINES ===
var schedule: Dictionary = {
	# Format: hour -> activity
	6: {"state": NPCState.WANDER, "location": "home", "duration": 1},
	8: {"state": NPCState.WORK, "location": "work", "duration": 8},
	17: {"state": NPCState.WANDER, "location": "town", "duration": 3},
	20: {"state": NPCState.EAT, "location": "home", "duration": 1},
	21: {"state": NPCState.IDLE, "location": "home", "duration": 1},
	22: {"state": NPCState.SLEEP, "location": "home", "duration": 8}
}
var current_activity: Dictionary = {}

# === AWARENESS AND MEMORY ===
var known_entities: Dictionary = {} # ID -> {last_seen_time, last_seen_position, attitude}
var recent_events: Array = [] # Memory of recent events
var max_memory_events: int = 10
var player_reference: Node2D = null

# === DIALOGUE AND INTERACTION ===
var dialogue_tree: Dictionary = {} # For conversation options
var dialogue_state: String = "ROOT"
var can_trade: bool = false
var store_inventory: Array = []
var trade_prices: Dictionary = {"buy_multiplier": 1.0, "sell_multiplier": 0.5}

# NPC Type-specific properties
var npc_properties = {
	MainGameState.NpcType.PEASANT: {
		"move_speed": 80.0,
		"move_interval": 0.5,
		"wander_radius": 5.0,
		"sprite_region_coords": Rect2i(0, 160, 32, 32),
		"behavior": "wander_near_home",
		"faction": "CIVILIAN",
		"dialogue": "peasant_dialogue",
		"inventory_template": "peasant_items",
		"can_trade": false,
		"stats": {"strength": 8, "agility": 10, "intelligence": 8, "endurance": 10, "charisma": 8}
	},
	MainGameState.NpcType.SOLDIER: {
		"move_speed": 100.0,
		"move_interval": 0.4,
		"wander_radius": 8.0,
		"sprite_region_coords": Rect2i(64, 32, 32, 32),
		"behavior": "patrol",
		"faction": "GUARD",
		"dialogue": "guard_dialogue",
		"inventory_template": "guard_items",
		"can_trade": false,
		"stats": {"strength": 14, "agility": 12, "intelligence": 8, "endurance": 14, "charisma": 8}
	},
	MainGameState.NpcType.MERCHANT: {
		"move_speed": 70.0,
		"move_interval": 0.6,
		"wander_radius": 3.0,
		"sprite_region_coords": Rect2i(96, 160, 32, 32),
		"behavior": "stay_near_shop",
		"faction": "MERCHANT",
		"dialogue": "merchant_dialogue",
		"inventory_template": "merchant_items",
		"can_trade": true,
		"trade_prices": {"buy_multiplier": 1.2, "sell_multiplier": 0.4},
		"stats": {"strength": 8, "agility": 8, "intelligence": 12, "endurance": 8, "charisma": 14}
	},
	MainGameState.NpcType.NOBLE: {
		"move_speed": 60.0,
		"move_interval": 0.7,
		"wander_radius": 4.0,
		"sprite_region_coords": Rect2i(160, 160, 32, 32),
		"behavior": "stay_in_manor",
		"faction": "NOBLE",
		"dialogue": "noble_dialogue",
		"inventory_template": "noble_items",
		"can_trade": false,
		"stats": {"strength": 8, "agility": 8, "intelligence": 14, "endurance": 8, "charisma": 14}
	},
	MainGameState.NpcType.BANDIT: {
		"move_speed": 120.0,
		"move_interval": 0.3,
		"wander_radius": 10.0,
		"sprite_region_coords": Rect2i(19, 0, 32, 32),
		"behavior": "aggressive",
		"faction": "OUTLAW",
		"dialogue": "bandit_dialogue",
		"inventory_template": "bandit_items",
		"can_trade": false,
		"stats": {"strength": 12, "agility": 14, "intelligence": 8, "endurance": 10, "charisma": 6}
	},
	MainGameState.NpcType.ANIMAL: {
		"move_speed": 90.0,
		"move_interval": 0.4,
		"wander_radius": 6.0,
		"sprite_region_coords": Rect2i(128, 96, 32, 32),
		"behavior": "flee_on_approach",
		"faction": "WILDLIFE",
		"dialogue": "none",
		"inventory_template": "animal_items",
		"can_trade": false,
		"stats": {"strength": 8, "agility": 14, "intelligence": 2, "endurance": 8, "charisma": 2}
	},
	MainGameState.NpcType.MONSTER: {
		"move_speed": 110.0,
		"move_interval": 0.3,
		"wander_radius": 12.0,
		"sprite_region_coords": Rect2i(128, 32, 32, 32),
		"behavior": "hunt",
		"faction": "MONSTER",
		"dialogue": "none",
		"inventory_template": "monster_items",
		"can_trade": false,
		"stats": {"strength": 16, "agility": 12, "intelligence": 6, "endurance": 14, "charisma": 2}
	}
}

@onready var debug_1: RichTextLabel = $Sprite2D/VBoxContainer/debug_text
@onready var debug_2: RichTextLabel = $Sprite2D/VBoxContainer/debug_text2
@onready var debug_3: RichTextLabel = $Sprite2D/VBoxContainer/debug_text3


# === SIGNALS ===
signal npc_dialogue_started(npc)
signal npc_dialogue_ended(npc)
signal npc_state_changed(npc, old_state, new_state)
signal npc_died(npc)
signal npc_attacked(npc, target)
signal npc_item_given(npc, item, target)
signal npc_item_received(npc, item, source)

func apply_type_profile():
	var profile = npc_properties.get(npc_type, null)
	if profile:
		move_speed = profile.move_speed if profile.has("move_speed") else move_speed
		move_interval = profile.move_interval if profile.has("move_interval") else move_interval
		wander_radius = profile.wander_radius if profile.has("wander_radius") else wander_radius
		faction = profile.faction
		stats = profile.stats
		can_trade = profile.get("can_trade", false)
		if profile.has("trade_prices"):
			trade_prices = profile.trade_prices
# Simple helper to set home/work
func set_locations(home: Vector2, work: Vector2 = Vector2.ZERO):
	home_position = home
	work_position = work if work != Vector2.ZERO else home

# =============================
# NEW AI IMPLEMENTATION SECTION
# =============================

# --- GAME TIME / SCHEDULING SUPPORT ---
var internal_time_seconds: float = 0.0 # Fallback internal clock if no global time system
var seconds_per_game_hour: float = 10.0 # Adjustable pacing (3600 for real-time hour)
var last_schedule_hour: int = -1

# --- PERCEPTION CACHES ---
var current_target: Node2D = null
var threat_source: Node2D = null
var flee_timer: float = 0.0
var combat_range: float = 32.0
var hear_event_cooldown: float = 0.0

# --- DEBUG OPTIONS ---
var show_debug: bool = true

func _ready():
	apply_type_profile()
	# Attempt to locate player for reference (optional)
	if not player_reference:
		player_reference = _find_player()
	# Initialize schedule to nearest state
	_update_schedule(true)
	set_process(true)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if state == NPCState.DEAD:
		return

	state_timer += delta
	move_timer += delta
	if hear_event_cooldown > 0:
		hear_event_cooldown -= delta

	# Update or simulate time-of-day
	internal_time_seconds += delta
	_update_schedule()
	_perception_update()
	_behavior_decision()
	_execute_state(delta)
	_update_debug()

func set_state(new_state: NPCState, data: Dictionary = {}):
	if state == new_state:
		return
	var old = state
	previous_state = state
	_exit_state(old)
	state = new_state
	state_data = data
	state_timer = 0.0
	_enter_state(new_state)
	emit_signal("npc_state_changed", self, old, new_state)

func _enter_state(s: int):
	match s:
		NPCState.WANDER:
			_choose_new_wander_target()
		NPCState.FLEE:
			flee_timer = 3.0
		NPCState.SLEEP, NPCState.EAT, NPCState.IDLE:
			velocity = Vector2.ZERO
		NPCState.WORK:
			# Move towards work position; if none fallback to home
			if work_position == Vector2.ZERO:
				work_position = home_position
		NPCState.COMBAT:
			# Ensure we still have a valid target
			if not is_instance_valid(current_target):
				current_target = player_reference

func _exit_state(_s: int):
	pass # Placeholder for future cleanup (e.g., stop tweens, release reservations)

func _update_schedule(force: bool = false):
	# Attempt to pull global hour if available; else derive from internal clock
	var hour: int = -1
	if Engine.has_singleton("MainGameState") and MainGameState.has_method("get_current_hour"):
		# If user later adds a proper method
		hour = MainGameState.get_current_hour()
	else:
		var sim_hours = int(internal_time_seconds / seconds_per_game_hour)
		hour = sim_hours % 24
	if hour == last_schedule_hour and not force:
		return
	last_schedule_hour = hour
	# Find the latest schedule entry whose hour <= current hour
	var chosen_key: int = -1
	for h in schedule.keys():
		if h <= hour and h > chosen_key:
			chosen_key = h
	if chosen_key == -1:
		return
	var entry = schedule[chosen_key]
	# Avoid re-entering same state unless forced
	if state != entry.state or force:
		set_state(entry.state, {"schedule_location": entry.location})

func _perception_update():
	# Acquire player reference if missing
	if not player_reference or not is_instance_valid(player_reference):
		player_reference = _find_player()
	if player_reference:
		var dist = global_position.distance_to(player_reference.global_position)
		if dist <= vision_range * tile_size:
			_known_entity_update("player", player_reference.global_position, _attitude_towards_player())
			# Hostile logic
			if _is_hostile_to_player():
				current_target = player_reference
			elif faction == "WILDLIFE" and dist < vision_range * 0.6 * tile_size:
				# Wildlife flees sooner
				threat_source = player_reference
				if state != NPCState.FLEE:
					set_state(NPCState.FLEE)

func _behavior_decision():
	# If fleeing and timer active keep fleeing
	if state == NPCState.FLEE:
		if flee_timer <= 0:
			set_state(NPCState.WANDER)
		return

	# Combat decisions
	if _should_enter_combat():
		if state != NPCState.COMBAT:
			set_state(NPCState.COMBAT)
		return

	# Low health flee (non-monster) condition
	if current_health < max_health * 0.25 and state != NPCState.FLEE and faction in ["CIVILIAN", "OUTLAW", "WILDLIFE"]:
		threat_source = current_target
		set_state(NPCState.FLEE)
		return

	# Schedule-determined states already handled; supplement wandering if idle
	if state in [NPCState.IDLE, NPCState.WANDER] and move_timer >= move_interval:
		_choose_new_wander_target()

func _execute_state(delta: float):
	match state:
		NPCState.WANDER:
			_move_towards_target(delta)
		NPCState.WORK:
			if work_position != Vector2.ZERO:
				target_position = work_position
				_move_towards_target(delta, true)
		NPCState.SLEEP:
			target_position = home_position
			_move_towards_target(delta, true)
		NPCState.EAT:
			target_position = home_position
			velocity = Vector2.ZERO
		NPCState.IDLE:
			velocity = Vector2.ZERO
		NPCState.COMBAT:
			_combat_update(delta)
		NPCState.FLEE:
			flee_timer -= delta
			_flee_update(delta)
		NPCState.PATROL:
			# Placeholder: treat like wander for now
			_move_towards_target(delta)
		NPCState.FOLLOW:
			_follow_update(delta)
		NPCState.INTERACT:
			velocity = Vector2.ZERO
		NPCState.DEAD:
			velocity = Vector2.ZERO

	# Apply movement
	if velocity.length() > 0.1:
		move_and_slide()

func _move_towards_target(_delta: float, arrive_idle: bool = false):
	if target_position == Vector2.ZERO:
		return
	if move_timer < move_interval:
		return
	if is_moving:
		return
	var curr_tile: Vector2i = Vector2i(global_position / tile_size)
	var target_tile: Vector2i = Vector2i(target_position / tile_size)
	if curr_tile == target_tile:
		if arrive_idle:
			set_state(NPCState.IDLE)
		return

	var delta_tile: Vector2i = target_tile - curr_tile
	var primary_dir: Vector2
	var secondary_dir: Vector2
	if abs(delta_tile.x) >= abs(delta_tile.y):
		primary_dir = Vector2.RIGHT if delta_tile.x > 0 else Vector2.LEFT
		secondary_dir = Vector2.DOWN if delta_tile.y > 0 else Vector2.UP
	else:
		primary_dir = Vector2.DOWN if delta_tile.y > 0 else Vector2.UP
		secondary_dir = Vector2.RIGHT if delta_tile.x > 0 else Vector2.LEFT

	if not _grid_try_move(primary_dir):
		_grid_try_move(secondary_dir)

func _choose_new_wander_target():
	# move_timer = 3.0
	var center = home_position if home_position != Vector2.ZERO else global_position
	var radius_pixels = wander_radius * tile_size
	var offset = Vector2(rng.randf_range(-radius_pixels, radius_pixels), rng.randf_range(-radius_pixels, radius_pixels))
	target_position = center + offset

func _combat_update(delta: float):
	if not is_instance_valid(current_target):
		set_state(NPCState.WANDER)
		return
	var dist = global_position.distance_to(current_target.global_position)
	if dist > vision_range * tile_size * 1.2:
		# Lost target
		current_target = null
		set_state(NPCState.WANDER)
		return
	if dist <= combat_range:
		# Placeholder attack logic
		velocity = Vector2.ZERO
		# Could emit npc_attacked signal periodically
	else:
		# Chase
		target_position = current_target.global_position
		_move_towards_target(delta)

func _flee_update(_delta: float):
	if not is_instance_valid(threat_source):
		set_state(NPCState.WANDER)
		return
	if is_moving:
		return
	if move_timer < move_interval:
		return
	var away = (global_position - threat_source.global_position)
	if away.length() < 1:
		away = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	var dir = _vector_to_cardinal(away)
	# Try the main flee direction, then orthogonals if blocked
	if not _grid_try_move(dir):
		var ortho = _orthogonal_dirs(dir)
		if not _grid_try_move(ortho[0]):
			_grid_try_move(ortho[1])

func _follow_update(delta: float):
	if not is_instance_valid(current_target):
		set_state(NPCState.IDLE)
		return
	target_position = current_target.global_position
	_move_towards_target(delta)

func _should_enter_combat() -> bool:
	if faction in ["CIVILIAN", "MERCHANT", "NOBLE", "WILDLIFE"]:
		return false
	if current_target and is_instance_valid(current_target):
		var dist = global_position.distance_to(current_target.global_position)
		return dist <= vision_range * tile_size
	return false

func _is_hostile_to_player() -> bool:
	# Basic faction hostility matrix (expand later)
	match faction:
		"OUTLAW", "MONSTER":
			return true
		_:
			return false

func _attitude_towards_player() -> int:
	if _is_hostile_to_player():
		return -50
	return 10

func _known_entity_update(id: String, pos: Vector2, attitude: int = 0):
	known_entities[id] = {
		"last_seen_time": internal_time_seconds,
		"last_seen_position": pos,
		"attitude": attitude
	}

func _find_player() -> Node2D:
	# Try group first
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		return players[0]
	# Fallback search by type name
	var root = get_tree().get_root()
	return root.find_child("Player", true, false)

func record_event(event: Dictionary):
	recent_events.append(event)
	while recent_events.size() > max_memory_events:
		recent_events.pop_front()

func _update_debug():
	if not show_debug:
		return
	if debug_1:
		debug_1.text = "State: %s  HP:%d/%d" % [_state_name(state), current_health, max_health]
	if debug_2:
		var hour = last_schedule_hour
		debug_2.text = "Hour:%02d Target:%s" % [hour, Vector2i(target_position)]
	if debug_3:
		var tgt = current_target if current_target else null
		debug_3.text = "Faction:%s Hostile:%s Target:%s" % [faction, str(_is_hostile_to_player()), (tgt and tgt.name) if tgt else "None"]

func _state_name(s: int) -> String:
	match s:
		NPCState.IDLE: return "IDLE"
		NPCState.WANDER: return "WANDER"
		NPCState.PATROL: return "PATROL"
		NPCState.WORK: return "WORK"
		NPCState.SLEEP: return "SLEEP"
		NPCState.EAT: return "EAT"
		NPCState.INTERACT: return "INTERACT"
		NPCState.COMBAT: return "COMBAT"
		NPCState.FLEE: return "FLEE"
		NPCState.FOLLOW: return "FOLLOW"
		NPCState.DEAD: return "DEAD"
		_: return "UNKNOWN"

func take_damage(amount: int, source: Node2D = null):
	if state == NPCState.DEAD:
		return
	current_health -= amount
	record_event({"type": "damage", "amount": amount})
	if current_health <= 0:
		current_health = 0
		set_state(NPCState.DEAD)
		emit_signal("npc_died", self)
		velocity = Vector2.ZERO
		return
	# Reaction: set combat target or flee
	if source and source != self:
		if _is_hostile_to_player() or faction in ["OUTLAW", "MONSTER", "GUARD"]:
			current_target = source
			set_state(NPCState.COMBAT)
		elif faction in ["CIVILIAN", "WILDLIFE", "MERCHANT", "NOBLE"]:
			threat_source = source
			set_state(NPCState.FLEE)

func hear_noise(source_pos: Vector2, intensity: float = 1.0):
	if intensity <= 0 or hear_event_cooldown > 0:
		return
	var dist = global_position.distance_to(source_pos)
	if dist <= hearing_range * tile_size * intensity:
		hear_event_cooldown = 1.0
		# Mild curiosity: if idle become wander towards approximate location
		if state in [NPCState.IDLE, NPCState.SLEEP, NPCState.EAT]:
			target_position = source_pos
			set_state(NPCState.WANDER)

# =============================
# GRID MOVEMENT HELPERS (RayCast2D based)
# =============================

func _get_raycast(dir: Vector2) -> RayCast2D:
	if dir == Vector2.UP:
		return up
	elif dir == Vector2.DOWN:
		return down
	elif dir == Vector2.LEFT:
		return left
	elif dir == Vector2.RIGHT:
		return right
	return null

func _grid_can_move(dir: Vector2) -> bool:
	var rc := _get_raycast(dir)
	if rc == null:
		return false
	rc.enabled = true
	rc.force_raycast_update()
	return not rc.is_colliding()

func _grid_try_move(dir: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return false
	if not _grid_can_move(dir):
		return false
	_grid_step(dir)
	return true

func _grid_step(dir: Vector2) -> void:
	# Move the body one tile and tween the sprite for a smooth slide
	is_moving = true
	move_timer = 0.0
	global_position += dir * tile_size
	if sprite_node_pos_tween:
		sprite_node_pos_tween.kill()
	$Sprite2D.global_position -= dir * tile_size
	sprite_node_pos_tween = create_tween()
	sprite_node_pos_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sprite_node_pos_tween.tween_property($Sprite2D, "global_position", global_position, 0.185).set_trans(Tween.TRANS_SINE)
	sprite_node_pos_tween.finished.connect(_on_move_tween_finished)
	is_moving = false

func _on_move_tween_finished() -> void:
	is_moving = false

func _vector_to_cardinal(v: Vector2) -> Vector2:
	if abs(v.x) > abs(v.y):
		return Vector2.RIGHT if v.x > 0.0 else Vector2.LEFT
	else:
		return Vector2.DOWN if v.y > 0.0 else Vector2.UP

func _orthogonal_dirs(dir: Vector2) -> Array:
	if dir == Vector2.LEFT or dir == Vector2.RIGHT:
		return [Vector2.UP, Vector2.DOWN]
	else:
		return [Vector2.LEFT, Vector2.RIGHT]
