extends Node

## Default spritesheet for items that don't specify one, and the grid it is cut
## on. Both come from TilesetCatalog — the same table the map is painted from —
## so an item's icon and its world tile are the same 16px grid and an item is
## addressed by the atlas coord it occupies there.
var default_item_spritesheet: Resource = TilesetCatalog.ITEM_SHEET
var default_tile_size: Vector2i = TilesetCatalog.ITEM_TILE_SIZE

## ItemDatabase - Autoload singleton for managing item templates and unique items.
## Provides access to both predefined unique items and templates for procedural generation.

## Paths to item resource folders
const ITEM_PATHS = {
	"templates": "res://resources/items/templates/",
	"weapons": "res://resources/items/weapons/",
	"armor": "res://resources/items/armor/",
	"consumables": "res://resources/items/consumables/",
	"quest": "res://resources/items/quest/",
	"materials": "res://resources/items/materials/"
}

## Templates for procedural generation
var weapon_templates: Dictionary = {}
var armor_templates: Dictionary = {}
var consumable_templates: Dictionary = {}
var book_templates: Dictionary = {}
var material_templates: Dictionary = {}

## Cache for unique/quest items (loaded from .tres files)
var unique_items: Dictionary = {}

## All items indexed by ID for quick lookup
var all_items: Dictionary = {}

## tag -> Array[String] of item ids carrying it. Built from all_items after load.
var tag_index: Dictionary = {}

## Every unique/hand-crafted item is indexed under this tag, so random tag
## queries can exclude them without each .tres having to remember it.
const UNIQUE_TAG := "kind.unique"

## Spawn tables live alongside the items they draw from: entries are validated
## against the item index, so they have to load after it.
const SPAWN_TABLE_PATH := "res://resources/spawn_tables/"
const SPAWN_TABLE_TIERS := ["owned", "ambient"]

## table id -> ItemSpawnTable
var spawn_tables: Dictionary = {}


func _ready():
	_load_templates()
	_load_unique_items()
	_build_tag_index()
	_load_spawn_tables()
	_report_missing_art()
	print("[ItemDatabase] Loaded %d weapon templates" % weapon_templates.size())
	print("[ItemDatabase] Loaded %d armor templates" % armor_templates.size())
	print("[ItemDatabase] Loaded %d consumable templates" % consumable_templates.size())
	print("[ItemDatabase] Loaded %d unique items" % unique_items.size())
	print("[ItemDatabase] Loaded %d spawn tables" % spawn_tables.size())


func _load_templates():
	## Load weapon templates
	_load_folder_into_dict(ITEM_PATHS["templates"] + "weapons/", weapon_templates, true, "ItemWeapon")
	
	## Load armor templates
	_load_folder_into_dict(ITEM_PATHS["templates"] + "armor/", armor_templates, true, "ItemArmor")

	## Load consumable templates
	_load_folder_into_dict(ITEM_PATHS["templates"] + "consumables/", consumable_templates, true, "ItemConsumable")

	## Load book templates
	_load_folder_into_dict(ITEM_PATHS["templates"] + "books/", book_templates, true, "ItemBook")
	
	## Load material templates
	_load_folder_into_dict(ITEM_PATHS["templates"] + "materials/", material_templates, true)


func _load_unique_items():
	## Load all quest/unique items from files
	_load_folder_into_dict(ITEM_PATHS["quest"], unique_items, true)
	
	## Also load specific weapon/armor/consumable folders for hand-crafted items
	_load_folder_into_dict(ITEM_PATHS["weapons"], unique_items, true)
	_load_folder_into_dict(ITEM_PATHS["armor"], unique_items, true)
	_load_folder_into_dict(ITEM_PATHS["consumables"], unique_items, true)


## Index every .tres in `path` by item id.
##
## `expected_class` guards the typed getters below: a template folder is only a
## convention, so a resource of the wrong class dropped into one would other-
## wise be handed back by a getter that promises a narrower type and crash at
## the return. Warn and skip instead — the file is misfiled, not malformed.
func _load_folder_into_dict(path: String, target_dict: Dictionary, add_to_all: bool = false, expected_class: String = ""):
	if not DirAccess.dir_exists_absolute(path):
		return
	
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path = path + file_name
			var item = load(full_path)
			if item and item is Item:
				if expected_class != "" and not _script_is(item, expected_class):
					push_warning("[ItemDatabase] %s is not a %s — skipping (wrong folder?)" % [full_path, expected_class])
				else:
					var item_id = item.id if item.id else file_name.get_basename()
					if item.template_id.is_empty():
						item.template_id = item_id
					target_dict[item_id] = item
					if add_to_all:
						all_items[item_id] = item
		file_name = dir.get_next()
	dir.list_dir_end()


## Whether `item`'s script chain declares `class_name` — Object.is_class() only
## knows about engine classes, so a GDScript type has to be walked by hand.
func _script_is(item: Item, class_name_str: String) -> bool:
	var script: Script = item.get_script()
	while script != null:
		if script.get_global_name() == class_name_str:
			return true
		script = script.get_base_script()
	return false


