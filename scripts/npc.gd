extends CharacterBody2D
class_name NPC

## NPC — unified, data-driven non-player character controller.
##
## Drives every non-player character in the game (peasants, soldiers,
## merchants, nobles, bandits, animals, monsters) through a single state
## machine (see NPCState) covering wandering, scheduled routines (work/eat/
## sleep), combat, fleeing, following, and dialogue/trade interaction.
##
## HOW TO USE:
## - Instance `npc.tscn` (or a scene that extends it) and place it in a local
##   area (NPCs currently only operate within local area maps, not the
##   overworld).
## - Set `npc_type` (MainGameState.NpcType) and optionally `npc_variant` in the
##   Inspector; `apply_type_profile()` and `set_sprite()` (called from
##   `_ready()`) pull move speed, stats, faction, sprite region, spells, and
##   trade behavior from the profile table returned by `get_profiles()` for
##   that type/variant. Add new types/variants by extending `_build_profiles()`
##   — no script changes are needed for basic stat/sprite tuning.
## - Sprites come from the shared roguelike master sheet. A variant names its
##   art as `sprite_atlas_coords` — a Vector2i(col, row) into that sheet — and
##   `set_sprite()` converts it into the region rect on the `npc_sprite` node.
## - Optionally call `set_locations(home, work)` after spawning to configure
##   its wander/work anchor points, and assign a `schedule` if it should
##   follow hourly routines.
## - The NPCSpawner (`scripts/npc_spawner.gd`) is the normal way NPCs get
##   created at runtime based on settlement density tiers — prefer that over
##   manually instancing NPCs for populated areas.
## - This NPC is a turn-based actor. It has no per-frame AI loop: TurnManager
##   calls `take_turn()` once for every action it can afford, which runs
##   perception → behavior decision → exactly one action. `_process()` only
##   keeps the debug and health-bar overlays glued to the sprite.
## - Player interaction (dialogue/trade) goes through `start_interaction()` /
##   `end_interaction()`, triggered by the Player's interact-radius detection.

## Optional config resource to auto-apply settings from a config resource (useful for type templates, unique NPCs, or loading an NPC programmatically from a saved config)
# @export var auto_set_config: NPCConfig 

## Geometry of the roguelike master sheet NPC art is cut from, so the sprite
## cell size has one definition shared with the tile generator.
const Layout := preload("res://resources/tileset_layout.gd")

## Marks a variant whose coords on the roguelike sheet have not been picked yet.
## Such a variant keeps whatever region npc.tscn ships with and warns, so
## unmigrated entries are obvious rather than silently drawing the wrong art.
const SPRITE_TODO := Vector2i(-1, -1)

# === EXPORTS AND CONFIGURATION ===
@export_group("Basic Properties")
## Legacy px/s figure kept only because the profile table is keyed on it; the
## turn `speed` below is derived from it. Movement itself is one tile per turn.
@export var move_speed: float = 50.0
@export var tile_size: int = 16
# @export var grid_size: int = 16
@export var movement_threshold: float = 1.0 # Distance threshold for considering movement complete
@export var npc_type: MainGameState.NpcType = MainGameState.NpcType.PEASANT
@export var npc_variant: String = "default" # New variant property
@export var vision_range: float = 8.0 # How many tiles the NPC can see
@export var hearing_range: float = 5.0 # How many tiles the NPC can hear
@export var max_health: int = 100

@export_group("Turn scheduling")
## Actions per standard turn, relative to TurnManager.NORMAL_SPEED (100).
## 50 = acts every other player turn, 200 = twice per player turn.
@export var speed: int = 100
## Energy pool owned by TurnManager — do not touch it from AI code.
var energy: int = 0

@export_group("stats sheet")
@export var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"endurance": 10,
	"charisma": 10,
	"initiative": 10   ## Used for turn-order rolls in combat
}

# === IDENTITY AND PERSISTENCE ===
@export_group("NPC identity, and behavior")
@export var npc_id: String = "" # Unique identifier
@export var npc_name: String = ""
@export var faction: String = "NEUTRAL" # Group this NPC belongs to
@export var relationships: Dictionary = {} # NPC ID or faction -> relationship value (-100 to 100)
@export var inventory: Inventory = null  # Proper inventory system with stacking
@export var equipped_items: Dictionary = {}
@export var quest_flags: Dictionary = {}
@export var current_health: int = max_health
@export var gold: int = 0

@onready var up: RayCast2D = $up
@onready var down: RayCast2D = $down
@onready var left: RayCast2D = $left
@onready var right: RayCast2D = $right
@onready var npc_sprite: Sprite2D = $npc_sprite
@onready var debug_canvas: CanvasLayer = $CanvasLayer


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
var sprite_node_pos_tween: Tween

# === MOVEMENT AND NAVIGATION ===
# NPCs are currently restricted to local area maps only and cannot transition to overworld
var environment: Node2D # Local area map only
var rng = RandomNumberGenerator.new()
var target_position: Vector2
## True only while the sprite is sliding into the tile the body already left.
## Purely cosmetic — the turn scheduler, not this flag, gates actions.
var is_moving: bool = false
var last_direction: Vector2 = Vector2.ZERO
var path: Array = [] # For pathfinding
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

# === TYPE / VARIANT PROFILE TABLE ===

