extends Item
class_name ItemSpellScroll

@export var spell: Spell  # Reference to the spell it teaches
@export var consumed_on_use: bool = true  # Scrolls usually consumed, books aren't

func _init():
    item_type = ItemType.CONSUMABLE
    stackable = false