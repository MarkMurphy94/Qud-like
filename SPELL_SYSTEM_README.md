# Spell Learning System - Quick Start Guide

## Overview
The spell learning system allows players to learn spells from spell books and manage them through a spell book UI.

## Components Created

### 1. **Spell Resource** (`resources/spells/spell.gd`)
- Base spell class with properties for casting, effects, requirements, and visuals
- Includes helper methods like `can_cast()`, `get_icon()`, `get_display_name()`

### 2. **Spell Templates** (`resources/spells/spell_templates/`)
- `fireball.tres` - Example offensive spell

### 3. **Item Book** (`resources/items/item_book.gd`)
- Already existed, used for spell books
- `book_type = SPELL` indicates it teaches a spell
- `spell_id` references the spell template file name

### 4. **Spell Book Items** (`resources/items/templates/books/`)
- `spellbook_fireball.tres` - Teaches the Fireball spell
- Set `read_once = true` to consume on use

### 5. **Player Spell System** (`scripts/Player.gd`)
- `learned_spells: Array[Spell]` - Stores learned spells
- `spell_cooldowns: Dictionary` - Tracks spell cooldowns
- `learn_spell(spell)` - Learn a new spell
- `has_spell(spell_id)` - Check if spell is known
- `get_learned_spells()` - Get all learned spells
- `open_spell_book()` - Open spell book UI

### 6. **Spell Book UI** (`scenes/spell_book_screen.tscn` & `scripts/spell_book_screen.gd`)
- Displays learned spells in a grid
- Shows spell details (damage, mana cost, cooldown, etc.)
- Filter spells by type
- Cast button (currently just consumes mana and prints message)

### 7. **Inventory Integration** (`scripts/inventory_screen.gd`)
- "Spell Book" button in title bar to open spell book
- Using a spell book item teaches the spell to the player
- Books with `read_once = true` are consumed after learning

## How to Test

### Option 1: Add Spellbook via Console (if you have one)
```gdscript
var book = load("res://resources/items/templates/books/spellbook_fireball.tres")
player.add_item_to_inventory(book, 1)
```

### Option 2: Place in World
1. Create a `WorldItem` scene instance
2. Set `item_resource` to the spellbook
3. Walk over it to pick up

### Option 3: Add to Starting Inventory
In `Player.gd`, add after `_initialize_inventory()`:
```gdscript
# Give starting spell book for testing
var starting_book = load("res://resources/items/templates/books/spellbook_fireball.tres")
if starting_book:
    add_item_to_inventory(starting_book, 1)
```

## Usage Flow

1. **Get a Spell Book**
   - Find/receive `spellbook_fireball.tres`
   - It appears in your inventory

2. **Learn the Spell**
   - Open inventory (I key or button)
   - Click the spell book
   - Click "Use" button
   - Message: "Learned spell: Fireball"
   - Book is removed (because `read_once = true`)

3. **View Learned Spells**
   - Click "Spell Book" button in inventory
   - See all learned spells in grid
   - Click a spell to see details

4. **Cast a Spell** (Partial Implementation)
   - Select spell in spell book
   - Click "Cast Spell"
   - Mana is consumed
   - Cooldown is started
   - Message printed (actual effects TODO)

## Creating New Spells

### 1. Create Spell Template
File: `resources/spells/spell_templates/lightning_bolt.tres`
```gdscript
[gd_resource type="Resource" script_class="Spell" load_steps=2 format=3]

[ext_resource type="Script" path="res://resources/spells/spell.gd" id="1_spell"]

[resource]
script = ExtResource("1_spell")
id = "lightning_bolt"
display_name = "Lightning Bolt"
description = "Strike your enemy with a bolt of lightning."
spell_type = 0  # Offensive
rarity = 2  # Rare
mana_cost = 35
cast_time = 0.5
cooldown = 2.0
spell_range = 10.0
target_type = 1  # Single Enemy
damage = 60
required_level = 8
```

### 2. Create Spell Book Item
File: `resources/items/templates/books/spellbook_lightning_bolt.tres`
```gdscript
[gd_resource type="Resource" script_class="ItemBook" load_steps=2 format=3]

[ext_resource type="Script" path="res://resources/items/item_book.gd" id="1_book"]

[resource]
script = ExtResource("1_book")
id = "spellbook_lightning_bolt"
display_name = "Scroll of Lightning"
description = "Teaches Lightning Bolt spell"
item_type = 7  # BOOK
rarity = 2  # Rare
weight = 1.5
base_value = 400
book_type = 2  # SPELL
spell_id = "lightning_bolt"
read_once = true
```

## TODO / Future Improvements

1. **Spell Casting Implementation**
   - Create projectiles/effects
   - Deal damage to targets
   - Apply status effects
   - Area of effect handling

2. **Spell Requirements**
   - Check player level
   - Check skill requirements
   - Visual feedback when requirements not met

3. **Spell Hotbar**
   - Quick access to equipped spells
   - Keyboard shortcuts (1-9)

4. **Spell Schools/Skills**
   - Pyromancy, Cryomancy, etc.
   - Skill progression affects spell power

5. **Mana Regeneration**
   - Add mana regen over time
   - Mana potions

6. **Book Reading UI**
   - Show `full_text` in a nice dialog
   - Lore books that don't teach spells

7. **Spell Animations**
   - Cast animations
   - Particle effects
   - Sound effects

## Key Files Reference

- **Spell Base**: `resources/spells/spell.gd`
- **Spell Templates**: `resources/spells/spell_templates/`
- **Book Item**: `resources/items/item_book.gd`
- **Book Templates**: `resources/items/templates/books/`
- **Player Spells**: `scripts/Player.gd` (lines ~47-50, ~620-699)
- **Spell Book UI**: `scripts/spell_book_screen.gd`
- **Inventory**: `scripts/inventory_screen.gd`