## Built once for the whole class instead of once per instance — a populated
## settlement holds dozens of NPCs and this table is large. Built lazily (on the
## first NPC's _ready) rather than at script load so the MainGameState autoload
## is guaranteed to exist by the time the enum keys are evaluated.
static var _profiles: Dictionary = {}

## The type/variant profile table. Add types and variants here — basic stat,
## faction and sprite tuning needs no script changes.
static func get_profiles() -> Dictionary:
	if _profiles.is_empty():
		_profiles = _build_profiles()
	return _profiles

## Variant names defined for a type. NPCSpawner picks from this so the list of
## valid variants has exactly one source of truth.
static func variants_for(type_value: MainGameState.NpcType) -> Array:
	var type_data: Dictionary = get_profiles().get(type_value, {})
	return type_data.keys()

static func _build_profiles() -> Dictionary:
	var profiles: Dictionary = {}
	profiles[MainGameState.NpcType.SOLDIER] = {
		"default": {
			"move_speed": 60.0,
			"sprite_atlas_coords": Vector2i(7, 33), # was 32rogues Rect2i(64, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 12, "intelligence": 8, "endurance": 14, "charisma": 8}
		},
		"archer": {
			"move_speed": 55.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(96, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 16, "intelligence": 10, "endurance": 12, "charisma": 8}
		},
		"knight": {
			"move_speed": 50.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(0, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 16, "agility": 8, "intelligence": 8, "endurance": 16, "charisma": 10}
		},
		"heavy_knight": {
			"move_speed": 45.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(32, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 18, "agility": 6, "intelligence": 8, "endurance": 18, "charisma": 10}
		},
		"crossbowman": {
			"move_speed": 52.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(128, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 14, "intelligence": 10, "endurance": 12, "charisma": 8}
		},
		"longswordsman": {
			"move_speed": 58.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(160, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 12, "intelligence": 8, "endurance": 14, "charisma": 8}
		},
		"fencer": {
			"move_speed": 65.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(192, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 10, "agility": 16, "intelligence": 10, "endurance": 10, "charisma": 12}
		},
		"warrior_monk": {
			"move_speed": 62.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(224, 32, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 14, "agility": 14, "intelligence": 12, "endurance": 14, "charisma": 10}
		},
		"battlemage": {
			"move_speed": 55.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(0, 64, 32, 32)
			"faction": "GUARD",
			"max_mana": 80,
			"spells": ["res://resources/spells/spell_templates/fireball.tres"],
			"stats": {"strength": 10, "agility": 10, "intelligence": 16, "endurance": 12, "charisma": 10}
		},
		"dwarf_warrior": {
			"move_speed": 52.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(32, 64, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 16, "agility": 8, "intelligence": 8, "endurance": 18, "charisma": 8}
		},
		"elven_archer": {
			"move_speed": 60.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(64, 64, 32, 32)
			"faction": "GUARD",
			"stats": {"strength": 8, "agility": 18, "intelligence": 12, "endurance": 10, "charisma": 12}
		}
	}
	profiles[MainGameState.NpcType.PEASANT] = {
		"default": {
			"move_speed": 50.0,
			"sprite_atlas_coords": Vector2i(62, 33), # was 32rogues Rect2i(0, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 8, "agility": 10, "intelligence": 8, "endurance": 10, "charisma": 8}
		},
		"farmer": {
			"move_speed": 45.0,
			"sprite_atlas_coords": Vector2i(62, 33), # was 32rogues Rect2i(0, 224, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 12, "agility": 8, "intelligence": 8, "endurance": 12, "charisma": 6}
		},
		"baker": {
			"move_speed": 42.0,
			"sprite_atlas_coords": Vector2i(61, 33), # was 32rogues Rect2i(32, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 10, "agility": 8, "intelligence": 10, "endurance": 10, "charisma": 10}
		},
		"blacksmith": {
			"move_speed": 45.0,
			"sprite_atlas_coords": Vector2i(8, 33), # was 32rogues Rect2i(64, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 16, "agility": 8, "intelligence": 10, "endurance": 14, "charisma": 8}
		},
		"scholar": {
			"move_speed": 42.0,
			"sprite_atlas_coords": Vector2i(17, 33), # was 32rogues Rect2i(128, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 6, "agility": 8, "intelligence": 16, "endurance": 8, "charisma": 12}
		},
		"crone": {
			"move_speed": 36.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(192, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 6, "agility": 6, "intelligence": 14, "endurance": 8, "charisma": 10}
		},
		"hermit": {
			"move_speed": 40.0,
			"sprite_atlas_coords": Vector2i(45, 33), # was 32rogues Rect2i(224, 160, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 8, "agility": 8, "intelligence": 12, "endurance": 10, "charisma": 6}
		},
		"forester": {
			"move_speed": 52.0,
			"sprite_atlas_coords": Vector2i(62, 33), # was 32rogues Rect2i(0, 192, 32, 32)
			"faction": "CIVILIAN",
			"stats": {"strength": 12, "agility": 12, "intelligence": 10, "endurance": 12, "charisma": 8}
		}
	}
	profiles[MainGameState.NpcType.MERCHANT] = {
		"default": {
			"move_speed": 42.0,
			"move_interval": 0.6,
			"wander_radius": 3.0,
			"sprite_atlas_coords": Vector2i(89, 33), # was 32rogues Rect2i(96, 160, 32, 32)
			"behavior": "stay_near_shop",
			"faction": "MERCHANT",
			"dialogue": "merchant_dialogue",
			"inventory_template": "merchant_items",
			"can_trade": true,
			"trade_prices": {"buy_multiplier": 1.2, "sell_multiplier": 0.4},
			"stats": {"strength": 8, "agility": 8, "intelligence": 12, "endurance": 8, "charisma": 14}
		}
	}
	profiles[MainGameState.NpcType.NOBLE] = {
		"default": {
			"move_speed": 36.0,
			"move_interval": 0.7,
			"wander_radius": 4.0,
			"sprite_atlas_coords": Vector2i(91, 33), # was 32rogues Rect2i(160, 160, 32, 32)
			"behavior": "stay_in_manor",
			"faction": "NOBLE",
			"dialogue": "noble_dialogue",
			"inventory_template": "noble_items",
			"can_trade": false,
			"stats": {"strength": 8, "agility": 8, "intelligence": 14, "endurance": 8, "charisma": 14}
		},
		"priest": {
			"move_speed": 42.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(32, 192, 32, 32)
			"faction": "CLERGY",
			"stats": {"strength": 8, "agility": 8, "intelligence": 14, "endurance": 10, "charisma": 14}
		},
		"cleric": {
			"move_speed": 45.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(64, 192, 32, 32)
			"faction": "CLERGY",
			"stats": {"strength": 10, "agility": 8, "intelligence": 14, "endurance": 12, "charisma": 12}
		},
		"monk": {
			"move_speed": 52.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(96, 192, 32, 32)
			"faction": "CLERGY",
			"stats": {"strength": 10, "agility": 12, "intelligence": 12, "endurance": 12, "charisma": 10}
		},
		"druid": {
			"move_speed": 48.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(128, 192, 32, 32)
			"faction": "DRUID",
			"stats": {"strength": 8, "agility": 10, "intelligence": 16, "endurance": 10, "charisma": 12}
		},
		"witch": {
			"move_speed": 45.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(160, 192, 32, 32)
			"faction": "NEUTRAL",
			"max_mana": 90,
			"spells": ["res://resources/spells/spell_templates/dark_magic_ball.tres"],
			"stats": {"strength": 6, "agility": 10, "intelligence": 16, "endurance": 8, "charisma": 10}
		},
		"wizard": {
			"move_speed": 42.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(192, 192, 32, 32)
			"faction": "MAGE",
			"max_mana": 120,
			"spells": ["res://resources/spells/spell_templates/fireball.tres", "res://resources/spells/spell_templates/dark_magic_ball.tres"],
			"stats": {"strength": 6, "agility": 8, "intelligence": 18, "endurance": 8, "charisma": 12}
		},
		"warlock": {
			"move_speed": 45.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(224, 192, 32, 32)
			"faction": "NEUTRAL",
			"max_mana": 100,
			"spells": ["res://resources/spells/spell_templates/dark_magic_ball.tres"],
			"stats": {"strength": 8, "agility": 8, "intelligence": 16, "endurance": 10, "charisma": 10}
		},
		"dwarf_wizard": {
			"move_speed": 40.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(0, 224, 32, 32)
			"faction": "MAGE",
			"stats": {"strength": 10, "agility": 6, "intelligence": 16, "endurance": 14, "charisma": 10}
		}
	}
	profiles[MainGameState.NpcType.BANDIT] = {
		"default": {
			"move_speed": 72.0,
			"move_interval": 0.3,
			"wander_radius": 10.0,
			"sprite_atlas_coords": Vector2i(71, 33), # was 32rogues Rect2i(0, 0, 32, 32)
			"behavior": "aggressive",
			"faction": "OUTLAW",
			"dialogue": "bandit_dialogue",
			"inventory_template": "bandit_items",
			"can_trade": false,
			"stats": {"strength": 12, "agility": 14, "intelligence": 8, "endurance": 10, "charisma": 6}
		},
		"thief": {
			"move_speed": 78.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(32, 0, 32, 32)
			"faction": "OUTLAW",
			"stats": {"strength": 8, "agility": 16, "intelligence": 12, "endurance": 8, "charisma": 10}
		},
		"elven_rogue": {
			"move_speed": 80.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(64, 0, 32, 32)
			"faction": "OUTLAW",
			"stats": {"strength": 8, "agility": 18, "intelligence": 14, "endurance": 8, "charisma": 12}
		},
		"barbarian": {
			"move_speed": 70.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(96, 0, 32, 32)
			"faction": "TRIBAL",
			"stats": {"strength": 16, "agility": 12, "intelligence": 6, "endurance": 16, "charisma": 6}
		},
		"heavy_barbarian": {
			"move_speed": 65.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(128, 0, 32, 32)
			"faction": "TRIBAL",
			"stats": {"strength": 18, "agility": 10, "intelligence": 6, "endurance": 18, "charisma": 6}
		},
		"hill_tribe_warrior": {
			"move_speed": 68.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(160, 0, 32, 32)
			"faction": "TRIBAL",
			"stats": {"strength": 14, "agility": 14, "intelligence": 8, "endurance": 14, "charisma": 6}
		},
		"dark_priest": {
			"move_speed": 52.0,
			"sprite_atlas_coords": SPRITE_TODO, # was 32rogues Rect2i(192, 0, 32, 32)
			"faction": "CULTIST",
			"max_mana": 80,
			"spells": ["res://resources/spells/spell_templates/dark_magic_ball.tres"],
			"stats": {"strength": 8, "agility": 8, "intelligence": 16, "endurance": 10, "charisma": 10}
		}
	}
	profiles[MainGameState.NpcType.ANIMAL] = {
		"default": {
			"move_speed": 55.0,
			"move_interval": 0.4,
			"wander_radius": 6.0,
			"sprite_atlas_coords": Vector2i(92, 28), # was 32rogues Rect2i(128, 96, 32, 32)
			"behavior": "flee_on_approach",
			"faction": "WILDLIFE",
			"dialogue": "none",
			"inventory_template": "animal_items",
			"can_trade": false,
			"stats": {"strength": 8, "agility": 14, "intelligence": 2, "endurance": 8, "charisma": 2}
		}
	}
	profiles[MainGameState.NpcType.MONSTER] = {
		"default": {
			"move_speed": 65.0,
			"move_interval": 0.3,
			"wander_radius": 12.0,
			"sprite_atlas_coords": Vector2i(5, 32), # was 32rogues Rect2i(0, 160, 32, 32)
			"behavior": "hunt",
			"max_mana": 50,
			"faction": "MONSTER",
			"dialogue": "none",
			"inventory_template": "monster_items",
			"can_trade": false,
			"stats": {"strength": 16, "agility": 12, "intelligence": 6, "endurance": 14, "charisma": 2}
		}
	}
	return profiles

