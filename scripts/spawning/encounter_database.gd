extends Node

## Loads every EncounterEntry under ENCOUNTER_PATH (recursively), every
## PopulationPoolDef under POOL_PATH and every SpawnModifier template under
## MODIFIER_PATH at startup, and drops entries that cannot spawn, so the
## resolver only sees well-formed data.

const ENCOUNTER_PATH := "res://resources/spawning/encounters/"
const POOL_PATH := "res://resources/spawning/pools/"
const MODIFIER_PATH := "res://resources/spawning/modifiers/"

## id -> EncounterEntry
var entries: Dictionary = {}
## id -> PopulationPoolDef
var pools: Dictionary = {}
## id -> SpawnModifier template. Never handed out directly; EncounterState
## duplicates it per emission.
var modifier_templates: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	entries.clear()
	pools.clear()
	modifier_templates.clear()
	_load_pools()
	_load_modifiers()
	var paths: Dictionary = {}  # entry id -> file path, for error messages
	_load_folder(ENCOUNTER_PATH, paths)
	for entry_id: String in entries.keys():
		if not _is_valid(entries[entry_id], paths[entry_id]):
			entries.erase(entry_id)
	print("[EncounterDatabase] Loaded %d encounter entries, %d population pools, %d spawn modifiers"
		% [entries.size(), pools.size(), modifier_templates.size()])


func get_pool(pool_id: String) -> PopulationPoolDef:
	return pools.get(pool_id)


func get_modifier_template(template_id: String) -> SpawnModifier:
	return modifier_templates.get(template_id)


func get_entry(entry_id: String) -> EncounterEntry:
	return entries.get(entry_id)


func ambient_entries() -> Array[EncounterEntry]:
	return _of_kind("ambient")


func anchor_entries() -> Array[EncounterEntry]:
	return _of_kind("anchor")


## Sorted by id so that weighted picks over them are deterministic.
func _of_kind(kind: String) -> Array[EncounterEntry]:
	var out: Array[EncounterEntry] = []
	for entry: EncounterEntry in entries.values():
		if entry.kind == kind:
			out.append(entry)
	out.sort_custom(func(a: EncounterEntry, b: EncounterEntry) -> bool: return a.id < b.id)
	return out


func _load_folder(path: String, paths: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[EncounterDatabase] No encounter folder at %s" % path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_load_folder(full_path, paths)
		elif file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			full_path = full_path.trim_suffix(".remap")
			var entry := load(full_path) as EncounterEntry
			if entry == null:
				push_error("[EncounterDatabase] %s is not an EncounterEntry" % full_path)
			else:
				if entry.id.is_empty():
					entry.id = file_name.trim_suffix(".remap").get_basename()
				if entries.has(entry.id):
					push_error("[EncounterDatabase] %s: encounter id '%s' already used by %s" % [full_path, entry.id, paths[entry.id]])
				else:
					entries[entry.id] = entry
					paths[entry.id] = full_path
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_pools() -> void:
	var dir := DirAccess.open(POOL_PATH)
	if dir == null:
		push_warning("[EncounterDatabase] No pool folder at %s" % POOL_PATH)
		return
	for file_name in dir.get_files():
		file_name = file_name.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var full_path := POOL_PATH + file_name
		var def := load(full_path) as PopulationPoolDef
		if def == null:
			push_error("[EncounterDatabase] %s is not a PopulationPoolDef" % full_path)
			continue
		if def.id.is_empty():
			def.id = file_name.get_basename()
		if pools.has(def.id):
			push_error("[EncounterDatabase] %s: pool id '%s' is already used" % [full_path, def.id])
			continue
		pools[def.id] = def
	for def: PopulationPoolDef in pools.values():
		for prey_id: String in def.prey:
			if not pools.has(prey_id):
				push_warning("[EncounterDatabase] pool %s preys on unknown pool %s" % [def.id, prey_id])


func _load_modifiers() -> void:
	var dir := DirAccess.open(MODIFIER_PATH)
	if dir == null:
		push_warning("[EncounterDatabase] No modifier folder at %s" % MODIFIER_PATH)
		return
	for file_name in dir.get_files():
		file_name = file_name.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var full_path := MODIFIER_PATH + file_name
		var mod := load(full_path) as SpawnModifier
		if mod == null:
			push_error("[EncounterDatabase] %s is not a SpawnModifier" % full_path)
			continue
		if mod.id.is_empty():
			mod.id = file_name.get_basename()
		if modifier_templates.has(mod.id):
			push_error("[EncounterDatabase] %s: modifier id '%s' is already used" % [full_path, mod.id])
			continue
		for pool_id: String in mod.pool_deltas:
			if not pools.has(pool_id):
				push_warning("[EncounterDatabase] %s: pool_deltas names unknown pool %s" % [full_path, pool_id])
		modifier_templates[mod.id] = mod


func _is_valid(entry: EncounterEntry, path: String) -> bool:
	if not entry.pool_id.is_empty() and not pools.has(entry.pool_id):
		push_warning("[EncounterDatabase] %s: unknown pool_id '%s'; entry dropped" % [path, entry.pool_id])
		return false
	if entry.kind == "anchor" and entry.anchor_match.is_empty():
		push_warning("[EncounterDatabase] %s: anchor entry matches no camp; entry dropped" % path)
		return false
	if not NPCSpawner.ENCOUNTER_NPC_TYPES.has(entry.npc_type):
		push_warning("[EncounterDatabase] %s: unknown npc_type '%s'; entry dropped" % [path, entry.npc_type])
		return false
	var known: Array = NPC.variants_for(NPCSpawner.ENCOUNTER_NPC_TYPES[entry.npc_type])
	for variant in entry.variants:
		if not variant in known:
			push_warning("[EncounterDatabase] %s: '%s' has no variant '%s'; entry dropped" % [path, entry.npc_type, variant])
			return false
	if entry.group_min < 1 or entry.group_min > entry.group_max:
		push_error("[EncounterDatabase] %s: group size %d..%d is invalid; entry dropped" % [path, entry.group_min, entry.group_max])
		return false
	if entry.budget_cost < 1:
		push_error("[EncounterDatabase] %s: budget_cost must be at least 1; entry dropped" % path)
		return false
	return true
