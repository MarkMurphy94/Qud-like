extends Node

## ItemGenerator - Autoload singleton for procedural item generation.
## Creates randomized items from templates with modifiers based on rarity.

var rng := RandomNumberGenerator.new()

## Modifier pools for weapon prefixes
const WEAPON_PREFIXES = {
	Item.Rarity.COMMON: [],
	Item.Rarity.UNCOMMON: [
		{"name": "Sharp", "damage_bonus": 1},
		{"name": "Sturdy", "durability_bonus": 10},
		{"name": "Light", "attack_speed_bonus": 0.1},
	],
	Item.Rarity.RARE: [
		{"name": "Keen", "damage_bonus": 2, "crit_bonus": 5},
		{"name": "Hardened", "damage_bonus": 1, "defense_bonus": 2},
		{"name": "Swift", "attack_speed_bonus": 0.2},
		{"name": "Vicious", "damage_bonus": 3},
	],
	Item.Rarity.EPIC: [
		{"name": "Masterwork", "damage_bonus": 4, "crit_bonus": 10},
		{"name": "Ancient", "damage_bonus": 3, "special": "lifesteal"},
		{"name": "Blazing", "damage_bonus": 2, "fire_damage": 5},
		{"name": "Frozen", "damage_bonus": 2, "ice_damage": 5},
	],
	Item.Rarity.LEGENDARY: [
		{"name": "Godslayer", "damage_bonus": 6, "crit_bonus": 15, "special": "execute"},
		{"name": "Soulreaver", "damage_bonus": 5, "special": "lifesteal", "fire_damage": 8},
		{"name": "Worldbreaker", "damage_bonus": 8, "attack_speed_bonus": -0.2},
	],
}

## Modifier pools for weapon suffixes
const WEAPON_SUFFIXES = {
	Item.Rarity.COMMON: [],
	Item.Rarity.UNCOMMON: [
		{"name": "of Striking", "attack_speed_bonus": 0.1},
		{"name": "of Might", "damage_bonus": 1},
	],
	Item.Rarity.RARE: [
		{"name": "of Slaying", "damage_bonus": 2},
		{"name": "of Speed", "attack_speed_bonus": 0.2},
		{"name": "of Precision", "crit_bonus": 8},
	],
	Item.Rarity.EPIC: [
		{"name": "of the Dragon", "damage_bonus": 3, "fire_damage": 5},
		{"name": "of the Frost Giant", "damage_bonus": 3, "ice_damage": 5},
		{"name": "of Devastation", "damage_bonus": 4, "crit_bonus": 10},
	],
	Item.Rarity.LEGENDARY: [
		{"name": "of the Ancients", "damage_bonus": 5, "crit_bonus": 15, "attack_speed_bonus": 0.15},
		{"name": "of Annihilation", "damage_bonus": 8},
	],
}

## Modifier pools for armor prefixes
const ARMOR_PREFIXES = {
	Item.Rarity.COMMON: [],
	Item.Rarity.UNCOMMON: [
		{"name": "Reinforced", "defense_bonus": 2},
		{"name": "Padded", "defense_bonus": 1, "movement_bonus": 0.05},
	],
	Item.Rarity.RARE: [
		{"name": "Fortified", "defense_bonus": 4},
		{"name": "Enchanted", "defense_bonus": 2, "magic_resistance_bonus": 3},
		{"name": "Nimble", "defense_bonus": 1, "movement_bonus": 0.1},
	],
	Item.Rarity.EPIC: [
		{"name": "Dragonscale", "defense_bonus": 6, "fire_resistance": 15.0},
		{"name": "Frostforged", "defense_bonus": 5, "ice_resistance": 15.0},
		{"name": "Runic", "defense_bonus": 4, "magic_resistance_bonus": 8},
	],
	Item.Rarity.LEGENDARY: [
		{"name": "Godforged", "defense_bonus": 10, "magic_resistance_bonus": 10},
		{"name": "Primordial", "defense_bonus": 8, "fire_resistance": 20.0, "ice_resistance": 20.0},
	],
}

## Armor suffixes
const ARMOR_SUFFIXES = {
	Item.Rarity.COMMON: [],
	Item.Rarity.UNCOMMON: [
		{"name": "of Protection", "defense_bonus": 1},
	],
	Item.Rarity.RARE: [
		{"name": "of the Guardian", "defense_bonus": 3},
		{"name": "of Warding", "magic_resistance_bonus": 4},
	],
	Item.Rarity.EPIC: [
		{"name": "of the Fortress", "defense_bonus": 5},
		{"name": "of Immunity", "poison_resistance": 25.0},
	],
	Item.Rarity.LEGENDARY: [
		{"name": "of the Immortal", "defense_bonus": 8, "special": "regeneration"},
	],
}

