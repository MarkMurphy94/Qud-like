extends Node

## Item spawning checks. Open scenes/tests/spawn_determinism_test.tscn and press
## F6; results go to the Output panel. Extended phase by phase.

var _failures: int = 0


func _ready() -> void:
	_check_tags()
	_check_records()
	_check_tables_loaded()
	_check_validation()
	_check_resolver_determinism()
	_check_resolve_once()
	_check_fixed_item_rarity()
	print("[SpawnTest] Done — %d failure(s)" % _failures)


func _check_tags() -> void:
	var weapons := ItemDatabase.find_by_tags(["kind.weapon"])
	print("[SpawnTest] kind.weapon -> %s" % [weapons])
	var templates := ItemDatabase.get_weapon_template_ids()
	for template_id in templates:
		_expect(template_id in weapons, "weapon template %s is tagged kind.weapon" % template_id)

	var random_weapons := ItemDatabase.find_by_tags(["kind.weapon"], [ItemDatabase.UNIQUE_TAG])
	_expect(random_weapons.size() == templates.size(), "excluding kind.unique leaves only templates")
	_expect(not "blade_of_dawn" in random_weapons, "blade_of_dawn excluded from random queries")

	print("[SpawnTest] kind.material -> %s" % [ItemDatabase.find_by_tags(["kind.material"])])
	print("[SpawnTest] material.iron -> %s" % [ItemDatabase.find_by_tags(["material.iron"])])
	for item_id: String in ItemDatabase.all_items:
		var item: Item = ItemDatabase.all_items[item_id]
		_expect(not item.tags.is_empty(), "%s has tags" % item_id)
		_expect(item.duplicate_item().tags == item.tags, "%s keeps tags through duplicate_item" % item_id)


func _check_records() -> void:
	var shared_before := ItemGenerator.rng.state
	var sword := ItemGenerator.generate_weapon("basic_sword", -1, 12345, "test_place/b0.container.0/0")
	_expect(ItemGenerator.rng.state == shared_before, "seeded generation leaves the shared rng alone")
	var again := ItemGenerator.generate_weapon("basic_sword", -1, 12345, "test_place/b0.container.0/0")
	_expect(_same_item(sword, again), "same seed builds the same sword")
	_expect(sword.id == "test_place/b0.container.0/0#basic_sword", "sword id derives from spawn id (%s)" % sword.id)

	for rarity in [Item.Rarity.COMMON, Item.Rarity.RARE, Item.Rarity.LEGENDARY]:
		var armor := ItemGenerator.generate_armor("chainmail", rarity, 777 + rarity)
		var rebuilt := ItemGenerator.item_from_record(ItemGenerator.item_to_record(armor))
		_expect(_same_item(armor, rebuilt), "chainmail rarity %d survives a record round-trip" % rarity)
	var rebuilt_sword := ItemGenerator.item_from_record(ItemGenerator.item_to_record(sword))
	_expect(_same_item(sword, rebuilt_sword), "sword survives a record round-trip")

	var bread := ItemGenerator.generate_consumable("bread")
	_expect(bread.id == "bread", "stackable items keep the template id")

	var inv := Inventory.new()
	inv.add_item(sword, 1)
	inv.add_item(bread, 3)
	inv.add_item(ItemGenerator.generate_consumable("bread"), 2)
	var restored := Inventory.new()
	restored.from_dict(inv.to_dict())
	_expect(restored.get_slot_count() == 2, "bread stacks and the sword keeps its own slot")
	_expect(restored.get_item_count("bread") == 5, "bread quantity survives save/load")
	_expect(_same_item(restored.get_item_by_id(sword.id), sword), "generated sword survives Inventory save/load")

	var legacy := ItemGenerator.item_from_record({"item_id": "basic_sword_1730000000_4", "quantity": 1, "modifiers": {"prefix": "Sharp", "damage_bonus": 1}})
	_expect(legacy != null and legacy.template_id == "basic_sword", "pre-v3 generated id recovers its template")
	_expect(legacy != null and legacy.get_display_name() == "Sharp Sword", "pre-v3 record keeps its modifiers")

	var removed_items: Array = []
	inv.item_removed.connect(func(item: Item, _qty: int) -> void: removed_items.append(item))
	inv.remove_item(sword.id, 1)
	_expect(removed_items.size() == 1 and removed_items[0].id == sword.id, "removing the last generated item still emits item_removed")
	inv.free()
	restored.free()


