extends Resource
class_name Item

## Base item resource class for all items in the game.
## Can be extended for specialized item types (weapons, armor, consumables).
## Supports both hand-crafted unique items and procedural generation.

enum ItemType {
    WEAPON,
    ARMOR,
    CONSUMABLE,
    BOOK,
    MATERIAL,
    QUEST,
    KEY,
    MISC
}

enum Rarity {
    COMMON,
    UNCOMMON,
    RARE,
    EPIC,
    LEGENDARY,
    UNIQUE  ## For quest/special items
}

## Core identification
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var item_type: ItemType = ItemType.MISC
@export var rarity: Rarity = Rarity.COMMON

## Visuals
##
## Art comes from TilesetCatalog.ITEM_TILES: register an atlas coord there under
## the item's `id` and nothing needs setting here at all. `sprite_id` points at
## a catalog entry under a different name (variants sharing one sprite);
## `sprite_index` is the local override for one-off art with no catalog entry;
## `sprite_region` is the escape hatch for art that does not sit on the 16px
## grid, and wins over both. A direct `icon` beats everything.
@export_group("Visuals")
@export var icon: Texture2D  ## Direct icon texture (optional, overrides spritesheet)
@export var spritesheet: Texture2D  ## Overrides ItemDatabase.default_item_spritesheet
@export var sprite_region: Rect2i = Rect2i(0, 0, 0, 0)  ## Explicit pixel region; zero size = use the atlas coord
@export var sprite_id: String = ""  ## TilesetCatalog.ITEM_TILES key; blank falls back to `id`
@export var sprite_index: Vector2i = Vector2i(0, 0)  ## Atlas coordinate (col, row), used when the catalog has no entry
@export var tile_size: Vector2i = Vector2i(0, 0)  ## Zero = ItemDatabase.default_tile_size

## Inventory properties
@export_group("Inventory")
@export var stackable: bool = false
@export var max_stack: int = 1
@export var weight: float = 1.0
@export var base_value: int = 0

## Flags
@export_group("Flags")
@export var is_quest_item: bool = false
@export var is_unique: bool = false
@export var can_drop: bool = true
@export var can_sell: bool = true

## Optional modifiers (for generated items)
@export var modifiers: Dictionary = {}


## Returns the icon texture for UI display
## If a direct icon is set, uses that. Otherwise extracts from spritesheet.
## Falls back to ItemDatabase.default_item_spritesheet if no spritesheet is set.
func get_icon() -> Texture2D:
    if icon:
        return icon
    
    var sheet = _get_spritesheet()
    if sheet:
        return _create_atlas_texture(sheet)
    return null


## Gets the spritesheet to use, falling back to ItemDatabase default
func _get_spritesheet() -> Texture2D:
    if spritesheet:
        return spritesheet
    # Fall back to ItemDatabase default if available
    if Engine.has_singleton("ItemDatabase"):
        return Engine.get_singleton("ItemDatabase").default_item_spritesheet
    # Try accessing as autoload (more common pattern)
    var item_db = Engine.get_main_loop().root.get_node_or_null("/root/ItemDatabase")
    if item_db and item_db.default_item_spritesheet:
        return item_db.default_item_spritesheet
    return null


## Gets the tile size, falling back to ItemDatabase default
func _get_tile_size() -> Vector2i:
    if tile_size.x > 0 and tile_size.y > 0:
        return tile_size
    var item_db = Engine.get_main_loop().root.get_node_or_null("/root/ItemDatabase")
    if item_db:
        return item_db.default_tile_size
    return Vector2i(16, 16)


## Creates an AtlasTexture from the spritesheet using sprite_region or sprite_index
func _create_atlas_texture(sheet: Texture2D) -> AtlasTexture:
    var atlas = AtlasTexture.new()
    atlas.atlas = sheet
    
    # If sprite_region is set (non-zero size), use it directly
    if sprite_region.size.x > 0 and sprite_region.size.y > 0:
        atlas.region = Rect2(sprite_region)
    else:
        # Otherwise calculate from the atlas coord and tile_size
        var ts = _get_tile_size()
        var coord = get_sprite_index()
        atlas.region = Rect2(
            coord.x * ts.x,
            coord.y * ts.y,
            ts.x,
            ts.y
        )
    
    return atlas


## The atlas coord this item's art sits at. The catalog is asked first — that is
## where item art is registered, so adding a coord there is all a new item needs
## — and the resource's own `sprite_index` is the fallback.
func get_sprite_index() -> Vector2i:
    var named: String = sprite_id if not sprite_id.is_empty() else id
    var coord: Vector2i = TilesetCatalog.item_atlas(named)
    if coord != TilesetCatalog.NO_ITEM_TILE:
        return coord
    return sprite_index


## True when this item's art comes from the catalog rather than the resource.
func has_catalog_art() -> bool:
    return TilesetCatalog.has_item_tile(sprite_id if not sprite_id.is_empty() else id)


## Returns the calculated sprite region (useful for debugging)
func get_sprite_rect() -> Rect2:
    if sprite_region.size.x > 0 and sprite_region.size.y > 0:
        return Rect2(sprite_region)
    var ts = _get_tile_size()
    var coord = get_sprite_index()
    return Rect2(
        coord.x * ts.x,
        coord.y * ts.y,
        ts.x,
        ts.y
    )


## Returns the total value including any modifiers
func get_total_value() -> int:
    var modifier_bonus = modifiers.get("value_bonus", 0)
    return base_value + modifier_bonus


## Returns the display name with prefix/suffix modifiers applied
func get_display_name() -> String:
    var prefix = modifiers.get("prefix", "")
    var suffix = modifiers.get("suffix", "")
    var name = display_name
    if prefix:
        name = prefix + " " + name
    if suffix:
        name = name + " " + suffix
    return name


## Returns a color associated with the item's rarity
func get_rarity_color() -> Color:
    match rarity:
        Rarity.COMMON:
            return Color.WHITE
        Rarity.UNCOMMON:
            return Color.GREEN
        Rarity.RARE:
            return Color.CORNFLOWER_BLUE
        Rarity.EPIC:
            return Color.MEDIUM_PURPLE
        Rarity.LEGENDARY:
            return Color.ORANGE
        Rarity.UNIQUE:
            return Color.GOLD
        _:
            return Color.WHITE


## Returns a string representation of the rarity
func get_rarity_name() -> String:
    match rarity:
        Rarity.COMMON:
            return "Common"
        Rarity.UNCOMMON:
            return "Uncommon"
        Rarity.RARE:
            return "Rare"
        Rarity.EPIC:
            return "Epic"
        Rarity.LEGENDARY:
            return "Legendary"
        Rarity.UNIQUE:
            return "Unique"
        _:
            return "Unknown"


## Creates a deep copy of this item
func duplicate_item() -> Item:
    var new_item = duplicate(true)
    new_item.modifiers = modifiers.duplicate(true)
    return new_item