## Rarity weights for random rolling
const RARITY_WEIGHTS = {
	Item.Rarity.COMMON: 60,
	Item.Rarity.UNCOMMON: 25,
	Item.Rarity.RARE: 10,
	Item.Rarity.EPIC: 4,
	Item.Rarity.LEGENDARY: 1,
}

## Unique ID counter for generated items
var _item_counter: int = 0


func _ready():
	rng.randomize()


## Generate a weapon from a template
## template_id: The ID of the weapon template to use
## forced_rarity: Force a specific rarity (-1 for random)
## seed_value: Seed for deterministic generation (-1 for random)
func generate_weapon(template_id: String, forced_rarity: int = -1, seed_value: int = -1) -> ItemWeapon:
	if seed_value >= 0:
		rng.seed = seed_value
	
	var template = ItemDatabase.get_weapon_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown weapon template: %s" % template_id)
		return null
	
	# Duplicate template to create new instance
	var item: ItemWeapon = template.duplicate(true)
	_item_counter += 1
	item.id = "%s_%d_%d" % [template_id, Time.get_unix_time_from_system(), _item_counter]
	
	# Determine rarity
	var rarity = forced_rarity if forced_rarity >= 0 else _roll_rarity()
	item.rarity = rarity
	
	# Apply modifiers based on rarity
	_apply_weapon_modifiers(item, rarity)
	
	# Scale base stats by rarity
	var rarity_multiplier = 1.0 + (rarity * 0.2)
	item.base_damage = int(item.base_damage * rarity_multiplier)
	item.base_value = int(item.base_value * rarity_multiplier * rarity_multiplier)
	
	return item


## Generate armor from a template
func generate_armor(template_id: String, forced_rarity: int = -1, seed_value: int = -1) -> ItemArmor:
	if seed_value >= 0:
		rng.seed = seed_value
	
	var template = ItemDatabase.get_armor_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown armor template: %s" % template_id)
		return null
	
	var item: ItemArmor = template.duplicate(true)
	_item_counter += 1
	item.id = "%s_%d_%d" % [template_id, Time.get_unix_time_from_system(), _item_counter]
	
	var rarity = forced_rarity if forced_rarity >= 0 else _roll_rarity()
	item.rarity = rarity
	
	_apply_armor_modifiers(item, rarity)
	
	var rarity_multiplier = 1.0 + (rarity * 0.2)
	item.base_defense = int(item.base_defense * rarity_multiplier)
	item.base_value = int(item.base_value * rarity_multiplier * rarity_multiplier)
	
	return item


## Generate a consumable from a template (consumables don't get modifiers by default)
func generate_consumable(template_id: String) -> ItemConsumable:
	var template = ItemDatabase.get_consumable_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown consumable template: %s" % template_id)
		return null
	
	var item: ItemConsumable = template.duplicate(true)
	_item_counter += 1
	item.id = "%s_%d_%d" % [template_id, Time.get_unix_time_from_system(), _item_counter]
	return item


## Generate a material from a template
func generate_material(template_id: String) -> Item:
	var template = ItemDatabase.get_material_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown material template: %s" % template_id)
		return null
	
	var item: Item = template.duplicate(true)
	_item_counter += 1
	item.id = "%s_%d_%d" % [template_id, Time.get_unix_time_from_system(), _item_counter]
	return item


## Generate a random weapon
func generate_random_weapon(forced_rarity: int = -1) -> ItemWeapon:
	var templates = ItemDatabase.get_weapon_template_ids()
	if templates.is_empty():
		push_warning("[ItemGenerator] No weapon templates available")
		return null
	
	var template_id = templates[rng.randi() % templates.size()]
	return generate_weapon(template_id, forced_rarity)


## Generate a random armor piece
func generate_random_armor(forced_rarity: int = -1) -> ItemArmor:
	var templates = ItemDatabase.get_armor_template_ids()
	if templates.is_empty():
		push_warning("[ItemGenerator] No armor templates available")
		return null
	
	var template_id = templates[rng.randi() % templates.size()]
	return generate_armor(template_id, forced_rarity)