const RUNS := 100

## Owner tags each owned table is normally resolved with.
const TABLE_OWNER_TAGS := {
	"owned.role.villager": ["role.villager"],
	"owned.role.bandit": ["role.bandit"],
	"owned.role.guard": ["role.guard"],
	"owned.role.merchant": ["role.merchant"],
	"owned.creature.beast": ["creature.beast"],
}


func _check_tables_loaded() -> void:
	print("[SpawnTest] Spawn tables: %s" % [ItemDatabase.spawn_tables.keys()])
	for table_id in ["owned.role.merchant", "owned.role.bandit", "owned.role.guard", "owned.role.villager",
			"owned.creature.beast", "ambient.wilderness", "ambient.ruin", "container.generic"]:
		_expect(ItemDatabase.has_spawn_table(table_id), "starter table %s loaded" % table_id)


## Feeds deliberately broken data through the load-time validator. The errors
## this prints are expected; only the [SpawnTest] FAIL lines matter.
func _check_validation() -> void:
	print("[SpawnTest] --- expected validation errors follow ---")
	var table := ItemSpawnTable.new()
	table.tier = "owned"
	var good := ItemSpawnEntry.new()
	good.item_id = "bread"
	var two_sources := ItemSpawnEntry.new()
	two_sources.item_id = "bread"
	two_sources.table_id = "container.generic"
	var no_source := ItemSpawnEntry.new()
	var bad_item := ItemSpawnEntry.new()
	bad_item.item_id = "no_such_item"
	var bad_table := ItemSpawnEntry.new()
	bad_table.table_id = "no.such.table"
	table.entries = [good, two_sources, no_source, bad_item, bad_table]
	ItemDatabase._validate_spawn_table(table, "test://bad_table.tres")
	_expect(table.entries.size() == 1 and table.entries[0] == good, "invalid entries are dropped, the valid one kept")

	var a := ItemSpawnTable.new()
	var b := ItemSpawnTable.new()
	var a_to_b := ItemSpawnEntry.new()
	a_to_b.table_id = "test.cycle.b"
	var b_to_a := ItemSpawnEntry.new()
	b_to_a.table_id = "test.cycle.a"
	a.entries = [a_to_b]
	b.entries = [b_to_a]
	ItemDatabase.spawn_tables["test.cycle.a"] = a
	ItemDatabase.spawn_tables["test.cycle.b"] = b
	ItemDatabase._report_spawn_table_cycles({})
	var ctx := SpawnContext.for_slot(_fake_place(1), "test")
	var results := ItemSpawnResolver.resolve("test.cycle.a", ctx)
	_expect(results.is_empty(), "resolving a cycle terminates")
	ItemDatabase.spawn_tables.erase("test.cycle.a")
	ItemDatabase.spawn_tables.erase("test.cycle.b")
	print("[SpawnTest] --- end of expected errors ---")


func _check_resolver_determinism() -> void:
	var shared_before := ItemGenerator.rng.state
	for table_id: String in ItemDatabase.spawn_tables:
		var first := _resolve_runs(table_id)
		var second := _resolve_runs(table_id)
		_expect(first == second, "%s resolves identically across runs" % table_id)
		_print_distribution(table_id)
	var place_a := _resolve_place_signature()
	_expect(place_a == _resolve_place_signature(), "resolve_place is deterministic")
	_expect(ItemGenerator.rng.state == shared_before, "resolving never touches ItemGenerator's shared rng")


func _resolve_runs(table_id: String) -> Array[String]:
	var signatures: Array[String] = []
	for seed_value in RUNS:
		signatures.append(_signature(ItemSpawnResolver.resolve(table_id, _context(table_id, seed_value))))
	return signatures


func _resolve_place_signature() -> Array[String]:
	var signatures: Array[String] = []
	for seed_value in RUNS:
		signatures.append(_signature(ItemSpawnResolver.resolve_place(_fake_place(seed_value), 5)))
	return signatures


