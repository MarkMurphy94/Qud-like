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

func _ready():
	rng.randomize()


## Generate a weapon from a template.
##
## Every roll comes from an RNG local to this call, seeded by `seed_value` (or a
## seed drawn from the shared rng when none is given), so the shared rng is
## never reseeded and the item can be rebuilt from {template_id, rarity,
## gen_seed}. Rarity is always rolled, even when forced, so a forced rebuild
## consumes the RNG exactly as the original roll did.
## `spawn_id` names where the item was spawned and becomes part of its id.
func generate_weapon(template_id: String, forced_rarity: int = -1, seed_value: int = -1, spawn_id: String = "") -> ItemWeapon:
	var template = ItemDatabase.get_weapon_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown weapon template: %s" % template_id)
		return null

	var item: ItemWeapon = template.duplicate(true)
	var gen_rng := _begin_generation(item, template_id, seed_value, spawn_id)

	var rolled := _roll_rarity(gen_rng)
	var rarity = forced_rarity if forced_rarity >= 0 else rolled
	item.rarity = rarity

	_apply_weapon_modifiers(item, rarity, gen_rng)

	var rarity_multiplier = 1.0 + (rarity * 0.2)
	item.base_damage = int(item.base_damage * rarity_multiplier)
	item.base_value = int(item.base_value * rarity_multiplier * rarity_multiplier)

	return item


## Generate armor from a template. Same seeding contract as generate_weapon.
func generate_armor(template_id: String, forced_rarity: int = -1, seed_value: int = -1, spawn_id: String = "") -> ItemArmor:
	var template = ItemDatabase.get_armor_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown armor template: %s" % template_id)
		return null

	var item: ItemArmor = template.duplicate(true)
	var gen_rng := _begin_generation(item, template_id, seed_value, spawn_id)

	var rolled := _roll_rarity(gen_rng)
	var rarity = forced_rarity if forced_rarity >= 0 else rolled
	item.rarity = rarity

	_apply_armor_modifiers(item, rarity, gen_rng)

	var rarity_multiplier = 1.0 + (rarity * 0.2)
	item.base_defense = int(item.base_defense * rarity_multiplier)
	item.base_value = int(item.base_value * rarity_multiplier * rarity_multiplier)

	return item


## Generate a consumable from a template (consumables don't get modifiers, so
## they are plain copies and need no seed to rebuild).
func generate_consumable(template_id: String) -> ItemConsumable:
	var template = ItemDatabase.get_consumable_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown consumable template: %s" % template_id)
		return null
	return _plain_copy(template, template_id)


## Generate a material from a template
func generate_material(template_id: String) -> Item:
	var template = ItemDatabase.get_material_template(template_id)
	if not template:
		push_warning("[ItemGenerator] Unknown material template: %s" % template_id)
		return null
	return _plain_copy(template, template_id)


## Build any template by id, dispatching on the template folder it was loaded
## from. Books, materials and consumables ignore rarity and seed.
func generate_from_template(template_id: String, rarity: int = -1, seed_value: int = -1, spawn_id: String = "") -> Item:
	if ItemDatabase.weapon_templates.has(template_id):
		return generate_weapon(template_id, rarity, seed_value, spawn_id)
	if ItemDatabase.armor_templates.has(template_id):
		return generate_armor(template_id, rarity, seed_value, spawn_id)
	if ItemDatabase.consumable_templates.has(template_id):
		return generate_consumable(template_id)
	if ItemDatabase.material_templates.has(template_id):
		return generate_material(template_id)
	if ItemDatabase.has_item(template_id):
		return ItemDatabase.get_item(template_id)
	push_warning("[ItemGenerator] Unknown template: %s" % template_id)
	return null


func _begin_generation(item: Item, template_id: String, seed_value: int, spawn_id: String) -> RandomNumberGenerator:
	if seed_value < 0:
		seed_value = rng.randi() & 0x7FFFFFFF
	item.template_id = template_id
	item.gen_seed = seed_value
	item.id = _generated_id(item, template_id, spawn_id)
	var gen_rng := RandomNumberGenerator.new()
	gen_rng.seed = seed_value
	return gen_rng


func _plain_copy(template: Item, template_id: String) -> Item:
	var item: Item = template.duplicate(true)
	item.template_id = template_id
	item.id = template_id
	item.gen_seed = -1
	return item


## Stackable items keep the template id so they still stack with each other.
## Anything else is unique per spawn — or per seed when spawned outside a place.
func _generated_id(item: Item, template_id: String, spawn_id: String) -> String:
	if item.stackable:
		return template_id
	if not spawn_id.is_empty():
		return "%s#%s" % [spawn_id, template_id]
	return "%s#%d" % [template_id, item.gen_seed]


# ═══════════════════════════════════════════════════════════════════════
#  SAVE RECORDS
# ═══════════════════════════════════════════════════════════════════════

## Everything needed to rebuild `item` later. Generated items are rebuilt from
## their seed rather than serialised field by field.
func item_to_record(item: Item, quantity: int = 1) -> Dictionary:
	var record := {
		"template_id": item.template_id if not item.template_id.is_empty() else item.id,
		"id": item.id,
		"rarity": int(item.rarity),
		"gen_seed": item.gen_seed,
		"quantity": quantity,
	}
	if not item.provenance.is_empty():
		record["provenance"] = item.provenance.duplicate(true)
	return record