@onready var debug_container: VBoxContainer = $CanvasLayer/VBoxContainer
@onready var debug_1: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text
@onready var debug_2: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text2
@onready var debug_3: RichTextLabel = $CanvasLayer/VBoxContainer/debug_text3


@onready var interact_radius: Area2D = $interact_radius
@onready var _interact_label: Label = $InteractLabel

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
## Hour last acted on, so a schedule change fires its state switch only once.
var last_schedule_hour: int = -1

# --- PERCEPTION CACHES ---
var current_target: Node2D = null
var threat_source: Node2D = null
var flee_turns: int = 0
## Melee reach in pixels. Just under two tiles so only orthogonal/diagonal
## neighbours are in range — you must be standing next to someone to hit them.
var combat_range: float = 24.0
var hear_event_cooldown: int = 0

# --- DEBUG OPTIONS ---
var show_debug: bool = true

# --- SPELL SYSTEM ---
@export var learned_spells: Array[Spell] = []   ## Spells this NPC knows
var spell_cooldowns: Dictionary = {}    ## spell_id -> turns remaining
var max_mana: int = 0                   ## 0 means NPC is non-magical
var current_mana: int = 0
var mana_regen_per_turn: int = 5        ## Mana restored at the start of each turn

# --- COMBAT INDICATORS ---
## Combat UI nodes (created programmatically in _ready)
var _exclamation_label : Label       = null
var _hp_bar_container  : Control     = null
var _hp_bar_bg         : ColorRect   = null
var _hp_bar_fill       : ColorRect   = null
	
