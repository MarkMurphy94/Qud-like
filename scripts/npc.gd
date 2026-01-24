extends CharacterBody2D
class_name NPC

# === EXPORTS AND CONFIGURATION ===
@export var move_speed: float = 50.0
@export var tile_size: int = 16
@export var grid_size: int = 16
@export var move_interval: float = 1.5 # seconds between moves
@export var move_interval_variance: float = 0.5 # random variance added to move_interval
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete
var sprite_node_pos_tween: Tween
@export var npc_type: MainGameState.NpcType = MainGameState.NpcType.PEASANT
@export var npc_variant: String = "default" # New variant property
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
var move_timer: float = 0.0
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
var player_in_interact_range: bool = false
var is_interacting: bool = false

# NPC Type-specific properties with variants
var npc_properties = {
	MainGameState.NpcType.SOLDIER: {
		"default": {
			"move_speed": 60.0,
			"sprite_region_coords": Rect2i(64, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 12, "intelligence": 8, "endurance": 14, "charisma": 8}
		},
		"archer": {
			"move_speed": 55.0,
			"sprite_region_coords": Rect2i(96, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 16, "intelligence": 10, "endurance": 12, "charisma": 8}
		},
		"knight": {
			"move_speed": 50.0,
			"sprite_region_coords": Rect2i(0, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 16, "agility": 8, "intelligence": 8, "endurance": 16, "charisma": 10}
		},
		"heavy_knight": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(32, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 18, "agility": 6, "intelligence": 8, "endurance": 18, "charisma": 10}
		},
		"crossbowman": {
			"move_speed": 52.0,
			"sprite_region_coords": Rect2i(128, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 14, "intelligence": 10, "endurance": 12, "charisma": 8}
		},
		"longswordsman": {
			"move_speed": 58.0,
			"sprite_region_coords": Rect2i(160, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 12, "intelligence": 8, "endurance": 14, "charisma": 8}
		},
		"fencer": {
			"move_speed": 65.0,
			"sprite_region_coords": Rect2i(192, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 16, "intelligence": 10, "endurance": 10, "charisma": 12}
		},
		"warrior_monk": {
			"move_speed": 62.0,
			"sprite_region_coords": Rect2i(224, 32, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 14, "intelligence": 12, "endurance": 14, "charisma": 10}
		},
		"battlemage": {
			"move_speed": 55.0,
			"sprite_region_coords": Rect2i(0, 64, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 10, "intelligence": 16, "endurance": 12, "charisma": 10}
		},
		"dwarf_warrior": {
			"move_speed": 52.0,
			"sprite_region_coords": Rect2i(32, 64, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 16, "agility": 8, "intelligence": 8, "endurance": 18, "charisma": 8}
		},
		"elven_archer": {
			"move_speed": 60.0,
			"sprite_region_coords": Rect2i(64, 64, 32, 32),
			"faction": "GUARD",
			"stats": {"strength": 8, "agility": 18, "intelligence": 12, "endurance": 10, "charisma": 12}
		}
	},
	MainGameState.NpcType.PEASANT: {
		"default": {
			"move_speed": 50.0,
			"sprite_region_coords": Rect2i(0, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 8, "agility": 10, "intelligence": 8, "endurance": 10, "charisma": 8}
		},
		"farmer": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(0, 224, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 12, "agility": 8, "intelligence": 8, "endurance": 12, "charisma": 6}
		},
		"baker": {
			"move_speed": 42.0,
			"sprite_region_coords": Rect2i(32, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 10, "agility": 8, "intelligence": 10, "endurance": 10, "charisma": 10}
		},
		"blacksmith": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(64, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 16, "agility": 8, "intelligence": 10, "endurance": 14, "charisma": 8}
		},
		"scholar": {
			"move_speed": 42.0,
			"sprite_region_coords": Rect2i(128, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 6, "agility": 8, "intelligence": 16, "endurance": 8, "charisma": 12}
		},
		"crone": {
			"move_speed": 36.0,
			"sprite_region_coords": Rect2i(192, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 6, "agility": 6, "intelligence": 14, "endurance": 8, "charisma": 10}
		},
		"hermit": {
			"move_speed": 40.0,
			"sprite_region_coords": Rect2i(224, 160, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 8, "agility": 8, "intelligence": 12, "endurance": 10, "charisma": 6}
		},
		"forester": {
			"move_speed": 52.0,
			"sprite_region_coords": Rect2i(0, 192, 32, 32),
			"faction": "CIVILIAN",
			"stats": {"strength": 12, "agility": 12, "intelligence": 10, "endurance": 12, "charisma": 8}
		}
	},
	MainGameState.NpcType.MERCHANT: {
		"default": {
			"move_speed": 42.0,
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
		}
	},
	MainGameState.NpcType.NOBLE: {
		"default": {
			"move_speed": 36.0,
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
		"priest": {
			"move_speed": 42.0,
			"sprite_region_coords": Rect2i(32, 192, 32, 32),
			"faction": "CLERGY",
			"stats": {"strength": 8, "agility": 8, "intelligence": 14, "endurance": 10, "charisma": 14}
		},
		"cleric": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(64, 192, 32, 32),
			"faction": "CLERGY",
			"stats": {"strength": 10, "agility": 8, "intelligence": 14, "endurance": 12, "charisma": 12}
		},
		"monk": {
			"move_speed": 52.0,
			"sprite_region_coords": Rect2i(96, 192, 32, 32),
			"faction": "CLERGY",
			"stats": {"strength": 10, "agility": 12, "intelligence": 12, "endurance": 12, "charisma": 10}
		},
		"druid": {
			"move_speed": 48.0,
			"sprite_region_coords": Rect2i(128, 192, 32, 32),
			"faction": "DRUID",
			"stats": {"strength": 8, "agility": 10, "intelligence": 16, "endurance": 10, "charisma": 12}
		},
		"witch": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(160, 192, 32, 32),
			"faction": "NEUTRAL",
			"stats": {"strength": 6, "agility": 10, "intelligence": 16, "endurance": 8, "charisma": 10}
		},
		"wizard": {
			"move_speed": 42.0,
			"sprite_region_coords": Rect2i(192, 192, 32, 32),
			"faction": "MAGE",
			"stats": {"strength": 6, "agility": 8, "intelligence": 18, "endurance": 8, "charisma": 12}
		},
		"warlock": {
			"move_speed": 45.0,
			"sprite_region_coords": Rect2i(224, 192, 32, 32),
			"faction": "NEUTRAL",
			"stats": {"strength": 8, "agility": 8, "intelligence": 16, "endurance": 10, "charisma": 10}
		},
		"dwarf_wizard": {
			"move_speed": 40.0,
			"sprite_region_coords": Rect2i(0, 224, 32, 32),
			"faction": "MAGE",
			"stats": {"strength": 10, "agility": 6, "intelligence": 16, "endurance": 14, "charisma": 10}
		}
	},
	MainGameState.NpcType.BANDIT: {
		"default": {
			"move_speed": 72.0,
			"move_interval": 0.3,
			"wander_radius": 10.0,
			"sprite_region_coords": Rect2i(0, 0, 32, 32),
			"behavior": "aggressive",
			"faction": "OUTLAW",
			"dialogue": "bandit_dialogue",
			"inventory_template": "bandit_items",
			"can_trade": false,
			"stats": {"strength": 12, "agility": 14, "intelligence": 8, "endurance": 10, "charisma": 6}
		},
		"thief": {
			"move_speed": 78.0,
			"sprite_region_coords": Rect2i(32, 0, 32, 32),
			"faction": "OUTLAW",
			"stats": {"strength": 8, "agility": 16, "intelligence": 12, "endurance": 8, "charisma": 10}
		},
		"elven_rogue": {
			"move_speed": 80.0,
			"sprite_region_coords": Rect2i(64, 0, 32, 32),
			"faction": "OUTLAW",
			"stats": {"strength": 8, "agility": 18, "intelligence": 14, "endurance": 8, "charisma": 12}
		},
		"barbarian": {
			"move_speed": 70.0,
			"sprite_region_coords": Rect2i(96, 0, 32, 32),
			"faction": "TRIBAL",
			"stats": {"strength": 16, "agility": 12, "intelligence": 6, "endurance": 16, "charisma": 6}
		},
		"heavy_barbarian": {
			"move_speed": 65.0,
			"sprite_region_coords": Rect2i(128, 0, 32, 32),
			"faction": "TRIBAL",
			"stats": {"strength": 18, "agility": 10, "intelligence": 6, "endurance": 18, "charisma": 6}
		},
		"hill_tribe_warrior": {
			"move_speed": 68.0,
			"sprite_region_coords": Rect2i(160, 0, 32, 32),
			"faction": "TRIBAL",
			"stats": {"strength": 14, "agility": 14, "intelligence": 8, "endurance": 14, "charisma": 6}
		},
		"dark_priest": {
			"move_speed": 52.0,
			"sprite_region_coords": Rect2i(192, 0, 32, 32),
			"faction": "CULTIST",
			"stats": {"strength": 8, "agility": 8, "intelligence": 16, "endurance": 10, "charisma": 10}
		}
	},
	MainGameState.NpcType.ANIMAL: {
		"default": {
			"move_speed": 55.0,
			"move_interval": 0.4,
			"wander_radius": 6.0,
			"sprite_region_coords": Rect2i(128, 96, 32, 32),
			"behavior": "flee_on_approach",
			"faction": "WILDLIFE",
			"dialogue": "none",
			"inventory_template": "animal_items",
			"can_trade": false,
			"stats": {"strength": 8, "agility": 14, "intelligence": 2, "endurance": 8, "charisma": 2}
		}
	},
	MainGameState.NpcType.MONSTER: {
		"default": {
			"move_speed": 65.0,
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
}

@onready var debug_container: VBoxContainer = $CanvasLayer/VBoxContainer
@onready var debug_1: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text
@onready var debug_2: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text2
@onready var debug_3: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text3


@onready var human_sprite: Sprite2D = $human_sprite
@onready var animal_sprite: Sprite2D = $animal_sprite
@onready var monster_sprite: Sprite2D = $monster_sprite
@onready var interact_radius: Area2D = $interact_radius

# === SIGNALS ===
signal npc_dialogue_started(npc)
signal npc_dialogue_ended(npc)
signal npc_state_changed(npc, old_state, new_state)
signal npc_died(npc)
signal npc_attacked(npc, target)
signal npc_item_given(npc, item, target)
signal npc_item_received(npc, item, source)
signal npc_interaction_available(npc)
signal npc_interaction_unavailable(npc)

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
	rng.randomize()
	apply_type_profile()
	set_sprite()
	# Randomize initial move timer to desync NPC movement
	move_timer = rng.randf_range(0.0, move_interval + move_interval_variance)
	# Attempt to locate player for reference (optional)
	if not player_reference:
		player_reference = _find_player()
	# Initialize schedule to nearest state
	_update_schedule(true)
	# Connect interaction signals
	if interact_radius:
		interact_radius.body_entered.connect(_on_interact_radius_body_entered)
		interact_radius.body_exited.connect(_on_interact_radius_body_exited)
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

func apply_type_profile():
	var type_data = npc_properties.get(npc_type, null)
	if not type_data:
		push_warning("No properties found for NPC type %s" % npc_type)
		return
	
	var profile = type_data.get(npc_variant, type_data.get("default", null))
	if not profile:
		push_warning("No variant '%s' found for NPC type %s" % [npc_variant, npc_type])
		return
	
	move_speed = profile.get("move_speed", move_speed)
	move_interval = profile.get("move_interval", move_interval)
	wander_radius = profile.get("wander_radius", wander_radius)
	faction = profile.get("faction", faction)
	stats = profile.get("stats", stats)
	can_trade = profile.get("can_trade", false)
	if profile.has("trade_prices"):
		trade_prices = profile.trade_prices

# Simple helper to set home/work
func set_locations(home: Vector2, work: Vector2 = Vector2.ZERO):
	home_position = home
	work_position = work if work != Vector2.ZERO else home

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

func set_sprite():
	# Hide all sprites first
	human_sprite.visible = false
	animal_sprite.visible = false
	monster_sprite.visible = false
	
	# Get the type data first
	var type_data = npc_properties.get(npc_type, null)
	if not type_data:
		push_warning("No properties found for NPC type %s" % npc_type)
		return
	
	# Get the variant profile from the type data
	var profile = type_data.get(npc_variant, type_data.get("default", null))
	if not profile:
		push_warning("No variant '%s' found for NPC type %s" % [npc_variant, npc_type])
		return
	
	# Get the sprite region from the variant profile
	if not profile.has("sprite_region_coords"):
		push_warning("NPC type %s variant '%s' has no sprite_region_coords defined" % [npc_type, npc_variant])
		return
	
	var region: Rect2i = profile.sprite_region_coords
	
	# Determine which sprite to use based on NPC type
	var active_sprite: Sprite2D = null
	match npc_type:
		MainGameState.NpcType.PEASANT, MainGameState.NpcType.SOLDIER, MainGameState.NpcType.MERCHANT, MainGameState.NpcType.NOBLE, MainGameState.NpcType.BANDIT:
			active_sprite = human_sprite
		MainGameState.NpcType.ANIMAL:
			active_sprite = animal_sprite
		MainGameState.NpcType.MONSTER:
			active_sprite = monster_sprite
	
	# Configure the sprite
	if active_sprite:
		active_sprite.visible = true
		active_sprite.region_enabled = true
		active_sprite.region_rect = region
		sprite = active_sprite
	else:
		push_warning("Could not determine sprite for NPC type %s" % npc_type)

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
	# Add variance to movement timing
	var effective_interval = move_interval + rng.randf_range(-move_interval_variance, move_interval_variance)
	if move_timer < effective_interval:
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
		if debug_container:
			debug_container.visible = false
		return
	
	# Update debug container position to follow NPC in screen space
	if debug_container:
		debug_container.visible = true
		var camera = get_viewport().get_camera_2d()
		if camera:
			var screen_pos = get_global_transform_with_canvas().origin
			debug_container.position = screen_pos + Vector2(-64, -48)
	
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
	sprite.global_position -= dir * tile_size
	sprite_node_pos_tween = create_tween()
	sprite_node_pos_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	sprite_node_pos_tween.tween_property(sprite, "global_position", global_position, 0.185).set_trans(Tween.TRANS_SINE)
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

# =============================
# INTERACTION SYSTEM
# =============================

func _on_interact_radius_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_interact_range = true
		emit_signal("npc_interaction_available", self)

func _on_interact_radius_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_interact_range = false
		if is_interacting:
			end_interaction()
		emit_signal("npc_interaction_unavailable", self)

func can_interact() -> bool:
	"""Check if this NPC can currently be interacted with"""
	return player_in_interact_range and state != NPCState.DEAD and not is_interacting

func get_interaction_priority() -> float:
	"""Returns a priority value for interaction selection (lower is higher priority)
	Used when multiple NPCs are in range - closest NPC gets priority"""
	if not player_reference or not is_instance_valid(player_reference):
		return 9999.0
	return global_position.distance_to(player_reference.global_position)

func start_interaction(interactor: Node2D) -> bool:
	"""Called when player initiates interaction with this NPC
	Returns true if interaction was successful"""
	if not can_interact():
		return false
	
	if state == NPCState.DEAD:
		return false
	
	is_interacting = true
	
	# Set NPC to interact state
	set_state(NPCState.INTERACT, {"interactor": interactor})
	
	# Face the interactor
	var dir_to_interactor = (interactor.global_position - global_position).normalized()
	last_direction = dir_to_interactor
	
	# Start dialogue
	emit_signal("npc_dialogue_started", self)
	
	# Handle different interaction types
	if can_trade:
		_start_trade_interaction(interactor)
	else:
		_start_dialogue_interaction(interactor)
	
	return true

func end_interaction() -> void:
	"""End the current interaction"""
	if not is_interacting:
		return
	
	is_interacting = false
	emit_signal("npc_dialogue_ended", self)
	
	# Return to previous state or default to wander
	if previous_state != NPCState.INTERACT:
		set_state(previous_state)
	else:
		set_state(NPCState.WANDER)

func _start_dialogue_interaction(interactor: Node2D) -> void:
	"""Handle dialogue-based interaction"""
	print("%s: Hello there!" % npc_name if npc_name else "NPC says hello!")
	# TODO: Implement actual dialogue system integration
	# For now, just print a message based on NPC type and faction
	var greeting = _get_greeting_message()
	print(greeting)

func _start_trade_interaction(interactor: Node2D) -> void:
	"""Handle trade-based interaction"""
	print("%s: Would you like to see my wares?" % npc_name if npc_name else "Merchant opens shop")
	# TODO: Implement actual trade system
	# For now, just print available items
	if store_inventory.size() > 0:
		print("Available items: %s" % store_inventory)
	else:
		print("Shop inventory is empty")

func _get_greeting_message() -> String:
	"""Generate a greeting based on NPC type and faction"""
	var greeting = ""
	
	match faction:
		"GUARD":
			greeting = "Halt! State your business."
		"CIVILIAN":
			greeting = "Good day to you, traveler."
		"MERCHANT":
			greeting = "Welcome! Looking to buy or sell?"
		"NOBLE":
			greeting = "Greetings. What brings you here?"
		"OUTLAW":
			greeting = "What do you want?"
		"MONSTER":
			greeting = "*Growls menacingly*"
		"WILDLIFE":
			greeting = "*Animal noises*"
		_:
			greeting = "..."
	
	return greeting

func interact_give_item(item: Dictionary) -> bool:
	"""Player gives an item to this NPC
	Returns true if NPC accepts the item"""
	if not is_interacting:
		return false
	
	# Check if NPC wants this item (quest logic, etc.)
	var accepts_item = _should_accept_item(item)
	
	if accepts_item:
		inventory.append(item)
		emit_signal("npc_item_received", self, item, state_data.get("interactor"))
		print("%s accepts the %s" % [npc_name if npc_name else "NPC", item.get("name", "item")])
		return true
	else:
		print("%s doesn't want that." % [npc_name if npc_name else "NPC"])
		return false

func _should_accept_item(item: Dictionary) -> bool:
	"""Determine if NPC should accept the given item"""
	# TODO: Implement quest item checking, faction preferences, etc.
	# For now, merchants accept everything, others are selective
	if can_trade:
		return true
	
	# Check quest flags for specific item requests
	if quest_flags.has("wants_item"):
		var wanted_item = quest_flags["wants_item"]
		if item.get("id") == wanted_item:
			return true
	
	return false