## Rebuild an item from item_to_record() output. Also accepts the pre-v3
## inventory shape {item_id, quantity, modifiers}.
func item_from_record(record: Dictionary) -> Item:
	if not record.has("template_id"):
		return _item_from_legacy_record(record)

	var template_id: String = record["template_id"]
	var gen_seed := int(record.get("gen_seed", -1))
	var item: Item
	if gen_seed >= 0:
		item = generate_from_template(template_id, int(record.get("rarity", -1)), gen_seed)
	else:
		item = ItemDatabase.get_item(template_id)
	if item == null:
		return null
	item.id = String(record.get("id", item.id))
	if record.has("provenance"):
		item.provenance = (record["provenance"] as Dictionary).duplicate(true)
	return item


## Pre-v3 saves stored generated items under their "<template>_<unix>_<n>" id,
## which ItemDatabase cannot resolve. Recover the template from the id and keep
## the saved modifiers; the rarity was never saved, so it stays Common.
func _item_from_legacy_record(record: Dictionary) -> Item:
	var item_id := String(record.get("item_id", ""))
	var item: Item = null
	if ItemDatabase.has_item(item_id):
		item = ItemDatabase.get_item(item_id)
	else:
		var found := RegEx.create_from_string("^(.+)_\\d+_\\d+$").search(item_id)
		if found and ItemDatabase.has_item(found.get_string(1)):
			item = ItemDatabase.get_item(found.get_string(1))
			item.id = item_id
			push_warning("[ItemGenerator] Recovered legacy generated item %s from its template" % item_id)
	if item == null:
		push_warning("[ItemGenerator] Could not restore legacy item %s" % item_id)
		return null
	if record.has("modifiers"):
		item.modifiers = (record["modifiers"] as Dictionary).duplicate(true)
	return item


## Roll a random rarity based on weights
func _roll_rarity(r: RandomNumberGenerator) -> Item.Rarity:
	var total_weight = 0
	for weight in RARITY_WEIGHTS.values():
		total_weight += weight
	
	var roll = r.randi_range(0, total_weight - 1)
	var cumulative = 0
	
	for rarity in RARITY_WEIGHTS:
		cumulative += RARITY_WEIGHTS[rarity]
		if roll < cumulative:
			return rarity
	
	return Item.Rarity.COMMON


## Rarity for a spawn roll. Each tier above the first and each point of
## `rarity_bias` add to the chance of stepping one rarity up. The upgrade roll
## is always drawn, so the RNG advances the same way whatever the outcome.
func roll_rarity(r: RandomNumberGenerator, tier: int = SpawnTier.DEFAULT_TIER, rarity_bias: float = 0.0) -> Item.Rarity:
	var rarity: int = _roll_rarity(r)
	var upgrade_chance := clampf(0.05 * maxi(tier - 1, 0) + 0.25 * rarity_bias, 0.0, 0.9)
	var upgrade_roll := r.randf()
	if rarity < Item.Rarity.LEGENDARY and upgrade_roll < upgrade_chance:
		rarity += 1
	return rarity as Item.Rarity


## Apply modifiers to a weapon based on rarity
func _apply_weapon_modifiers(item: ItemWeapon, rarity: Item.Rarity, r: RandomNumberGenerator) -> void:
	if rarity == Item.Rarity.COMMON:
		return
	
	# Ensure rarity exists in our dictionaries
	if not WEAPON_PREFIXES.has(rarity):
		return
	
	# Chance for prefix (increases with rarity)
	var prefix_chance = 0.5 + (rarity * 0.1)
	if WEAPON_PREFIXES[rarity].size() > 0 and r.randf() < prefix_chance:
		var prefix = WEAPON_PREFIXES[rarity][r.randi() % WEAPON_PREFIXES[rarity].size()]
		_apply_modifier_dict(item, prefix)
	
	# Chance for suffix (lower than prefix)
	var suffix_chance = 0.3 + (rarity * 0.1)
	if WEAPON_SUFFIXES[rarity].size() > 0 and r.randf() < suffix_chance:
		var suffix = WEAPON_SUFFIXES[rarity][r.randi() % WEAPON_SUFFIXES[rarity].size()]
		_apply_modifier_dict(item, suffix, true)


## Apply modifiers to armor based on rarity
func _apply_armor_modifiers(item: ItemArmor, rarity: Item.Rarity, r: RandomNumberGenerator) -> void:
	if rarity == Item.Rarity.COMMON:
		return
	
	if not ARMOR_PREFIXES.has(rarity):
		return
	
	var prefix_chance = 0.5 + (rarity * 0.1)
	if ARMOR_PREFIXES[rarity].size() > 0 and r.randf() < prefix_chance:
		var prefix = ARMOR_PREFIXES[rarity][r.randi() % ARMOR_PREFIXES[rarity].size()]
		_apply_modifier_dict(item, prefix)
	
	var suffix_chance = 0.3 + (rarity * 0.1)
	if ARMOR_SUFFIXES[rarity].size() > 0 and r.randf() < suffix_chance:
		var suffix = ARMOR_SUFFIXES[rarity][r.randi() % ARMOR_SUFFIXES[rarity].size()]
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