func _ready():
	add_to_group("NPCs")  # Ensure group membership regardless of how the NPC was created
	rng.randomize()
	apply_type_profile()
	set_sprite()
	_build_combat_indicators()
	# Stagger starting energy so a crowd of NPCs doesn't move in lockstep.
	energy = rng.randi_range(0, TurnManager.TICKS_PER_ACTION - 1)
	# Attempt to locate player for reference (optional)
	if not player_reference:
		player_reference = _find_player()
	# Initialize schedule to nearest state
	_update_schedule(true)
	# Connect interaction signals
	if interact_radius:
		interact_radius.body_entered.connect(_on_interact_radius_body_entered)
		interact_radius.body_exited.connect(_on_interact_radius_body_exited)
	
	# Initialize inventory
	_initialize_inventory()
	
	set_process(true)
	set_physics_process(false)

## Per-frame work is limited to overlays. No AI, no movement — the world is
## frozen until the player acts.
func _process(_delta: float) -> void:
	if state == NPCState.DEAD:
		return
	_update_debug()
	_update_combat_ui()

## One action. Called by TurnManager as often as this NPC's speed affords.
## Returns the world-time cost of what it did, in ticks.
func take_turn() -> int:
	if state == NPCState.DEAD:
		return TurnManager.TICKS_PER_ACTION

	_tick_turn_timers()
	_update_schedule()
	_perception_update()

	# Standing still to talk to the player still burns the turn.
	if is_interacting:
		return TurnManager.TICKS_PER_ACTION

	_behavior_decision()
	return _execute_state()

## Advance everything this NPC measures in turns rather than seconds.
func _tick_turn_timers() -> void:
	state_timer += 1.0
	hear_event_cooldown = maxi(0, hear_event_cooldown - 1)
	for sid in spell_cooldowns.keys():
		spell_cooldowns[sid] -= 1.0
		if spell_cooldowns[sid] <= 0.0:
			spell_cooldowns.erase(sid)
	restore_mana_for_turn()

## The profile for this NPC's type/variant, or {} when neither the type nor a
## "default" variant is defined. apply_type_profile() and set_sprite() both read
## through this so the type → variant → default fallback lives in one place.
func _resolve_profile() -> Dictionary:
	var type_data: Dictionary = get_profiles().get(npc_type, {})
	if type_data.is_empty():
		push_warning("No properties found for NPC type %s" % npc_type)
		return {}
	var profile: Dictionary = type_data.get(npc_variant, type_data.get("default", {}))
	if profile.is_empty():
		push_warning("No variant '%s' found for NPC type %s" % [npc_variant, npc_type])
	return profile

