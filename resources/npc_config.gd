extends Resource

class_name NPCConfig

# === EXPORTS AND CONFIGURATION ===
@export_group("Basic Properties")
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

# === IDENTITY AND PERSISTENCE ===
@export_group("NPC stats and behavior")
@export var npc_id: String = "" # Unique identifier
@export var npc_name: String = ""
@export var faction: String = "NEUTRAL" # PLACEHOLDER. This will likely be an enum or reference to a Faction resource.
@export var relationships: Dictionary = {} # NPC ID or faction -> relationship value (-100 to 100)
@export var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"endurance": 10,
	"charisma": 10
}
@export var inventory_items: Array[Dictionary] = [] # List of items in inventory, each with {item_id, quantity}
@export var equipped_items: Dictionary = {}
@export var quest_flags: Dictionary = {}
@export var current_health: int = max_health
@export var gold: int = 0