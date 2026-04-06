extends Resource
class_name SaveGameResource

## ─── Multi-slot save system ────────────────────────────────────────────
## Saves are stored in  user://saves/slot_<N>.tres  (debug) / .res (release)
## A lightweight index file  user://saves/index.tres  tracks slot metadata.

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 10

# ─── Save-file version (bump when the schema changes) ──────────────────
@export var version: int = 2

# ─── Metadata ───────────────────────────────────────────────────────────
@export var slot_index: int = -1          ## Which slot this occupies (0-based)
@export var slot_name: String = ""        ## Player-chosen label, e.g. "My Town Run"
@export var save_date: String = ""        ## ISO-8601 timestamp of the save
@export var play_time_seconds: float = 0.0 ## Total seconds of gameplay

# ─── Player position & scene ────────────────────────────────────────────
@export var player_overworld_position: Vector2 = Vector2(184, 344)
@export var player_local_position: Vector2 = Vector2.ZERO
@export var player_in_local_area: bool = false
@export var player_overworld_tile: Vector2i = Vector2i.ZERO
@export var player_current_scene_path: String = "res://scenes/game.tscn"

# ─── Player stats ──────────────────────────────────────────────────────
@export var player_health: int = 100
@export var player_max_health: int = 100
@export var player_mana: int = 50
@export var player_max_mana: int = 50
@export var player_stamina: int = 100
@export var player_max_stamina: int = 100
@export var player_gold: int = 0

# ─── Inventory (serialised via Inventory.to_dict / from_dict) ──────────
@export var inventory_data: Dictionary = {}

# ─── Learned spells (resource paths so they survive serialisation) ─────
@export var learned_spell_paths: PackedStringArray = PackedStringArray()

# ─── World tile metadata for tiles the player has discovered ───────────
## Key = "x,y"  Value = TileMetadata.to_dict()
@export var world_tile_data: Dictionary = {}

# ─── Settlement runtime state (MainGameState.settlements snapshot) ─────
@export var settlements_data: Dictionary = {}

# ─── Local area the player was in when they saved (empty = overworld) ──
@export var local_area_metadata: Dictionary = {}
@export var local_area_settlement_path: String = ""

# ─── Item pickup records — prevents already-collected WorldItems from  ─
# ─── respawning when the player re-enters an area or loads a save.     ─
## Key = area identifier (scene path for settlements, "x,y" for procedural tiles).
## Value = Array of item-key strings produced by main_game._make_item_key().
@export var area_picked_up_items: Dictionary = {}

# ═══════════════════════════════════════════════════════════════════════
#  SLOT HELPERS
# ═══════════════════════════════════════════════════════════════════════

## Build the full path for a numbered slot.
static func get_slot_path(slot: int) -> String:
	_ensure_save_dir()
	var ext := ".tres" if OS.is_debug_build() else ".res"
	return SAVE_DIR + "slot_%d%s" % [slot, ext]

## Does a particular slot exist on disk?
static func slot_exists(slot: int) -> bool:
	return ResourceLoader.exists(get_slot_path(slot))

## Does *any* save exist? (handy for greying-out "Continue" / "Load".)
static func any_save_exists() -> bool:
	for i in range(MAX_SLOTS):
		if slot_exists(i):
			return true
	return false

## Load a specific slot (returns null if it doesn't exist).
static func load_slot(slot: int) -> SaveGameResource:
	if not slot_exists(slot):
		return null
	return ResourceLoader.load(get_slot_path(slot), "", ResourceLoader.CACHE_MODE_IGNORE) as SaveGameResource

## Write this resource into its slot.
func write_to_slot(slot: int = -1) -> void:
	if slot >= 0:
		slot_index = slot
	save_date = Time.get_datetime_string_from_system(false, true)
	version = 2
	_ensure_save_dir()
	ResourceSaver.save(self, get_slot_path(slot_index))

## Delete a save slot from disk.
static func delete_slot(slot: int) -> void:
	var path := get_slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Return lightweight info about every occupied slot.
## Each entry: { "slot": int, "name": String, "date": String, "play_time": float }
static func get_all_slot_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(MAX_SLOTS):
		if slot_exists(i):
			var res := load_slot(i)
			if res:
				out.append({
					"slot": i,
					"name": res.slot_name,
					"date": res.save_date,
					"play_time": res.play_time_seconds,
					"player_position": res.player_overworld_position,
					"in_local_area": res.player_in_local_area,
				})
	return out

## Return the index of the next free slot, or -1 if all full.
static func next_free_slot() -> int:
	for i in range(MAX_SLOTS):
		if not slot_exists(i):
			return i
	return -1

## Find the most-recently-saved slot (for a "Continue" button).
static func most_recent_slot() -> int:
	var best_slot := -1
	var best_date := ""
	for i in range(MAX_SLOTS):
		if slot_exists(i):
			var res := load_slot(i)
			if res and res.save_date > best_date:
				best_date = res.save_date
				best_slot = i
	return best_slot

# ═══════════════════════════════════════════════════════════════════════
#  LEGACY COMPAT — keeps old single-file callers working until migrated
# ═══════════════════════════════════════════════════════════════════════

## @deprecated – use slot_exists / any_save_exists instead
static func save_exists() -> bool:
	return any_save_exists()

## @deprecated – loads most recent slot
static func load_savegame() -> SaveGameResource:
	var slot := most_recent_slot()
	if slot >= 0:
		return load_slot(slot)
	return null

## @deprecated – reset is now just "start a new game"
static func reset_savegame() -> void:
	pass # No-op; new game simply doesn't load any slot.

# ─── Internal ───────────────────────────────────────────────────────────
static func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ─── Pretty-print helpers ──────────────────────────────────────────────
func get_play_time_string() -> String:
	var total := int(play_time_seconds)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	var seconds := total % 60
	if hours > 0:
		return "%dh %02dm %02ds" % [hours, minutes, seconds]
	elif minutes > 0:
		return "%dm %02ds" % [minutes, seconds]
	else:
		return "%ds" % seconds