func apply_type_profile():
	var profile := _resolve_profile()
	if profile.is_empty():
		return
	
	move_speed = profile.get("move_speed", move_speed)
	# The profile table is written in px/s, which no longer means anything in a
	# turn-based world — reinterpret it as turn speed so ~55 px/s reads as
	# "normal". A profile can still state an explicit `speed` to override this.
	speed = int(profile.get("speed", clampi(roundi(move_speed / 55.0 * 100.0), 40, 250)))
	wander_radius = profile.get("wander_radius", wander_radius)
	faction = profile.get("faction", faction)
	stats = profile.get("stats", stats)
	can_trade = profile.get("can_trade", false)
	if profile.has("trade_prices"):
		trade_prices = profile.trade_prices
	# Load spells
	max_mana = profile.get("max_mana", 0)
	current_mana = max_mana
	# learned_spells.clear()
	# for spell_path in profile.get("spells", []):
	# 	if ResourceLoader.exists(spell_path):
	# 		var sp := load(spell_path) as Spell
	# 		if sp:
	# 			learned_spells.append(sp)

func apply_auto_set_config(_config: NPCConfig):
	# TODO: implement to auto-set all export variables from a config- good for applying templates for npc types or named npcs
	pass

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
	var profile := _resolve_profile()
	if profile.is_empty():
		return
	
	var coords: Vector2i = profile.get("sprite_atlas_coords", SPRITE_TODO)
	if coords == SPRITE_TODO:
		push_warning("NPC type %s variant '%s' has no roguelike sheet coords yet" % [npc_type, npc_variant])
		return
	
	# One Sprite2D serves every NPC type; the type only decides which cell of the
	# shared sheet it shows. npc.tscn must therefore give the sprite the *whole*
	# sheet texture — an AtlasTexture would clip this region to its own window
	# (and, being a shared sub-resource, would leak between NPC instances).
	npc_sprite.region_enabled = true
	npc_sprite.region_rect = Rect2(
		Vector2(coords * Layout.TILE_SIZE),
		Vector2(Layout.TILE_SIZE, Layout.TILE_SIZE)
	)

func _enter_state(s: int):
	match s:
		NPCState.WANDER:
			_choose_new_wander_target()
		NPCState.FLEE:
			flee_turns = 6
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
			_set_combat_indicators_visible(true)

func _exit_state(s: int):
	if s == NPCState.COMBAT:
		_set_combat_indicators_visible(false)

func _update_schedule(force: bool = false):
	# World time is the only clock: one hour passes every
	# TurnManager.TURNS_PER_GAME_HOUR turns.
	var hour: int = TurnManager.get_hour()
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
	# If fleeing and there is panic left, keep fleeing
	if state == NPCState.FLEE:
		if flee_turns <= 0:
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

	# Schedule-determined states already handled; pick somewhere new to amble
	# to once the current wander target has been reached.
	if state in [NPCState.IDLE, NPCState.WANDER] and _at_target_tile():
		_choose_new_wander_target()

## Perform exactly one action for the current state and report its tick cost.
func _execute_state() -> int:
	match state:
		NPCState.WANDER:
			# Idling some turns makes crowds look alive instead of frantic.
			if rng.randf() < 0.35:
				return TurnManager.TICKS_PER_ACTION
			_step_towards(target_position)
		NPCState.WORK:
			if work_position != Vector2.ZERO:
				target_position = work_position
				_step_towards(target_position, true)
		NPCState.SLEEP:
			target_position = home_position
			_step_towards(target_position, true)
		NPCState.PATROL:
			# Placeholder: treat like wander for now
			_step_towards(target_position)
		NPCState.COMBAT:
			return _combat_turn()
		NPCState.FLEE:
			flee_turns -= 1
			_flee_turn()
		NPCState.FOLLOW:
			if is_instance_valid(current_target):
				target_position = current_target.global_position
				_step_towards(target_position)
			else:
				set_state(NPCState.IDLE)
		_:
			# EAT, IDLE, INTERACT, DEAD — stand still, but still burn the turn.
			pass
	return TurnManager.TICKS_PER_ACTION

## True when this NPC is already standing on its target tile.
func _at_target_tile() -> bool:
	if target_position == Vector2.ZERO:
		return true
	return Vector2i(global_position / tile_size) == Vector2i(target_position / tile_size)

## Take one tile-step toward `destination`, preferring the axis with the larger
## gap and falling back to the other when blocked. Returns true if it moved.
func _step_towards(destination: Vector2, arrive_idle: bool = false) -> bool:
	if destination == Vector2.ZERO:
		return false
	var curr_tile: Vector2i = Vector2i(global_position / tile_size)
	var target_tile: Vector2i = Vector2i(destination / tile_size)
	if curr_tile == target_tile:
		if arrive_idle:
			set_state(NPCState.IDLE)
		return false

	var delta_tile: Vector2i = target_tile - curr_tile
	var primary_dir: Vector2
	var secondary_dir: Vector2
	if abs(delta_tile.x) >= abs(delta_tile.y):
		primary_dir = Vector2.RIGHT if delta_tile.x > 0 else Vector2.LEFT
		secondary_dir = Vector2.DOWN if delta_tile.y > 0 else Vector2.UP
	else:
		primary_dir = Vector2.DOWN if delta_tile.y > 0 else Vector2.UP
		secondary_dir = Vector2.RIGHT if delta_tile.x > 0 else Vector2.LEFT

	if _grid_try_move(primary_dir):
		return true
	return _grid_try_move(secondary_dir)

