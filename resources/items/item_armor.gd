extends Item
class_name ItemArmor

## Armor item resource with defensive properties.

enum ArmorType {
	HEAD,
	CHEST,
	LEGS,
	FEET,
	HANDS,
	SHIELD,
	ACCESSORY
}

enum ArmorWeight {
	CLOTH,
	LIGHT,
	MEDIUM,
	HEAVY
}

## Armor-specific properties
@export var armor_type: ArmorType = ArmorType.CHEST
@export var armor_weight: ArmorWeight = ArmorWeight.LIGHT
@export var base_defense: int = 5
@export var magic_resistance: int = 0

## Resistances (percentage reduction)
@export var fire_resistance: float = 0.0
@export var ice_resistance: float = 0.0
@export var lightning_resistance: float = 0.0
@export var poison_resistance: float = 0.0

## Movement penalty for heavy armor (multiplier, 1.0 = no penalty)
@export var movement_modifier: float = 1.0


func _init():
	item_type = ItemType.ARMOR


## Returns the actual defense with modifiers
func get_defense() -> int:
	var defense_bonus = modifiers.get("defense_bonus", 0)
	return base_defense + defense_bonus


## Returns the actual magic resistance with modifiers
func get_magic_resistance() -> int:
	var mr_bonus = modifiers.get("magic_resistance_bonus", 0)
	return magic_resistance + mr_bonus


## Returns a formatted string describing the armor's stats
func get_stats_description() -> String:
	var lines: PackedStringArray = []
	lines.append("Defense: %d" % get_defense())
	
	if get_magic_resistance() > 0:
		lines.append("Magic Resist: %d" % get_magic_resistance())
	
	if fire_resistance > 0:
		lines.append("Fire Resist: %.0f%%" % fire_resistance)
	if ice_resistance > 0:
		lines.append("Ice Resist: %.0f%%" % ice_resistance)
	if lightning_resistance > 0:
		lines.append("Lightning Resist: %.0f%%" % lightning_resistance)
	if poison_resistance > 0:
		lines.append("Poison Resist: %.0f%%" % poison_resistance)
	
	if movement_modifier != 1.0:
		if movement_modifier < 1.0:
			lines.append("Movement: -%.0f%%" % ((1.0 - movement_modifier) * 100))
		else:
			lines.append("Movement: +%.0f%%" % ((movement_modifier - 1.0) * 100))
	
	lines.append("Weight: %s" % ArmorWeight.keys()[armor_weight].capitalize())
	
	return "\n".join(lines)


## Returns the slot name for equipment UI
func get_slot_name() -> String:
	return ArmorType.keys()[armor_type].capitalize()