## Get a specific unique item by ID (returns a duplicate to avoid shared state)
func get_unique_item(item_id: String) -> Item:
	if unique_items.has(item_id):
		return unique_items[item_id].duplicate_item()
	push_warning("[ItemDatabase] Unknown unique item: %s" % item_id)
	return null


## Get any item by ID (returns a duplicate)
func get_item(item_id: String) -> Item:
	if all_items.has(item_id):
		return all_items[item_id].duplicate_item()
	push_warning("[ItemDatabase] Unknown item: %s" % item_id)
	return null


## Get a weapon template for procedural generation (returns original, not duplicate)
func get_weapon_template(template_id: String) -> ItemWeapon:
	if weapon_templates.has(template_id):
		return weapon_templates[template_id]
	push_warning("[ItemDatabase] Unknown weapon template: %s" % template_id)
	return null


## Get an armor template for procedural generation (returns original, not duplicate)
func get_armor_template(template_id: String) -> ItemArmor:
	if armor_templates.has(template_id):
		return armor_templates[template_id]
	push_warning("[ItemDatabase] Unknown armor template: %s" % template_id)
	return null


## Get a consumable template for procedural generation (returns original, not duplicate)
func get_consumable_template(template_id: String) -> ItemConsumable:
	if consumable_templates.has(template_id):
		return consumable_templates[template_id]
	push_warning("[ItemDatabase] Unknown consumable template: %s" % template_id)
	return null


## Get a material template (returns original, not duplicate)
func get_material_template(template_id: String) -> Item:
	if material_templates.has(template_id):
		return material_templates[template_id]
	push_warning("[ItemDatabase] Unknown material template: %s" % template_id)
	return null


## Get a book template (returns original, not duplicate)
func get_book_template(template_id: String) -> ItemBook:
	if book_templates.has(template_id):
		return book_templates[template_id]
	push_warning("[ItemDatabase] Unknown book template: %s" % template_id)
	return null


## Get a list of all weapon template IDs
func get_weapon_template_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in weapon_templates.keys():
		ids.append(key)
	return ids


## Get a list of all armor template IDs
func get_armor_template_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in armor_templates.keys():
		ids.append(key)
	return ids


## Get a list of all consumable template IDs
func get_consumable_template_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in consumable_templates.keys():
		ids.append(key)
	return ids


## Get a list of all book template IDs
func get_book_template_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in book_templates.keys():
		ids.append(key)
	return ids


## Check if an item exists
func has_item(item_id: String) -> bool:
	return all_items.has(item_id) or unique_items.has(item_id)


## Check if a weapon template exists
func has_weapon_template(template_id: String) -> bool:
	return weapon_templates.has(template_id)


## Reload all items (useful for development)
func reload():
	weapon_templates.clear()
	armor_templates.clear()
	consumable_templates.clear()
	book_templates.clear()
	material_templates.clear()
	unique_items.clear()
	all_items.clear()
	tag_index.clear()
	spawn_tables.clear()
	_load_templates()
	_load_unique_items()
	_build_tag_index()
	_load_spawn_tables()
	_report_missing_art()
	print("[ItemDatabase] Reloaded all items")


func _build_tag_index() -> void:
	tag_index.clear()
	for item_id: String in all_items:
		var item: Item = all_items[item_id]
		var item_tags: Array[String] = item.tags.duplicate()
		if unique_items.has(item_id) and not UNIQUE_TAG in item_tags:
			item_tags.append(UNIQUE_TAG)
		for tag in item_tags:
			if not tag_index.has(tag):
				tag_index[tag] = []
			tag_index[tag].append(item_id)