func _choose_new_wander_target():
	var center = home_position if home_position != Vector2.ZERO else global_position
	var radius_pixels = wander_radius * tile_size
	var offset = Vector2(rng.randf_range(-radius_pixels, radius_pixels), rng.randf_range(-radius_pixels, radius_pixels))
	target_position = center + offset

## One combat action: cast if a spell is worth it, else swing if adjacent,
## else close the distance. Exactly one of these happens per turn.
func _combat_turn() -> int:
	if not is_instance_valid(current_target):
		set_state(NPCState.WANDER)
		return TurnManager.TICKS_PER_ACTION

	var dist = global_position.distance_to(current_target.global_position)
	if dist > vision_range * tile_size * 1.2:
		# Lost target
		current_target = null
		set_state(NPCState.WANDER)
		return TurnManager.TICKS_PER_ACTION

	var spell := get_best_combat_spell(dist)
	if spell != null and cast_spell_at(spell, current_target):
		return TurnManager.TICKS_PER_ACTION

	if dist <= combat_range:
		attack(current_target)
	else:
		_step_towards(current_target.global_position)
	return TurnManager.TICKS_PER_ACTION

func _flee_turn() -> void:
	if not is_instance_valid(threat_source):
		set_state(NPCState.WANDER)
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

## Public hostility check used by the player's bump-to-attack. Openly hostile
## factions always qualify; so does anyone already fighting `who`.
func is_hostile_toward(who: Node) -> bool:
	if state == NPCState.DEAD:
		return false
	if _is_hostile_to_player() and who == player_reference:
		return true
	return state == NPCState.COMBAT and current_target == who

## Is this NPC a valid obstacle/target? Corpses are neither.
func is_alive() -> bool:
	return state != NPCState.DEAD and current_health > 0

func _attitude_towards_player() -> int:
	if _is_hostile_to_player():
		return -50
	return 10

func _known_entity_update(id: String, pos: Vector2, attitude: int = 0):
	known_entities[id] = {
		"last_seen_time": TurnManager.world_time,
		"last_seen_position": pos,
		"attitude": attitude
	}

func _find_player() -> Node2D:
	# Group lookup only. _perception_update() calls this every frame until a
	# player is found, so a recursive whole-tree find_child() fallback here would
	# cost a full scene walk per NPC per frame.
	var players := get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return null
	return players[0]

func record_event(event: Dictionary):
	recent_events.append(event)
	while recent_events.size() > max_memory_events:
		recent_events.pop_front()

func _update_debug():
	# The debug overlay's CanvasLayer is hidden in npc.tscn by default. Formatting
	# three labels per NPC per physics frame is not free, so skip the work unless
	# the overlay is actually on screen.
	if not show_debug or debug_canvas == null or not debug_canvas.visible:
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
		debug_1.text = "State: %s \n HP:%d/%d" % [_state_name(state), current_health, max_health]
	if debug_2:
		var hour = last_schedule_hour
		debug_2.text = "Hour:%02d \n Target:%s" % [hour, Vector2i(target_position)]
	if debug_3:
		var tgt = current_target if current_target else null
		debug_3.text = "Hostile:%s \n Target:%s" % [str(_is_hostile_to_player()), (tgt and tgt.name) if tgt else "None"]

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

# =============================
# TURN-BASED COMBAT SUPPORT
# =============================

func _build_combat_indicators() -> void:
	"""Create exclamation mark label and HP bar in the NPC's CanvasLayer."""
	var canvas = get_node_or_null("CanvasLayer")
	if canvas == null:
		return

	# ── Exclamation label (red "!") ──────────────────────────────────────
	_exclamation_label = Label.new()
	_exclamation_label.text = "!"
	_exclamation_label.add_theme_font_size_override("font_size", 22)
	_exclamation_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	_exclamation_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_exclamation_label.add_theme_constant_override("shadow_offset_x", 1)
	_exclamation_label.add_theme_constant_override("shadow_offset_y", 1)
	_exclamation_label.visible = false
	canvas.add_child(_exclamation_label)

	# ── HP bar (background + fill) ───────────────────────────────────────
	_hp_bar_container = Control.new()
	_hp_bar_container.custom_minimum_size = Vector2(32, 5)
	_hp_bar_container.visible = false
	canvas.add_child(_hp_bar_container)

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.color = Color(0.2, 0.2, 0.2)
	_hp_bar_bg.size = Vector2(32, 5)
	_hp_bar_container.add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.color = Color(0.85, 0.15, 0.15)
	_hp_bar_fill.size = Vector2(32, 5)
	_hp_bar_container.add_child(_hp_bar_fill)

func _update_combat_ui() -> void:
	"""Reposition and refresh combat indicators every physics frame."""
	if _exclamation_label == null:
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var screen_pos: Vector2 = get_global_transform_with_canvas().origin
	# Exclamation: directly above the NPC
	_exclamation_label.position = screen_pos + Vector2(-6, -44)
	# HP bar: just below the exclamation
	if _hp_bar_container:
		_hp_bar_container.position = screen_pos + Vector2(-16, -26)
		var ratio: float = float(current_health) / float(max(1, max_health))
		if _hp_bar_fill:
			_hp_bar_fill.size.x = 32.0 * clampf(ratio, 0.0, 1.0)