## Generate loot drops for an enemy
## enemy_level: Used to adjust drop quality
## loot_table: Name of the loot table to use (for future expansion)
func generate_loot_drop(enemy_level: int = 1, loot_table: String = "default") -> Array[Item]:
	var drops: Array[Item] = []
	
	# Number of drops scales slightly with level
	var max_drops = 1 + (enemy_level / 5)
	var num_drops = rng.randi_range(0, max_drops)
	
	for i in num_drops:
		var roll = rng.randf()
		
		if roll < 0.4:
			# 40% chance for consumable
			var consumable_templates = ItemDatabase.get_consumable_template_ids()
			if not consumable_templates.is_empty():
				var template_id = consumable_templates[rng.randi() % consumable_templates.size()]
				var item = generate_consumable(template_id)
				if item:
					drops.append(item)
		elif roll < 0.6:
			# 20% chance for material
			var material_templates = ["iron_scrap", "leather", "cloth"]  # Add more as needed
			var has_templates = false
			for t in material_templates:
				if ItemDatabase.has_weapon_template(t):  # Check if any exist
					has_templates = true
					break
			if has_templates:
				var item = generate_material(material_templates[rng.randi() % material_templates.size()])
				if item:
					drops.append(item)
		elif roll < 0.85:
			# 25% chance for weapon
			var item = generate_random_weapon()
			if item:
				drops.append(item)
		else:
			# 15% chance for armor
			var item = generate_random_armor()
			if item:
				drops.append(item)
	
	return drops


## Roll a random rarity based on weights
func _roll_rarity() -> Item.Rarity:
	var total_weight = 0
	for weight in RARITY_WEIGHTS.values():
		total_weight += weight
	
	var roll = rng.randi_range(0, total_weight - 1)
	var cumulative = 0
	
	for rarity in RARITY_WEIGHTS:
		cumulative += RARITY_WEIGHTS[rarity]
		if roll < cumulative:
			return rarity
	
	return Item.Rarity.COMMON


## Roll rarity with level bonus
func _roll_rarity_with_level(level: int) -> Item.Rarity:
	# Higher levels slightly increase chance of better items
	var bonus_roll = level * 0.5  # Each level adds 0.5 to the roll
	var base_rarity = _roll_rarity()
	
	# Small chance to upgrade rarity based on level
	if rng.randf() * 100 < bonus_roll and base_rarity < Item.Rarity.LEGENDARY:
		return base_rarity + 1
	
	return base_rarity


## Apply modifiers to a weapon based on rarity
func _apply_weapon_modifiers(item: ItemWeapon, rarity: Item.Rarity) -> void:
	if rarity == Item.Rarity.COMMON:
		return
	
	# Ensure rarity exists in our dictionaries
	if not WEAPON_PREFIXES.has(rarity):
		return
	
	# Chance for prefix (increases with rarity)
	var prefix_chance = 0.5 + (rarity * 0.1)
	if WEAPON_PREFIXES[rarity].size() > 0 and rng.randf() < prefix_chance:
		var prefix = WEAPON_PREFIXES[rarity][rng.randi() % WEAPON_PREFIXES[rarity].size()]
		_apply_modifier_dict(item, prefix)
	
	# Chance for suffix (lower than prefix)
	var suffix_chance = 0.3 + (rarity * 0.1)
	if WEAPON_SUFFIXES[rarity].size() > 0 and rng.randf() < suffix_chance:
		var suffix = WEAPON_SUFFIXES[rarity][rng.randi() % WEAPON_SUFFIXES[rarity].size()]
		_apply_modifier_dict(item, suffix, true)


## Apply modifiers to armor based on rarity
func _apply_armor_modifiers(item: ItemArmor, rarity: Item.Rarity) -> void:
	if rarity == Item.Rarity.COMMON:
		return
	
	if not ARMOR_PREFIXES.has(rarity):
		return
	
	var prefix_chance = 0.5 + (rarity * 0.1)
	if ARMOR_PREFIXES[rarity].size() > 0 and rng.randf() < prefix_chance:
		var prefix = ARMOR_PREFIXES[rarity][rng.randi() % ARMOR_PREFIXES[rarity].size()]
		_apply_modifier_dict(item, prefix)
	
	var suffix_chance = 0.3 + (rarity * 0.1)
	if ARMOR_SUFFIXES[rarity].size() > 0 and rng.randf() < suffix_chance:
		var suffix = ARMOR_SUFFIXES[rarity][rng.randi() % ARMOR_SUFFIXES[rarity].size()]
		_apply_modifier_dict(item, suffix, true)


## Apply a modifier dictionary to an item
func _apply_modifier_dict(item: Item, modifier: Dictionary, is_suffix: bool = false) -> void:
	for key in modifier:
		if key == "name":
			if is_suffix:
				item.modifiers["suffix"] = modifier["name"]
			else:
				item.modifiers["prefix"] = modifier["name"]
		else:
			# Stack modifiers if they already exist
			if item.modifiers.has(key):
				if typeof(item.modifiers[key]) == TYPE_STRING:
					# Don't stack string modifiers, just overwrite
					item.modifiers[key] = modifier[key]
				else:
					item.modifiers[key] += modifier[key]
			else:
				item.modifiers[key] = modifier[key]


## Set the random seed for deterministic generation
func set_seed(seed_value: int) -> void:
	rng.seed = seed_value


## Randomize the seed
func randomize_seed() -> void:
	rng.randomize()
