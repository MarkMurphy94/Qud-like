extends Item
class_name ItemBook

enum BookType {
    LORE,           # Story/world building
    SKILL,          # Teaches a skill or ability
    SPELL,          # Teaches a spell (like scroll but reusable)
    RECIPE,         # Unlocks crafting recipe
    MAP,            # Reveals locations
    QUEST           # Quest-related information
}

@export var book_type: BookType = BookType.LORE
@export_multiline var full_text: String = ""
@export var skill_id: String = ""  # For skill books
@export var spell_id: String = ""  # For spell books
@export var recipe_id: String = ""  # For recipe books
@export var read_once: bool = false  # If true, only provides benefit once

func _init():
    item_type = ItemType.BOOK
    stackable = false
    max_stack = 1