## Show or hide the aggro indicators. Driven by entering/leaving COMBAT, so
## the "!" pops the moment this NPC actually turns on someone.
func _set_combat_indicators_visible(visible_now: bool) -> void:
	if _hp_bar_container:
		_hp_bar_container.visible = visible_now
	if _exclamation_label == null:
		return
	if not visible_now:
		_exclamation_label.visible = false
		_exclamation_label.modulate.a = 1.0
		return
	# Blink the "!" once, then let it fade — the HP bar stays for the fight.
	_exclamation_label.visible = true
	_exclamation_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_exclamation_label, "modulate:a", 0.0, 0.4)
	tw.finished.connect(func(): _exclamation_label.visible = false)

## Cast `spell` at `target`, spending mana and starting its cooldown.
## Returns true if the spell went off (and therefore consumed the turn).
func cast_spell_at(spell: Spell, target: Node2D) -> bool:
	if not is_instance_valid(target) or not spell:
		return false
	if current_mana < spell.get_mana_cost():
		return false
	if is_spell_on_cooldown(spell.id):
		return false
	current_mana -= spell.get_mana_cost()
	start_spell_cooldown(spell.id, spell.cooldown)
	# Spawn the projectile
	var projectile_scene: PackedScene = load("res://scenes/projectile_spell.tscn")
	if projectile_scene == null:
		push_warning("[NPC] projectile_spell.tscn not found")
		return false
	var projectile: Node2D = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = global_position
	var to_target: Vector2 = target.global_position - global_position
	var max_range_px: float = spell.spell_range * tile_size
	var stop_px: float = minf(to_target.length(), max_range_px)
	projectile.setup(spell, self, to_target.normalized(), stop_px)
	var display_name: String = npc_name if npc_name != "" else str(name)
	TurnManager.log_message("%s casts %s!" % [display_name, spell.get_display_name()], "spell")
	return true

## Called at the start of each turn to regenerate a little mana.
func restore_mana_for_turn() -> void:
	if max_mana > 0:
		current_mana = mini(current_mana + mana_regen_per_turn, max_mana)

## Return the best offensive spell this NPC can cast at the given distance (px).
## Returns null if none are available.
func get_best_combat_spell(dist_px: float) -> Spell:
	var best: Spell = null
	for sp in learned_spells:
		if sp.spell_type != Spell.SpellType.OFFENSIVE:
			continue
		if current_mana < sp.get_mana_cost():
			continue
		if is_spell_on_cooldown(sp.id):
			continue
		if dist_px > sp.spell_range * tile_size:
			continue
		if best == null or sp.get_damage() > best.get_damage():
			best = sp
	return best

## Returns current mana (duck-typed compatibility with Spell.can_cast()).
func get_current_mana() -> int:
	return current_mana

## Returns NPC level (placeholder; satisfies Spell.can_cast() duck-typing).
func get_level() -> int:
	return 1

## Check if a spell is on cooldown.
func is_spell_on_cooldown(spell_id: String) -> bool:
	return spell_cooldowns.has(spell_id) and spell_cooldowns[spell_id] > 0.0

## Start cooldown for a spell, measured in turns.
func start_spell_cooldown(spell_id: String, cooldown: float) -> void:
	if cooldown > 0.0:
		spell_cooldowns[spell_id] = cooldown

