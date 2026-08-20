extends Node

## Default spritesheet for items that don't specify one.
## The transparent cut of the Backterria master sheet — the same art the map is
## painted from (see resources/tileset_catalog.gd), so an item's icon and its
## world tile are the same 16px grid and an item is addressed by the atlas
## coord it occupies there.
var default_item_spritesheet: Resource = preload("res://assets/The Roguelike 1-15-1 Alpha.png")
var default_tile_size: Vector2i = Vector2i(16, 16)

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


func _ready():
	_load_templates()
	_load_unique_items()
	print("[ItemDatabase] Loaded %d weapon templates" % weapon_templates.size())
	print("[ItemDatabase] Loaded %d armor templates" % armor_templates.size())
	print("[ItemDatabase] Loaded %d consumable templates" % consumable_templates.size())
	print("[ItemDatabase] Loaded %d unique items" % unique_items.size())


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
	_load_templates()
	_load_unique_items()
	print("[ItemDatabase] Reloaded all items")


## Helper to get icon for any item, using default spritesheet if needed
func get_item_icon(item: Item) -> Texture2D:
	if item.icon:
		return item.icon
	
	var spritesheet = item.spritesheet if item.spritesheet else default_item_spritesheet
	if not spritesheet:
		return null
	
	var atlas = AtlasTexture.new()
	atlas.atlas = spritesheet
	
	if item.sprite_region.size.x > 0:
		atlas.region = Rect2(item.sprite_region)
	else:
		var tile_size = item.tile_size if item.tile_size.x > 0 else default_tile_size
		atlas.region = Rect2(
			item.sprite_index.x * tile_size.x,
			item.sprite_index.y * tile_size.y,
			tile_size.x,
			tile_size.y
		)
	
	return atlas
