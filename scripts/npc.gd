extends CharacterBody2D
class_name NPC

# === EXPORTS AND CONFIGURATION ===
@export var move_speed: float = 80.0
@export var grid_size: int = 16
@export var move_interval: float = 0.5 # seconds between moves
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete
@export var npc_type: GlobalGameState.NpcType = GlobalGameState.NpcType.PEASANT
@export var vision_range: float = 8.0 # How many tiles the NPC can see
@export var hearing_range: float = 5.0 # How many tiles the NPC can hear
@export var max_health: int = 100

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
var state = NPCState.IDLE
var previous_state = NPCState.IDLE
var state_timer: float = 0.0
var state_data: Dictionary = {} # Additional data for current state

# === MOVEMENT AND NAVIGATION ===
var environment: Node2D # Can be either overworld or local area
var environment_type: String = "local" # Can be "local" or "overworld"
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
var overworld_grid_pos: Vector2i = Vector2i(-1, -1) # Used when NPC is in a local area but needs to remember their overworld position

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
	GlobalGameState.NpcType.PEASANT: {
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
	GlobalGameState.NpcType.SOLDIER: {
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
	GlobalGameState.NpcType.MERCHANT: {
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
	GlobalGameState.NpcType.NOBLE: {
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
	GlobalGameState.NpcType.BANDIT: {
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
	GlobalGameState.NpcType.ANIMAL: {
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
	GlobalGameState.NpcType.MONSTER: {
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

@onready var debug_1 = $Sprite2D/debug_text
@onready var debug_2 = $Sprite2D/debug_text2
@onready var debug_3 = $Sprite2D/debug_text3

# === SIGNALS ===
signal npc_dialogue_started(npc)
signal npc_dialogue_ended(npc)
signal npc_state_changed(npc, old_state, new_state)
signal npc_died(npc)
signal npc_attacked(npc, target)
signal npc_item_given(npc, item, target)
signal npc_item_received(npc, item, source)

func _ready() -> void:
	rng.randomize()
	sprite = $Sprite2D
	if not sprite:
		push_error("Sprite2D node not found!")
	
	# Generate unique ID if none exists
	if npc_id == "":
		npc_id = _generate_unique_id()
	
	# Set up collision (layer 1 for NPCs)
	collision_layer = 1
	collision_mask = 1
	
	# Apply NPC type-specific properties
	var properties = npc_properties[npc_type]
	move_speed = properties["move_speed"]
	move_interval = properties["move_interval"]
	wander_radius = properties["wander_radius"]
	faction = properties["faction"]
	
	if properties.has("stats"):
		stats = properties["stats"]
	if properties.has("can_trade"):
		can_trade = properties["can_trade"]
	if properties.has("trade_prices"):
		trade_prices = properties["trade_prices"]
	
	if sprite:
		sprite.region_rect = properties["sprite_region_coords"]
	
	# Generate a random name if none was set
	if npc_name == "":
		npc_name = _generate_name()
		
	# Initialize inventory based on template
	if properties.has("inventory_template"):
		_initialize_inventory(properties["inventory_template"])
	
	# Load dialogue tree if available
	if properties.has("dialogue") and properties["dialogue"] != "none":
		_load_dialogue(properties["dialogue"])
	
	# Register with global NPC manager
	if GlobalGameState.has_method("register_npc"):
		GlobalGameState.register_npc(self)
	
	if not environment:
		set_physics_process(false)
		set_process(false)

func _generate_unique_id() -> String:
	return str(randi() % 100000) + "_" + str(Time.get_unix_time_from_system())

func _generate_name() -> String:
	var first_names = ["John", "Emma", "Bjorn", "Astrid", "Karim", "Leila", "Takeshi", "Mei", "Olga", "Diego"]
	var last_names = ["Smith", "Andersen", "Al-Farsi", "Tanaka", "Chen", "Ivanov", "Rodriguez", "Okafor", "Singh", "Müller"]
	
	var first = first_names[rng.randi() % first_names.size()]
	var last = last_names[rng.randi() % last_names.size()]
	
	return first + " " + last

func _initialize_inventory(template: String) -> void:
	# This would ideally load from a resource or database
	# For now we'll just add some placeholder items
	inventory.clear()
	
	match template:
		"peasant_items":
			inventory.append({"id": "food_bread", "name": "Bread", "type": "food", "value": 2})
			gold = rng.randi_range(1, 10)
		"guard_items":
			inventory.append({"id": "weapon_sword", "name": "Iron Sword", "type": "weapon", "value": 25})
			inventory.append({"id": "armor_chain", "name": "Chain Mail", "type": "armor", "value": 40})
			gold = rng.randi_range(10, 30)
		"merchant_items":
			# Merchants get special store inventory
			for i in range(5 + rng.randi() % 10):
				_add_random_store_item()
			gold = rng.randi_range(50, 200)
		"noble_items":
			inventory.append({"id": "jewelry_gold", "name": "Gold Necklace", "type": "jewelry", "value": 100})
			gold = rng.randi_range(100, 500)
		"bandit_items":
			inventory.append({"id": "weapon_dagger", "name": "Dagger", "type": "weapon", "value": 15})
			gold = rng.randi_range(5, 25)
		"monster_items":
			inventory.append({"id": "monster_hide", "name": "Monster Hide", "type": "material", "value": 20})
		_:
			# Default inventory
			gold = rng.randi_range(1, 5)

func _add_random_store_item() -> void:
	var item_types = ["weapon", "armor", "potion", "food", "jewelry", "book"]
	var type = item_types[rng.randi() % item_types.size()]
	var tier = rng.randi() % 3 + 1 # 1-3
	var value = (10 * tier) + rng.randi() % (10 * tier)
	
	var item = {
		"id": type + "_" + str(rng.randi() % 1000),
		"name": _generate_item_name(type, tier),
		"type": type,
		"value": value,
		"tier": tier
	}
	
	store_inventory.append(item)

func _generate_item_name(type: String, tier: int) -> String:
	var prefixes = ["", "Fine ", "Superior "]
	var names = {
		"weapon": ["Dagger", "Sword", "Axe", "Mace", "Bow"],
		"armor": ["Leather Armor", "Chain Mail", "Plate Armor", "Shield", "Helmet"],
		"potion": ["Health Potion", "Mana Potion", "Stamina Potion", "Poison", "Elixir"],
		"food": ["Bread", "Cheese", "Meat", "Fruit", "Stew"],
		"jewelry": ["Ring", "Amulet", "Bracelet", "Earrings", "Crown"],
		"book": ["Spellbook", "History Book", "Map", "Journal", "Manual"]
	}
	
	var name_options = names.get(type, ["Item"])
	var item_name = name_options[rng.randi() % name_options.size()]
	return prefixes[tier - 1] + item_name

func _load_dialogue(dialogue_template: String) -> void:
	# This would ideally load from a resource or JSON file
	# For now we'll just add some basic dialogue templates
	dialogue_tree = {
		"ROOT": {
			"text": "Greetings, traveler.",
			"options": [
				{"id": "1", "text": "Hello there.", "next": "GREETING"},
				{"id": "2", "text": "I need information.", "next": "INFO"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"GREETING": {
			"text": "How can I help you today?",
			"options": [
				{"id": "1", "text": "Tell me about yourself.", "next": "ABOUT"},
				{"id": "2", "text": "I need information.", "next": "INFO"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"ABOUT": {
			"text": "My name is " + npc_name + ". I'm just a simple person trying to get by.",
			"options": [
				{"id": "1", "text": "Tell me more about what you do.", "next": "JOB"},
				{"id": "2", "text": "Back to previous options.", "next": "GREETING"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"JOB": {
			"text": "I work as a " + GlobalGameState.NpcType.keys()[npc_type].to_lower() + " around here.",
			"options": [
				{"id": "1", "text": "Interesting. Tell me about this place.", "next": "PLACE"},
				{"id": "2", "text": "Back to previous options.", "next": "GREETING"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"PLACE": {
			"text": "This is a peaceful settlement. We try to keep to ourselves mostly.",
			"options": [
				{"id": "1", "text": "Back to previous options.", "next": "GREETING"},
				{"id": "2", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"INFO": {
			"text": "What kind of information are you looking for?",
			"options": [
				{"id": "1", "text": "Tell me about this place.", "next": "PLACE"},
				{"id": "2", "text": "Any rumors lately?", "next": "RUMORS"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"RUMORS": {
			"text": "Hmm, nothing specific comes to mind right now.",
			"options": [
				{"id": "1", "text": "Back to previous options.", "next": "GREETING"},
				{"id": "2", "text": "Goodbye.", "next": "EXIT"}
			]
		},
		"EXIT": {
			"text": "Farewell, traveler. Safe journeys.",
			"options": []
		}
	}
	
	# Add trade option for merchants
	if can_trade:
		dialogue_tree["GREETING"]["options"].insert(1, {"id": "T", "text": "I want to trade.", "next": "TRADE"})
		dialogue_tree["TRADE"] = {
			"text": "Here's what I have to offer.",
			"options": [
				{"id": "1", "text": "Show me your goods.", "next": "TRADE_BUY", "action": "open_trade"},
				{"id": "2", "text": "Back to previous options.", "next": "GREETING"},
				{"id": "3", "text": "Goodbye.", "next": "EXIT"}
			]
		}

	# Customize based on template
	match dialogue_template:
		"guard_dialogue":
			dialogue_tree["ROOT"]["text"] = "Halt. State your business."
			dialogue_tree["RUMORS"]["text"] = "Keep an eye out for bandits on the roads."
		"merchant_dialogue":
			dialogue_tree["ROOT"]["text"] = "Welcome! Looking to trade?"
			dialogue_tree["JOB"]["text"] = "I deal in all sorts of goods. Take a look at my wares!"
		"noble_dialogue":
			dialogue_tree["ROOT"]["text"] = "Yes? What is it?"
			dialogue_tree["ABOUT"]["text"] = "I am " + npc_name + ", of the noble house."
		"bandit_dialogue":
			dialogue_tree["ROOT"]["text"] = "What do you want? Make it quick."
			dialogue_tree["RUMORS"]["text"] = "I might know something... for a price."

func initialize(area_map: Node2D, start_pos: Vector2 = Vector2.ZERO, env_type: String = "local") -> void:
	environment = area_map
	environment_type = env_type
	
	# Determine if this is an overworld or local area based on the map's properties
	if area_map.has_method("world_to_map"):
		environment_type = "overworld"
	
	if start_pos != Vector2.ZERO:
		position = start_pos
		home_position = start_pos
	else:
		# Find valid starting position
		var found = false
		var width = environment.WIDTH if environment.has_method("get_tile_data") || environment.has_method("is_walkable") else 80
		var height = environment.HEIGHT if environment.has_method("get_tile_data") || environment.has_method("is_walkable") else 80
		
		for _i in 100:
			var x = rng.randi_range(0, width - 1)
			var y = rng.randi_range(0, height - 1)
			var grid_pos = Vector2i(x, y)
			
			if is_valid_position(grid_pos):
				if environment_type == "overworld":
					position = environment.map_to_world(grid_pos)
				else:
					position = Vector2(grid_pos) * GlobalGameState.TILE_SIZE
				
				home_position = position
				found = true
				break
		
		if not found:
			push_error("Could not find valid starting position for NPC")
			queue_free()
			return
	
	# Set work position (can be overridden later)
	work_position = home_position
	
	# Enable processing
	set_physics_process(true)
	set_process(true)
	
	# Start initial state
	_change_state(NPCState.IDLE)

func _process(delta: float) -> void:
	# Update state timer
	state_timer += delta
	
	# Process the current state
	match state:
		NPCState.IDLE:
			_process_idle_state(delta)
		NPCState.WANDER:
			_process_wander_state(delta)
		NPCState.PATROL:
			_process_patrol_state(delta)
		NPCState.WORK:
			_process_work_state(delta)
		NPCState.SLEEP:
			_process_sleep_state(delta)
		NPCState.EAT:
			_process_eat_state(delta)
		NPCState.INTERACT:
			_process_interact_state(delta)
		NPCState.COMBAT:
			_process_combat_state(delta)
		NPCState.FLEE:
			_process_flee_state(delta)
		NPCState.FOLLOW:
			_process_follow_state(delta)
		NPCState.DEAD:
			_process_dead_state(delta)
	
	# Check for state transitions
	_check_state_transitions(delta)
	
	# Check for player detection
	_check_awareness(delta)

func _physics_process(delta: float) -> void:
	if is_moving and state != NPCState.DEAD:
		if path.size() > 0:
			# Follow path if we have one
			_follow_path(delta)
		else:
			# Direct movement to target
			var move_direction = (target_position - position).normalized()
			velocity = move_direction * move_speed
			
			if position.distance_to(target_position) < movement_threshold:
				position = target_position
				is_moving = false
			else:
				move_and_slide()

# === STATE MACHINE METHODS ===

func _change_state(new_state: NPCState) -> void:
	if state == new_state:
		return
		
	var old_state = state
	previous_state = state
	state = new_state
	state_timer = 0.0
	
	# Handle state entry actions
	match new_state:
		NPCState.IDLE:
			_enter_idle_state()
		NPCState.WANDER:
			_enter_wander_state()
		NPCState.PATROL:
			_enter_patrol_state()
		NPCState.WORK:
			_enter_work_state()
		NPCState.SLEEP:
			_enter_sleep_state()
		NPCState.EAT:
			_enter_eat_state()
		NPCState.INTERACT:
			_enter_interact_state()
		NPCState.COMBAT:
			_enter_combat_state()
		NPCState.FLEE:
			_enter_flee_state()
		NPCState.FOLLOW:
			_enter_follow_state()
		NPCState.DEAD:
			_enter_dead_state()
	
	# Emit state change signal
	emit_signal("npc_state_changed", self, old_state, new_state)
	print("npc_state_changed: ", npc_name, " ", old_state, " ", new_state)
	debug_1.text = npc_name
	debug_2.text = str(npc_type)
	debug_3.text = "State: " + str(new_state)

func _check_state_transitions(_delta: float) -> void:
	# Check for global transitions that can happen in any state
	if state != NPCState.DEAD:
		# Check if health depleted
		if current_health <= 0:
			_change_state(NPCState.DEAD)
			return
			
		# Check for threats
		var threat = _get_nearest_threat()
		if threat and state != NPCState.COMBAT and state != NPCState.FLEE:
			if _should_fight(threat):
				state_data["target"] = threat
				_change_state(NPCState.COMBAT)
			else:
				state_data["threat"] = threat
				_change_state(NPCState.FLEE)
			return
	
	# Check schedule transitions
	var current_hour = _get_current_hour()
	if _should_change_scheduled_activity(current_hour):
		var activity = _get_activity_for_hour(current_hour)
		if activity:
			current_activity = activity
			var new_state = activity.get("state", NPCState.IDLE)
			_change_state(new_state)
			return
	
	# State-specific transitions
	match state:
		NPCState.IDLE:
			if state_timer > 3.0 and rng.randf() < 0.3:
				_change_state(NPCState.WANDER)
		
		NPCState.WANDER:
			if state_timer > 30.0:
				_change_state(NPCState.IDLE)
		
		NPCState.PATROL:
			# Continue patrolling indefinitely unless interrupted
			pass
		
		NPCState.WORK:
			# Work until schedule changes
			pass
		
		NPCState.SLEEP:
			# Sleep until schedule changes
			pass
		
		NPCState.EAT:
			if state_timer > 5.0:
				_change_state(NPCState.IDLE)
		
		NPCState.INTERACT:
			if state_timer > 10.0:
				_change_state(previous_state)
		
		NPCState.COMBAT:
			if not state_data.has("target") or not is_instance_valid(state_data["target"]):
				_change_state(NPCState.IDLE)
		
		NPCState.FLEE:
			if state_timer > 10.0 or (state_data.has("threat") and not is_instance_valid(state_data["threat"])):
				_change_state(NPCState.IDLE)
		
		NPCState.FOLLOW:
			if not state_data.has("follow_target") or not is_instance_valid(state_data["follow_target"]):
				_change_state(NPCState.IDLE)

func _get_current_hour() -> int:
	# This would connect to a global time system
	# For now, just return a placeholder value or simulated time
	if GlobalGameState.has_method("get_current_hour"):
		return GlobalGameState.get_current_hour()
	return 12 # Default to noon

func _should_change_scheduled_activity(current_hour: int) -> bool:
	# Check if we should start a new scheduled activity
	if not current_activity or current_activity.size() == 0:
		return true
		
	if schedule.has(current_hour) and current_activity != schedule[current_hour]:
		return true
		
	return false

func _get_activity_for_hour(hour: int) -> Dictionary:
	# Get the activity for the current hour, or the most recent activity
	if schedule.has(hour):
		return schedule[hour]
	
	var last_hour = 0
	for schedule_hour in schedule.keys():
		if schedule_hour <= hour and schedule_hour > last_hour:
			last_hour = schedule_hour
	
	if last_hour > 0:
		return schedule[last_hour]
	
	return {}

func _get_nearest_threat() -> Node2D:
	# This would scan for hostile entities nearby
	# var threats = []
	# For now, just return null (no threats)
	return null

func _should_fight(_threat: Node2D) -> bool:
	# Determine if this NPC should fight the threat or flee
	# Based on NPC type, health, etc.
	match npc_type:
		GlobalGameState.NpcType.SOLDIER, GlobalGameState.NpcType.BANDIT, GlobalGameState.NpcType.MONSTER:
			return true
		GlobalGameState.NpcType.ANIMAL:
			return current_health > max_health * 0.8 # Animals fight if healthy
		_:
			return false # Other NPCs prefer to flee

# === STATE PROCESSING METHODS ===

func _enter_idle_state() -> void:
	is_moving = false
	# Could play idle animation here

func _process_idle_state(_delta: float) -> void:
	# Just stand around
	pass

func _enter_wander_state() -> void:
	# Set up wander behavior
	move_timer = 0.0

func _process_wander_state(delta: float) -> void:
	if not is_moving:
		move_timer += delta
		if move_timer >= move_interval:
			move_timer = 0.0
			choose_wander_move()

func _enter_patrol_state() -> void:
	# Set up patrol behavior
	move_timer = 0.0
	if not state_data.has("patrol_points"):
		# Create patrol route if none exists
		_generate_patrol_route()

func _process_patrol_state(delta: float) -> void:
	if not is_moving:
		move_timer += delta
		if move_timer >= move_interval:
			move_timer = 0.0
			choose_patrol_move()

func _generate_patrol_route() -> void:
	# Generate a patrol route around the NPC's area
	var patrol_points = []
	var center = GlobalGameState.world_to_map(home_position)
	
	for i in range(4): # Create a square patrol route
		var angle = i * PI / 2 # 0, 90, 180, 270 degrees
		var distance = wander_radius
		var point = center + Vector2(cos(angle), sin(angle)) * distance
		patrol_points.append(Vector2i(point))
	
	state_data["patrol_points"] = patrol_points
	state_data["current_patrol_point"] = 0

func _enter_work_state() -> void:
	# Go to work location
	_move_to_position(work_position)

func _process_work_state(_delta: float) -> void:
	# If we're at the work position, just stay there
	# Otherwise, continue moving to it
	if not is_moving and position.distance_to(work_position) > grid_size:
		_move_to_position(work_position)

func _enter_sleep_state() -> void:
	# Go to bed at home
	_move_to_position(home_position)

func _process_sleep_state(_delta: float) -> void:
	# Just sleep
	pass

func _enter_eat_state() -> void:
	# Find a place to eat
	pass

func _process_eat_state(_delta: float) -> void:
	# Eating animation/behavior
	pass

func _enter_interact_state() -> void:
	# Started interaction with someone
	is_moving = false

func _process_interact_state(_delta: float) -> void:
	# Handle interaction
	pass

func _enter_combat_state() -> void:
	# Prepare for combat
	if state_data.has("target") and is_instance_valid(state_data["target"]):
		_move_to_position(state_data["target"].position)

func _process_combat_state(delta: float) -> void:
	# Handle combat behavior
	if state_data.has("target") and is_instance_valid(state_data["target"]):
		var target = state_data["target"]
		
		# If target moved, update our movement
		if not is_moving and position.distance_to(target.position) > interaction_range:
			_move_to_position(target.position)
		
		# Attack if in range
		if position.distance_to(target.position) <= interaction_range:
			state_data["attack_timer"] = state_data.get("attack_timer", 0.0) + delta
			if state_data["attack_timer"] >= 1.0: # Attack once per second
				state_data["attack_timer"] = 0.0
				_attack_target(target)

func _attack_target(target: Node2D) -> void:
	# Calculate damage based on stats
	var damage = stats["strength"] / 2 + rng.randi_range(1, 6)
	
	# Apply damage to target
	if target.has_method("take_damage"):
		target.take_damage(damage, self)
	
	# Emit attack signal
	emit_signal("npc_attacked", self, target)

func take_damage(amount: int, attacker: Node2D = null) -> void:
	current_health -= amount
	
	# Remember the attacker
	if attacker:
		_remember_entity(attacker, "HOSTILE")
		
	# Maybe play hurt animation/sound
	
	if current_health <= 0:
		_change_state(NPCState.DEAD)

func _enter_flee_state() -> void:
	# Run away from threat
	if state_data.has("threat") and is_instance_valid(state_data["threat"]):
		var flee_direction = position - state_data["threat"].position
		var flee_position = position + flee_direction.normalized() * (wander_radius * grid_size)
		_move_to_position(flee_position)

func _process_flee_state(delta: float) -> void:
	# Keep running away if threat still exists
	if state_data.has("threat") and is_instance_valid(state_data["threat"]):
		var threat = state_data["threat"]
		
		# Update flee direction every few seconds
		state_data["flee_timer"] = state_data.get("flee_timer", 0.0) + delta
		if state_data["flee_timer"] >= 2.0:
			state_data["flee_timer"] = 0.0
			var flee_direction = position - threat.position
			var flee_position = position + flee_direction.normalized() * (wander_radius * grid_size)
			_move_to_position(flee_position)

func _enter_follow_state() -> void:
	# Start following target
	if state_data.has("follow_target") and is_instance_valid(state_data["follow_target"]):
		_move_to_position(state_data["follow_target"].position)

func _process_follow_state(delta: float) -> void:
	# Keep following target
	if state_data.has("follow_target") and is_instance_valid(state_data["follow_target"]):
		var target = state_data["follow_target"]
		
		# Update movement every second
		state_data["follow_timer"] = state_data.get("follow_timer", 0.0) + delta
		if state_data["follow_timer"] >= 1.0:
			state_data["follow_timer"] = 0.0
			if position.distance_to(target.position) > grid_size * 2:
				_move_to_position(target.position)

func _enter_dead_state() -> void:
	# Die
	is_moving = false
	velocity = Vector2.ZERO
	
	# Maybe play death animation
	
	# Disable collision
	collision_layer = 0
	collision_mask = 0
	
	# Emit death signal
	emit_signal("npc_died", self)

func _process_dead_state(_delta: float) -> void:
	# Stay dead
	pass

# === MOVEMENT AND PATHFINDING ===

func _move_to_position(world_pos: Vector2) -> void:
	var grid_pos: Vector2i
	
	if environment_type == "overworld":
		if environment.has_method("world_to_map"):
			grid_pos = GlobalGameState.world_to_map(world_pos)
		else:
			grid_pos = Vector2i(world_pos / GlobalGameState.TILE_SIZE)
	else: # Local area
		grid_pos = Vector2i(world_pos / GlobalGameState.TILE_SIZE)
	
	# Eventually implement A* pathfinding here
	# For now, just set direct target
	set_move_target(grid_pos)

func _follow_path(_delta: float) -> void:
	if path.size() == 0:
		is_moving = false
		return
		
	var next_point = path[0]
	var move_direction = (next_point - position).normalized()
	velocity = move_direction * move_speed
	
	if position.distance_to(next_point) < movement_threshold:
		# Reached waypoint
		path.remove_at(0)
		if path.size() == 0:
			is_moving = false
	else:
		move_and_slide()

# === AWARENESS AND PERCEPTION ===

func _check_awareness(_delta: float) -> void:
	# Check for entities in vision and hearing range
	# Find the player if they're nearby
	var player = _find_player()
	if player:
		var distance = position.distance_to(player.position) / grid_size
		
		# Visual detection
		if distance <= vision_range:
			_on_player_spotted(player)
			
		# Hearing detection (simpler than vision)
		elif distance <= hearing_range:
			_on_player_heard(player)

func _find_player() -> Node2D:
	# Get the player reference
	if player_reference and is_instance_valid(player_reference):
		return player_reference
		
	# Try to find player in the scene
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_reference = players[0]
		return player_reference
		
	return null

func _on_player_spotted(player: Node2D) -> void:
	# React to seeing the player
	_remember_entity(player, "NEUTRAL")
	
	# Different reactions based on NPC type
	match npc_properties[npc_type]["behavior"]:
		"aggressive", "hunt":
			if state != NPCState.COMBAT and state != NPCState.DEAD:
				state_data["target"] = player
				_change_state(NPCState.COMBAT)
		"flee_on_approach":
			if state != NPCState.FLEE and state != NPCState.DEAD:
				state_data["threat"] = player
				_change_state(NPCState.FLEE)
		_:
			# Just acknowledge the player
			pass

func _on_player_heard(player: Node2D) -> void:
	# React to hearing the player
	_remember_entity(player, "NEUTRAL")
	
	# Maybe look in that direction or become alert

func _remember_entity(entity: Node2D, attitude: String) -> void:
	# Add to known entities
	var entity_id = entity.get("npc_id") if entity.has("npc_id") else str(entity)
	
	known_entities[entity_id] = {
		"entity": entity,
		"last_seen_time": _get_current_hour(),
		"last_seen_position": entity.position,
		"attitude": attitude
	}
	
	# Add to recent events
	var event = {
		"type": "entity_spotted",
		"entity": entity,
		"time": _get_current_hour(),
		"position": entity.position
	}
	
	_add_memory_event(event)

func _add_memory_event(event: Dictionary) -> void:
	recent_events.append(event)
	if recent_events.size() > max_memory_events:
		recent_events.remove_at(0) # Remove oldest event

# === DIALOGUE AND INTERACTION ===

func start_dialogue(player_node: Node2D) -> void:
	if state == NPCState.DEAD:
		return
		
	# Remember the player
	_remember_entity(player_node, "NEUTRAL")
	
	# Switch to interact state
	state_data["dialogue_partner"] = player_node
	_change_state(NPCState.INTERACT)
	
	# Reset dialogue state
	dialogue_state = "ROOT"
	
	# Emit dialogue started signal
	emit_signal("npc_dialogue_started", self)
	
	# Return initial dialogue
	return get_current_dialogue()

func get_current_dialogue() -> Dictionary:
	if dialogue_tree.has(dialogue_state):
		return dialogue_tree[dialogue_state]
	return {"text": "...", "options": []}

func process_dialogue_choice(choice_id: String) -> Dictionary:
	if not dialogue_tree.has(dialogue_state):
		return {"text": "Error in dialogue system.", "options": []}
		
	var options = dialogue_tree[dialogue_state].get("options", [])
	for option in options:
		if option["id"] == choice_id:
			# Check if option has an action
			if option.has("action"):
				_execute_dialogue_action(option["action"])
				
			# Move to next dialogue state
			dialogue_state = option["next"]
			return get_current_dialogue()
			
	return {"text": "Invalid choice.", "options": []}

func _execute_dialogue_action(action: String) -> void:
	match action:
		"open_trade":
			# Trigger trade UI
			pass
		"give_quest":
			# Give a quest to the player
			pass
		"end_dialogue":
			emit_signal("npc_dialogue_ended", self)
		_:
			# Unknown action
			pass

# === TRADE AND ECONOMY ===

func get_trade_inventory() -> Array:
	return store_inventory if can_trade else []

func get_buy_price(item: Dictionary) -> int:
	return int(item["value"] * trade_prices["buy_multiplier"])

func get_sell_price(item: Dictionary) -> int:
	return int(item["value"] * trade_prices["sell_multiplier"])

func buy_item_from_npc(item_index: int) -> Dictionary:
	if not can_trade or item_index >= store_inventory.size():
		return {"success": false, "message": "Item not available"}
		
	var item = store_inventory[item_index]
	var price = get_buy_price(item)
	
	# This would check if player has enough gold
	# For now just return the result
	return {
		"success": true,
		"item": item,
		"price": price,
		"message": "You bought " + item["name"] + " for " + str(price) + " gold."
	}

func sell_item_to_npc(item: Dictionary) -> Dictionary:
	if not can_trade:
		return {"success": false, "message": "This NPC doesn't trade"}
		
	var price = get_sell_price(item)
	
	# Check if NPC has enough gold
	if gold < price:
		return {"success": false, "message": npc_name + " doesn't have enough gold."}
		
	# Transaction successful
	gold -= price
	
	return {
		"success": true,
		"price": price,
		"message": "You sold " + item["name"] + " for " + str(price) + " gold."
	}

# === SERIALIZATION AND PERSISTENCE ===

func save_data() -> Dictionary:
	var save_dict = {
		"npc_id": npc_id,
		"npc_name": npc_name,
		"npc_type": npc_type,
		"position_x": position.x,
		"position_y": position.y,
		"home_x": home_position.x,
		"home_y": home_position.y,
		"work_x": work_position.x,
		"work_y": work_position.y,
		"current_health": current_health,
		"state": state,
		"gold": gold,
		"faction": faction,
		"stats": stats,
		"inventory": inventory,
		"relationships": relationships,
		"quest_flags": quest_flags
	}
	return save_dict

func load_data(data: Dictionary) -> void:
	if data.has("npc_id"):
		npc_id = data["npc_id"]
	if data.has("npc_name"):
		npc_name = data["npc_name"]
	if data.has("npc_type"):
		npc_type = data["npc_type"]
	if data.has("position_x") and data.has("position_y"):
		position = Vector2(data["position_x"], data["position_y"])
	if data.has("home_x") and data.has("home_y"):
		home_position = Vector2(data["home_x"], data["home_y"])
	if data.has("work_x") and data.has("work_y"):
		work_position = Vector2(data["work_x"], data["work_y"])
	if data.has("current_health"):
		current_health = data["current_health"]
	if data.has("state"):
		_change_state(data["state"])
	if data.has("gold"):
		gold = data["gold"]
	if data.has("faction"):
		faction = data["faction"]
	if data.has("stats"):
		stats = data["stats"]
	if data.has("inventory"):
		inventory = data["inventory"]
	if data.has("relationships"):
		relationships = data["relationships"]
	if data.has("quest_flags"):
		quest_flags = data["quest_flags"]

# === EXISTING METHODS WITH UPDATES ===

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
	var current_grid_pos = GlobalGameState.world_to_map(position)
	var valid_moves = get_valid_moves_in_radius(current_grid_pos, wander_radius)
	
	if valid_moves.is_empty():
		return
	
	# Prefer moves that keep us within our wander radius of home
	var home_grid = GlobalGameState.world_to_map(home_position)
	valid_moves.sort_custom(func(a, b):
		return a.distance_to(home_grid) < b.distance_to(home_grid)
	)
	
	# Pick one of the best moves (with some randomness)
	var move_index = rng.randi() % min(3, valid_moves.size())
	var new_pos = valid_moves[move_index]
	set_move_target(new_pos)

func choose_patrol_move() -> void:
	if state_data.has("patrol_points") and not state_data["patrol_points"].is_empty():
		var patrol_points = state_data["patrol_points"]
		var current_index = state_data.get("current_patrol_point", 0)
		
		var target_point = patrol_points[current_index]
		set_move_target(target_point)
		
		# Update to next patrol point
		current_index = (current_index + 1) % patrol_points.size()
		state_data["current_patrol_point"] = current_index
		return
	
	# Fallback to old patrol method if no patrol points defined
	var current_grid_pos = GlobalGameState.world_to_map(position)
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
	var current_grid_pos = GlobalGameState.world_to_map(position)
	var home_grid = GlobalGameState.world_to_map(home_position)
	
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
	# Look for targets to hunt
	var player = _find_player()
	if player and position.distance_to(player.position) / grid_size <= vision_range:
		# Hunt the player
		state_data["target"] = player
		_change_state(NPCState.COMBAT)
		return
		
	# Otherwise just wander
	choose_wander_move()

func choose_fleeing_move() -> void:
	# Check if player is nearby
	var player = _find_player()
	if player and position.distance_to(player.position) / grid_size <= vision_range:
		# Flee from player
		state_data["threat"] = player
		_change_state(NPCState.FLEE)
		return
		
	# Otherwise just wander
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
	var width = environment.WIDTH if environment.has_method("get_tile_data") || environment.has_method("is_walkable") else 80
	var height = environment.HEIGHT if environment.has_method("get_tile_data") || environment.has_method("is_walkable") else 80
	
	if grid_pos.x < 0 or grid_pos.x >= width or grid_pos.y < 0 or grid_pos.y >= height:
		return false
	
	# Check if position is walkable based on environment type
	if environment_type == "overworld":
		if environment.has_method("is_walkable"):
			return environment.is_walkable(grid_pos)
	else: # Local area
		if environment.has_method("is_walkable"):
			return environment.is_walkable(grid_pos)
		# For local areas with tilemaps
		elif environment.has_node("walls"):
			var walls = environment.get_node("walls")
			# No wall at this position
			return walls.get_cell_source_id(0, grid_pos) == -1
	
	return true # Fallback if is_walkable not implemented

func set_move_target(grid_pos: Vector2i) -> void:
	if environment_type == "overworld":
		target_position = environment.map_to_world(grid_pos)
		var current_grid_pos = GlobalGameState.world_to_map(position)
		last_direction = Vector2(grid_pos - current_grid_pos).normalized()
	else: # Local area
		target_position = Vector2(grid_pos) * GlobalGameState.TILE_SIZE
		var current_grid_pos = Vector2i(position / GlobalGameState.TILE_SIZE)
		last_direction = Vector2(grid_pos - current_grid_pos).normalized()
	
	is_moving = true
	
	# Update sprite direction
	if sprite:
		update_sprite_direction(last_direction)

func update_sprite_direction(direction: Vector2) -> void:
	# Update sprite frame based on direction
	# This depends on your specific sprite setup
	# Example implementation:
	if direction.y > 0:
		sprite.flip_h = false
		# Set to down-facing frame
	elif direction.y < 0:
		sprite.flip_h = false
		# Set to up-facing frame
	elif direction.x != 0:
		sprite.flip_h = direction.x < 0
		# Set to side-facing frame

# === MAP TRANSITION METHODS ===
func transition_to_local_area(local_area: Node2D) -> void:
	# Save overworld position before transitioning
	if environment_type == "overworld":
		overworld_grid_pos = GlobalGameState.world_to_map(position)
	
	# Update environment reference
	environment = local_area
	environment_type = "local"
	
	# Find a valid position in local area
	var found = false
	var map_rect = null
	
	if local_area.has_node("ground"):
		map_rect = local_area.get_node("ground").get_used_rect()
	
	if map_rect:
		var start_pos = Vector2i(map_rect.position)
		for y in map_rect.size.y:
			for x in map_rect.size.x:
				var test_pos = start_pos + Vector2i(x, y)
				if is_valid_position(test_pos):
					position = Vector2(test_pos) * GlobalGameState.TILE_SIZE
					found = true
					break
			if found:
				break
	
	if not found:
		# Fallback to center of map
		position = Vector2(local_area.WIDTH / 2, local_area.HEIGHT / 2) * GlobalGameState.TILE_SIZE
	
	# Update home and work positions for local area context
	# This should be done by the calling code after transition

func transition_to_overworld(overworld_map: Node2D) -> void:
	# Update environment reference
	environment = overworld_map
	environment_type = "overworld"
	
	# Return to saved overworld position
	if overworld_grid_pos != Vector2i(-1, -1):
		position = environment.map_to_world(overworld_grid_pos)
	else:
		# If no saved position, place at a random valid position
		for _i in 100:
			var x = rng.randi_range(0, environment.WIDTH - 1)
			var y = rng.randi_range(0, environment.HEIGHT - 1)
			var grid_pos = Vector2i(x, y)
			if is_valid_position(grid_pos):
				position = environment.map_to_world(grid_pos)
				break
	
	# Update state to reflect the transition
	_change_state(NPCState.IDLE)

# === SAVE/LOAD FOR MAP TRANSITIONS ===
func save_transition_data() -> Dictionary:
	var transition_data = {
		"npc_id": npc_id,
		"npc_name": npc_name,
		"npc_type": npc_type,
		"state": state,
		"position": {
			"x": position.x,
			"y": position.y
		},
		"home_position": {
			"x": home_position.x,
			"y": home_position.y
		},
		"work_position": {
			"x": work_position.x,
			"y": work_position.y
		},
		"overworld_grid_pos": {
			"x": overworld_grid_pos.x,
			"y": overworld_grid_pos.y
		},
		"stats": stats,
		"inventory": inventory,
		"gold": gold,
		"current_health": current_health,
		"faction": faction,
		"schedule": schedule,
		"environment_type": environment_type
	}
	return transition_data

func load_from_transition(data: Dictionary) -> void:
	npc_id = data.get("npc_id", npc_id)
	npc_name = data.get("npc_name", npc_name)
	if data.has("npc_type"):
		npc_type = data.get("npc_type")
	if data.has("state"):
		state = data.get("state")
	
	if data.has("position"):
		position.x = data["position"].get("x", position.x)
		position.y = data["position"].get("y", position.y)
	
	if data.has("home_position"):
		home_position.x = data["home_position"].get("x", home_position.x)
		home_position.y = data["home_position"].get("y", home_position.y)
	
	if data.has("work_position"):
		work_position.x = data["work_position"].get("x", work_position.x)
		work_position.y = data["work_position"].get("y", work_position.y)
	
	if data.has("overworld_grid_pos"):
		overworld_grid_pos.x = data["overworld_grid_pos"].get("x", overworld_grid_pos.x)
		overworld_grid_pos.y = data["overworld_grid_pos"].get("y", overworld_grid_pos.y)
	
	if data.has("stats"):
		stats = data.get("stats")
	if data.has("inventory"):
		inventory = data.get("inventory")
	if data.has("gold"):
		gold = data.get("gold")
	if data.has("current_health"):
		current_health = data.get("current_health")
	if data.has("faction"):
		faction = data.get("faction")
	if data.has("schedule"):
		schedule = data.get("schedule")
	if data.has("environment_type"):
		environment_type = data.get("environment_type")

func update_environment(new_environment: Node2D) -> void:
	environment = new_environment
	
	# Determine environment type based on the node's characteristics
	environment_type = "local"
	if environment.has_method("world_to_map") and environment.has_method("get_tile_data"):
		environment_type = "overworld"
	
	# Enable processing if it was disabled
	set_physics_process(true)
	set_process(true)