## Swing at `target`. One turn's worth of violence.
func attack(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	# Calculate damage: strength-based with a small dice roll
	var str_val: int = stats.get("strength", 10)
	var damage := int(str_val * 0.5) + rng.randi_range(1, 6)
	emit_signal("npc_attacked", self, target)
	var display_name: String = npc_name if npc_name != "" else str(name)
	if target.has_method("take_damage"):
		target.take_damage(damage, self)
	else:
		print("%s attacks %s for %d damage" % [display_name, target.name, damage])

func take_damage(amount: int, source: Node2D = null):
	if state == NPCState.DEAD:
		return
	current_health -= amount
	record_event({"type": "damage", "amount": amount})
	var display_name: String = npc_name if npc_name != "" else str(name)
	TurnManager.log_message("%s takes %d damage. (%d/%d HP)" % [display_name, amount, max(0, current_health), max_health], "attack")
	if current_health <= 0:
		current_health = 0
		set_state(NPCState.DEAD)
		emit_signal("npc_died", self)
		velocity = Vector2.ZERO
		_set_combat_indicators_visible(false)
		TurnManager.log_message("%s has been slain!" % display_name, "death")
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
		hear_event_cooldown = 2
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
	# The body teleports a full tile immediately so the turn resolves in one
	# atomic move; the sprite is then left behind and tweened into place to
	# sell the step. Capture where the sprite actually is *before* moving the
	# body — mid-slide that is not simply "one tile back".
	var from: Vector2 = npc_sprite.global_position
	is_moving = true
	global_position += dir * tile_size
	if sprite_node_pos_tween:
		sprite_node_pos_tween.kill()
	npc_sprite.global_position = from
	sprite_node_pos_tween = create_tween()
	sprite_node_pos_tween.tween_property(npc_sprite, "global_position", global_position,
		TurnManager.STEP_DURATION).set_trans(Tween.TRANS_SINE)
	sprite_node_pos_tween.finished.connect(_on_move_tween_finished)

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
		if _interact_label and state != NPCState.DEAD:
			_interact_label.visible = true
		emit_signal("npc_interaction_available", self)

func _on_interact_radius_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_interact_range = false
		if _interact_label:
			_interact_label.visible = false
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

func _start_dialogue_interaction(_interactor: Node2D) -> void:
	"""Handle dialogue-based interaction"""
	print("%s: Hello there!" % npc_name if npc_name else "NPC says hello!")
	# TODO: Implement actual dialogue system integration
	# For now, just print a message based on NPC type and faction
	var greeting = _get_greeting_message()
	print(greeting)

func _start_trade_interaction(_interactor: Node2D) -> void:
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

func interact_give_item(item: Item, quantity: int = 1) -> bool:
	"""Player gives an item to this NPC
	Returns true if NPC accepts the item"""
	if not is_interacting:
		return false
	
	if not inventory:
		_initialize_inventory()
	
	# Check if NPC wants this item (quest logic, etc.)
	var accepts_item = _should_accept_item(item)
	
	if accepts_item:
		if inventory.add_item(item, quantity):
			emit_signal("npc_item_received", self, item, state_data.get("interactor"))
			print("%s accepts the %s" % [npc_name if npc_name else "NPC", item.get_display_name()])
			return true
		else:
			print("%s's inventory is full" % [npc_name if npc_name else "NPC"])
			return false
	else:
		print("%s doesn't want that." % [npc_name if npc_name else "NPC"])
		return false

func _should_accept_item(item: Item) -> bool:
	"""Determine if NPC should accept the given item"""
	# TODO: Implement quest item checking, faction preferences, etc.
	# For now, merchants accept everything, others are selective
	if can_trade:
		return true
	
	# Check quest flags for specific item requests
	if quest_flags.has("wants_item"):
		var wanted_item = quest_flags["wants_item"]
		if item.id == wanted_item:
			return true
	
	return false

# =============================
# INVENTORY SYSTEM
# =============================

func _initialize_inventory() -> void:
	"""Set up the NPC's inventory"""
	if not inventory:
		inventory = Inventory.new()
		# NPCs typically have smaller inventories than player
		inventory.max_slots = 10
		inventory.max_weight = 50.0
		add_child(inventory)
		
		# Merchants have larger inventories
		if can_trade:
			inventory.max_slots = 30
			inventory.max_weight = 200.0
		
		# Connect to inventory signals
		inventory.inventory_changed.connect(_on_inventory_changed)
		inventory.inventory_full.connect(_on_inventory_full)
		
		# Populate a default test inventory so NPCs have something to trade
		_populate_default_inventory()

func _populate_default_inventory() -> void:
	"""Add a handful of starter items to every NPC inventory for testing."""
	# Always give a few consumables
	var potion_path := "res://resources/items/templates/consumables/health_potion.tres"
	var bread_path  := "res://resources/items/templates/consumables/bread.tres"
	var dagger_path := "res://resources/items/templates/weapons/dagger.tres"
	var sword_path  := "res://resources/items/templates/weapons/basic_sword.tres"

	if ResourceLoader.exists(potion_path):
		var potion: Item = load(potion_path)
		if potion:
			inventory.add_item(potion, 3)

	if ResourceLoader.exists(bread_path):
		var bread: Item = load(bread_path)
		if bread:
			inventory.add_item(bread, 2)

	# Merchants and bandits also stock weapons
	if can_trade or faction in ["OUTLAW", "GUARD"]:
		if ResourceLoader.exists(dagger_path):
			var dagger: Item = load(dagger_path)
			if dagger:
				inventory.add_item(dagger, 1)

	if can_trade:
		if ResourceLoader.exists(sword_path):
			var sword: Item = load(sword_path)
			if sword:
				inventory.add_item(sword, 1)

func add_item_to_inventory(item: Item, quantity: int = 1) -> bool:
	"""Add an item to the NPC's inventory. Returns true if successful."""
	if not inventory:
		_initialize_inventory()
	
	return inventory.add_item(item, quantity)

func remove_item_from_inventory(item_id: String, quantity: int = 1) -> int:
	"""Remove an item from inventory. Returns the actual quantity removed."""
	if not inventory:
		return 0
	
	return inventory.remove_item(item_id, quantity)

func has_item(item_id: String, quantity: int = 1) -> bool:
	"""Check if NPC has a specific item"""
	if not inventory:
		return false
	
	return inventory.has_item(item_id, quantity)

func get_inventory() -> Inventory:
	"""Get the NPC's inventory for external access"""
	return inventory

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
	"""Spawn an item in the world at the NPC's position"""
	var world_item_scene = preload("res://scenes/world_item.tscn")
	var world_item = world_item_scene.instantiate()
	world_item.item_resource = item
	world_item.quantity = quantity
	
	# Spawn slightly in front of the NPC
	var spawn_offset = Vector2(0, tile_size)
	world_item.global_position = global_position + spawn_offset
	
	# Add to the current scene
	get_parent().add_child(world_item)
	
	print("%s dropped %d x %s" % [npc_name if npc_name else "NPC", quantity, item.get_display_name()])

# Inventory signal handlers
func _on_inventory_changed() -> void:
	"""Called when inventory contents change"""
	# Update any UI or AI logic that depends on inventory
	pass

func _on_inventory_full() -> void:
	"""Called when trying to add to a full inventory"""
	if show_debug:
		print("%s's inventory is full!" % [npc_name if npc_name else "NPC"])
