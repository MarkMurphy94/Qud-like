extends Item
class_name ItemWeapon

## Weapon item resource with combat-specific properties.

enum WeaponType {
	SWORD,
	AXE,
	MACE,
	DAGGER,
	SPEAR,
	BOW,
	STAFF,
	UNARMED
}

enum DamageType {
	PHYSICAL,
	FIRE,
	ICE,
	LIGHTNING,
	POISON
}

## Weapon-specific properties
@export var weapon_type: WeaponType = WeaponType.SWORD
@export var damage_type: DamageType = DamageType.PHYSICAL
@export var base_damage: int = 5
@export var damage_variance: int = 2  ## damage = base ± variance
@export var attack_speed: float = 1.0
@export var range_tiles: int = 1
@export var crit_chance: float = 5.0  ## Percentage
@export var crit_multiplier: float = 1.5

## Two-handed weapons can't be used with shields
@export var two_handed: bool = false


func _init():
	item_type = ItemType.WEAPON


## Returns the minimum and maximum damage as a Vector2i
func get_damage_range() -> Vector2i:
	var damage_bonus = modifiers.get("damage_bonus", 0)
	var min_dmg = max(1, base_damage - damage_variance + damage_bonus)
	var max_dmg = base_damage + damage_variance + damage_bonus
	return Vector2i(min_dmg, max_dmg)


## Returns the actual attack speed with modifiers
func get_attack_speed() -> float:
	var speed_bonus = modifiers.get("attack_speed_bonus", 0.0)
	return attack_speed + speed_bonus


## Returns the actual crit chance with modifiers
func get_crit_chance() -> float:
	var crit_bonus = modifiers.get("crit_bonus", 0.0)
	return crit_chance + crit_bonus


## Rolls a damage value within the weapon's range
func roll_damage(rng: RandomNumberGenerator = null) -> int:
	var range = get_damage_range()
	if rng:
		return rng.randi_range(range.x, range.y)
	else:
		return randi_range(range.x, range.y)


## Returns a formatted string describing the weapon's stats
func get_stats_description() -> String:
	var damage_range = get_damage_range()
	var lines: PackedStringArray = []
	lines.append("Damage: %d-%d" % [damage_range.x, damage_range.y])
	lines.append("Attack Speed: %.1f" % get_attack_speed())
	lines.append("Range: %d" % range_tiles)
	lines.append("Crit: %.0f%% (x%.1f)" % [get_crit_chance(), crit_multiplier])
	
	if damage_type != DamageType.PHYSICAL:
		lines.append("Damage Type: %s" % DamageType.keys()[damage_type].capitalize())
	
	# Add any special modifiers
	if modifiers.has("fire_damage"):
		lines.append("+%d Fire Damage" % modifiers["fire_damage"])
	if modifiers.has("ice_damage"):
		lines.append("+%d Ice Damage" % modifiers["ice_damage"])
	if modifiers.has("lifesteal"):
		lines.append("Lifesteal")
	
	return "\n".join(lines)