## Ids of every item carrying all of `required` and none of `excluded`, sorted
## so a seeded pick over the result is stable across runs.
func find_by_tags(required: Array[String], excluded: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	if required.is_empty():
		return out
	var smallest: Array = []
	for tag in required:
		var ids: Array = tag_index.get(tag, [])
		if ids.is_empty():
			return out
		if smallest.is_empty() or ids.size() < smallest.size():
			smallest = ids
	for item_id: String in smallest:
		if _ids_have_tags(item_id, required) and not _ids_have_any_tag(item_id, excluded):
			out.append(item_id)
	out.sort()
	return out


func _ids_have_tags(item_id: String, tags: Array[String]) -> bool:
	for tag in tags:
		if not item_id in tag_index.get(tag, []):
			return false
	return true


func _ids_have_any_tag(item_id: String, tags: Array[String]) -> bool:
	for tag in tags:
		if item_id in tag_index.get(tag, []):
			return true
	return false


func get_spawn_table(table_id: String) -> ItemSpawnTable:
	if spawn_tables.has(table_id):
		return spawn_tables[table_id]
	push_warning("[ItemDatabase] Unknown spawn table: %s" % table_id)
	return null


func has_spawn_table(table_id: String) -> bool:
	return spawn_tables.has(table_id)


func _load_spawn_tables() -> void:
	var paths: Dictionary = {}  # table id -> file path, for error messages
	var dir := DirAccess.open(SPAWN_TABLE_PATH)
	if dir == null:
		push_warning("[ItemDatabase] No spawn table folder at %s" % SPAWN_TABLE_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path := SPAWN_TABLE_PATH + file_name
			var table := load(full_path) as ItemSpawnTable
			if table == null:
				push_error("[ItemDatabase] %s is not an ItemSpawnTable" % full_path)
			else:
				var table_id := table.id if not table.id.is_empty() else file_name.get_basename()
				table.id = table_id
				if spawn_tables.has(table_id):
					push_error("[ItemDatabase] %s: spawn table id '%s' already used by %s" % [full_path, table_id, paths[table_id]])
				else:
					spawn_tables[table_id] = table
					paths[table_id] = full_path
		file_name = dir.get_next()
	dir.list_dir_end()

	for table_id: String in spawn_tables:
		_validate_spawn_table(spawn_tables[table_id], paths[table_id])
	_report_spawn_table_cycles(paths)


## Report and drop entries that cannot resolve, so the resolver only ever sees
## well-formed data. Empty tag queries are a warning, not an error: the item
## they want may simply not be authored yet.
func _validate_spawn_table(table: ItemSpawnTable, path: String) -> void:
	if not table.tier in SPAWN_TABLE_TIERS:
		push_error("[ItemDatabase] %s: tier '%s' must be one of %s" % [path, table.tier, SPAWN_TABLE_TIERS])
	if table.rolls.x < 0 or table.rolls.y < table.rolls.x:
		push_error("[ItemDatabase] %s: rolls %s is not a valid min/max range" % [path, table.rolls])

	var valid: Array[ItemSpawnEntry] = []
	for i in table.entries.size():
		var entry: ItemSpawnEntry = table.entries[i]
		var where := "%s entry %d" % [path, i]
		if entry == null:
			push_error("[ItemDatabase] %s is empty" % where)
			continue
		if entry.source_count() != 1:
			push_error("[ItemDatabase] %s must set exactly one of item_id, item_tags, table_id" % where)
			continue
		if not entry.item_id.is_empty() and not has_item(entry.item_id):
			push_error("[ItemDatabase] %s: unknown item_id '%s'" % [where, entry.item_id])
			continue
		if not entry.table_id.is_empty() and not spawn_tables.has(entry.table_id):
			push_error("[ItemDatabase] %s: unknown table_id '%s'" % [where, entry.table_id])
			continue
		if not entry.item_tags.is_empty() and find_by_tags(entry.item_tags, [UNIQUE_TAG]).is_empty():
			push_warning("[ItemDatabase] %s: no item carries all of %s" % [where, entry.item_tags])
		if entry.weight <= 0.0:
			push_warning("[ItemDatabase] %s: weight %s means it is never picked" % [where, entry.weight])
		if entry.count.x < 0 or entry.count.y < entry.count.x:
			push_error("[ItemDatabase] %s: count %s is not a valid min/max range" % [where, entry.count])
			continue
		valid.append(entry)
	table.entries = valid


## Depth-first walk over nested table_id edges. A cycle is reported once, with
## the chain that closes it; the resolver's depth guard keeps it from hanging.
func _report_spawn_table_cycles(paths: Dictionary) -> void:
	var state: Dictionary = {}  # table id -> 1 visiting, 2 done
	for table_id: String in spawn_tables:
		_walk_spawn_table(table_id, state, [], paths)


func _walk_spawn_table(table_id: String, state: Dictionary, chain: Array, paths: Dictionary) -> void:
	if state.get(table_id, 0) == 2:
		return
	if state.get(table_id, 0) == 1:
		var loop: Array = chain.slice(chain.find(table_id)) + [table_id]
		push_error("[ItemDatabase] Spawn table cycle: %s (%s)" % [" -> ".join(PackedStringArray(loop)), paths.get(table_id, "")])
		return
	state[table_id] = 1
	chain.append(table_id)
	var table: ItemSpawnTable = spawn_tables[table_id]
	for entry in table.entries:
		if not entry.table_id.is_empty():
			_walk_spawn_table(entry.table_id, state, chain, paths)
	chain.pop_back()
	state[table_id] = 2


## Helper to get icon for any item, using default spritesheet if needed
func get_item_icon(item: Item) -> Texture2D:
	if item == null:
		return null
	return item.get_icon()


## Items loaded without any art registered for them — no catalog entry, no
## sprite_index, no icon. Printed once at startup so a newly added item that
## still needs a TilesetCatalog.ITEM_TILES coord is impossible to miss.
func _report_missing_art() -> void:
	var missing: Array[String] = []
	for item_id: String in all_items:
		var item: Item = all_items[item_id]
		if item.icon or item.sprite_region.size.x > 0:
			continue
		if item.has_catalog_art() or item.sprite_index != Vector2i.ZERO:
			continue
		missing.append(item_id)
	if not missing.is_empty():
		push_warning("[ItemDatabase] No art for: %s — add a coord to TilesetCatalog.ITEM_TILES" % ", ".join(missing))