func _print_distribution(table_id: String) -> void:
	var items: Dictionary = {}
	var tags: Dictionary = {}
	var rarities: Dictionary = {}
	var total := 0
	for seed_value in RUNS:
		for result in ItemSpawnResolver.resolve(table_id, _context(table_id, seed_value)):
			total += result.quantity
			items[result.item.template_id] = items.get(result.item.template_id, 0) + result.quantity
			rarities[result.item.get_rarity_name()] = rarities.get(result.item.get_rarity_name(), 0) + 1
			for tag in result.item.tags:
				tags[tag] = tags.get(tag, 0) + result.quantity
	print("[SpawnTest] %s: %d items over %d rolls (%.1f avg)" % [table_id, total, RUNS, float(total) / RUNS])
	print("    items:    %s" % [items])
	print("    tags:     %s" % [tags])
	print("    rarities: %s" % [rarities])


func _check_resolve_once() -> void:
	var place := _fake_place(42)
	place.place_id = "test_once_place"
	var ctx := SpawnContext.for_slot(place, "b0.container.0")
	var first := ItemSpawnResolver.resolve_slot_once("container.chest", ctx)
	# A different table on the same slot must still return the stored roll.
	var second := ItemSpawnResolver.resolve_slot_once("container.storage", SpawnContext.for_slot(place, "b0.container.0"))
	_expect(_signature(first) == _signature(second), "resolve_slot_once never re-rolls a slot")
	var ambient := ItemSpawnResolver.resolve_place_once(place, 4)
	_expect(_signature(ambient) == _signature(ItemSpawnResolver.resolve_place_once(place, 4)), "resolve_place_once never re-rolls")
	MainGameState.spawn_records.erase("test_once_place")


## A named item spawns at its template's rarity unless its entry asks to roll.
func _check_fixed_item_rarity() -> void:
	var entry := ItemSpawnEntry.new()
	entry.item_id = "basic_sword"
	var table := ItemSpawnTable.new()
	table.entries = [entry]
	ItemDatabase.spawn_tables["test.fixed_sword"] = table
	var rolled_up := 0
	for bias in [0.0, 1.0]:
		entry.rarity_bias = bias
		for seed_value in RUNS:
			for result in ItemSpawnResolver.resolve("test.fixed_sword", _context("test.fixed_sword", seed_value)):
				if result.item.rarity != Item.Rarity.COMMON:
					if bias == 0.0:
						_expect(false, "unbiased item_id entry spawned a %s sword" % result.item.get_rarity_name())
					else:
						rolled_up += 1
	_expect(rolled_up > 0, "an item_id entry with rarity_bias still rolls rarity")
	ItemDatabase.spawn_tables.erase("test.fixed_sword")


func _context(table_id: String, seed_value: int) -> SpawnContext:
	var extra: Array[String] = []
	extra.assign(TABLE_OWNER_TAGS.get(table_id, []))
	return SpawnContext.for_slot(_fake_place(seed_value), "test.slot", extra)


func _fake_place(seed_value: int) -> Place:
	var place := Place.new()
	place.place_id = "test_%d" % seed_value
	place.tile_seed = seed_value
	place.tags = ["biome.temperate", "place.wilderness"]
	return place


func _signature(results: Array[SpawnResult]) -> String:
	var parts: PackedStringArray = []
	for result in results:
		parts.append("%s=%s:%d:x%d:%s" % [result.spawn_id, result.item.id, result.item.rarity, result.quantity, result.item.modifiers])
	return "|".join(parts)


func _same_item(a: Item, b: Item) -> bool:
	if a == null or b == null:
		return false
	var same := a.id == b.id and a.rarity == b.rarity and a.modifiers == b.modifiers and a.base_value == b.base_value
	if a is ItemWeapon:
		same = same and (a as ItemWeapon).base_damage == (b as ItemWeapon).base_damage
	if a is ItemArmor:
		same = same and (a as ItemArmor).base_defense == (b as ItemArmor).base_defense
	return same


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		print("[SpawnTest] FAIL: %s" % label)
		push_error("[SpawnTest] FAIL: %s" % label)
