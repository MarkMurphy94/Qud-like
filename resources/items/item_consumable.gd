extends Item
class_name ItemConsumable

## Consumable item resource for items that can be used and depleted.

enum ConsumableEffect {
	HEAL,
	RESTORE_STAMINA,
	RESTORE_MANA,
	BUFF_STRENGTH,
	BUFF_AGILITY,
	BUFF_DEFENSE,
	CURE_POISON,
	CURE_ALL,
	FOOD,
	DRINK,
	ANTIDOTE,
	SCROLL  ## One-time use spells
}

## Consumable-specific properties
@export var effect_type: ConsumableEffect = ConsumableEffect.HEAL
@export var effect_value: int = 10
@export var duration: float = 0.0  ## 0 = instant effect
@export var hunger_restore: int = 0  ## For food items
@export var thirst_restore: int = 0  ## For drink items

## For scrolls/special items
@export var spell_id: String = ""


func _init():
	item_type = ItemType.CONSUMABLE
	stackable = true
	max_stack = 20


## Returns the actual effect value with any modifiers
func get_effect_value() -> int:
	var bonus = modifiers.get("effect_bonus", 0)
	return effect_value + bonus


## Returns true if this consumable has a duration (buff)
func is_buff() -> bool:
	return duration > 0.0


## Returns true if this is a food item
func is_food() -> bool:
	return effect_type == ConsumableEffect.FOOD or hunger_restore > 0


## Returns true if this is a drink item
func is_drink() -> bool:
	return effect_type == ConsumableEffect.DRINK or thirst_restore > 0


## Returns a formatted string describing the consumable's effects
func get_stats_description() -> String:
	var lines: PackedStringArray = []
	
	match effect_type:
		ConsumableEffect.HEAL:
			lines.append("Restores %d Health" % get_effect_value())
		ConsumableEffect.RESTORE_STAMINA:
			lines.append("Restores %d Stamina" % get_effect_value())
		ConsumableEffect.RESTORE_MANA:
			lines.append("Restores %d Mana" % get_effect_value())
		ConsumableEffect.BUFF_STRENGTH:
			lines.append("+%d Strength" % get_effect_value())
		ConsumableEffect.BUFF_AGILITY:
			lines.append("+%d Agility" % get_effect_value())
		ConsumableEffect.BUFF_DEFENSE:
			lines.append("+%d Defense" % get_effect_value())
		ConsumableEffect.CURE_POISON:
			lines.append("Cures Poison")
		ConsumableEffect.CURE_ALL:
			lines.append("Cures All Ailments")
		ConsumableEffect.ANTIDOTE:
			lines.append("Cures Poison")
		ConsumableEffect.SCROLL:
			lines.append("Casts: %s" % spell_id.capitalize())
		ConsumableEffect.FOOD, ConsumableEffect.DRINK:
			pass  ## Handled below
	
	if hunger_restore > 0:
		lines.append("Restores %d Hunger" % hunger_restore)
	if thirst_restore > 0:
		lines.append("Restores %d Thirst" % thirst_restore)
	
	if duration > 0:
		lines.append("Duration: %.1f seconds" % duration)
	
	return "\n".join(lines)
