# Inventory System Documentation

## Overview
The inventory system provides stackable item management for both Players and NPCs in the game. It supports item stacking, weight limits, slot limits, and easy serialization for save/load functionality.

## Features
- **Stackable Items**: Items marked as stackable will automatically stack up to their `max_stack` value
- **Weight Management**: Optional weight limits prevent carrying too much
- **Slot Limits**: Optional slot limits restrict inventory size
- **Signals**: Emits signals for inventory changes, items added/removed, and full inventory
- **Serialization**: Easy save/load with `to_dict()` and `from_dict()` methods
- **Sorting**: Built-in sorting by name, type, value, weight, or rarity
- **Transfer**: Methods to transfer items between inventories

## Usage

### For Player
The Player script automatically initializes an inventory in `_ready()`. You can configure it via export variables:
```gdscript
@export var inventory_slots: int = 20
@export var max_carry_weight: float = 100.0
```

### For NPCs
NPCs also get an inventory automatically initialized. Merchants get larger inventories:
- Regular NPCs: 10 slots, 50.0 weight limit
- Merchants: 30 slots, 200.0 weight limit

### Adding Items
```gdscript
# Add a single item
player.add_item_to_inventory(item, 1)

# Add multiple items (will stack if stackable)
player.add_item_to_inventory(item, 10)

# Check if successful
if player.add_item_to_inventory(item, 5):
    print("Added successfully!")
else:
    print("Inventory full!")
```

### Removing Items
```gdscript
# Remove items by ID
var removed_count = player.remove_item_from_inventory("potion_health", 3)
print("Removed %d items" % removed_count)

# Drop items into the world
player.drop_item("sword_iron", 1)
```

### Checking Items
```gdscript
# Check if player has an item
if player.has_item("key_tower", 1):
    print("You have the tower key!")

# Get item count
var potion_count = player.inventory.get_item_count("potion_health")
print("You have %d health potions" % potion_count)
```

### Picking Up Items
Items in the world (WorldItem) automatically call the player's inventory when picked up. The player just needs to walk over them if `auto_pickup = true`.

Manual pickup can be done with:
```gdscript
world_item.try_pickup(player)
```

### Accessing Inventory
```gdscript
# Get the inventory instance
var inv = player.get_inventory()

# Get all items
var all_items = inv.get_all_items()
for slot in all_items:
    print("%s x%d" % [slot.item.get_display_name(), slot.quantity])

# Sort inventory
inv.sort_by("name")  # Options: "name", "type", "value", "weight", "rarity"

# Get total weight and value
print("Total weight: %.1f kg" % inv.get_total_weight())
print("Total value: %d gold" % inv.get_total_value())
```

### Trading Between Entities
```gdscript
# Transfer item from player to NPC
player.inventory.transfer_to(npc.inventory, "gold_coin", 50)

# Transfer specific slot
player.inventory.transfer_slot_to(merchant.inventory, 0, 1)
```

### Save/Load
```gdscript
# Saving
var save_data = {
    "player_inventory": player.inventory.to_dict()
}

# Loading
player.inventory.from_dict(save_data.player_inventory)
```

## Item Configuration
Items must be configured with stacking properties in their resource:

```gdscript
# In item.gd or .tres file
@export var stackable: bool = true
@export var max_stack: int = 99
@export var weight: float = 0.5
```

Example stackable items:
- Potions: stackable=true, max_stack=99
- Arrows: stackable=true, max_stack=100
- Coins: stackable=true, max_stack=9999

Example non-stackable items:
- Weapons: stackable=false, max_stack=1
- Armor: stackable=false, max_stack=1
- Unique quest items: stackable=false, max_stack=1

## Signals
The Inventory class emits these signals:

```gdscript
signal inventory_changed  # When any change occurs
signal item_added(item: Item, quantity: int)  # When items are added
signal item_removed(item: Item, quantity: int)  # When items are removed
signal inventory_full  # When trying to add to full inventory
```

Connect to these for UI updates:
```gdscript
player.inventory.inventory_changed.connect(_update_inventory_ui)
player.inventory.inventory_full.connect(_show_full_message)
```

## Debug Methods
```gdscript
# Print inventory contents to console
player.inventory.print_inventory()

# Output example:
# [Inventory] Contents (5/20 slots, 15.5/100.0 weight):
#   [0] Health Potion x10 (0.5 kg each)
#   [1] Iron Sword x1 (5.0 kg each)
#   [2] Gold Coin x50 (0.0 kg each)
```

## Architecture
- **Inventory.gd**: The main inventory class (Node)
- **Item.gd**: Base item resource class with stacking properties
- **Player.gd**: Has inventory instance and helper methods
- **NPC.gd**: Has inventory instance and helper methods
- **WorldItem.gd**: Handles items in the game world and pickup logic
- **inventory_screen.gd**: UI screen for displaying and managing inventory

## Inventory Screen UI

The inventory screen provides a visual interface for managing the player's inventory.

### Opening the Inventory
- Press **I** or **Tab** to toggle the inventory screen
- Press **ESC** to close the inventory
- The game pauses automatically when the inventory is open

### Features
- **Grid Display**: Shows all items with icons colored by rarity
- **Item Details**: Click an item to see its full description and stats
- **Sorting**: Sort inventory by Name, Type, Value, Weight, or Rarity
- **Weight/Value Display**: Shows current and maximum weight, plus total value
- **Actions**:
  - **Use**: Use consumable items (potions, food, etc.)
  - **Drop**: Drop items into the world (with quantity selector for stacks)

### Rarity Colors
- **White**: Common items
- **Green**: Uncommon items
- **Blue**: Rare items
- **Purple**: Epic items
- **Orange**: Legendary items
- **Gold**: Unique quest items

### Usage Example
```gdscript
# The inventory screen is automatically added to the player
# Press I or Tab in-game to open it

# To manually open from code:
player.inventory_screen.open_inventory(player.inventory)

# To close:
player.inventory_screen.close_inventory()
```
