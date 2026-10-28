extends RefCounted
class_name ItemSpawnResolver

## Turns spawn tables into items. Every random choice comes from the
## SpawnContext's RNG, so a given context always produces the same results.
##
## Tiers resolve anchored → owned → ambient: resolve_anchored() (a stub until
## the item ledger exists), then owners' slots via resolve()/resolve_slot_once(),
## then resolve_place() for ambient scatter.

## Guards against a nested-table cycle that slipped past load-time validation.
const MAX_DEPTH := 8

## Ambient scatter is drawn with up to this many resolves per budget point, so
## a table that keeps rolling nothing cannot loop forever.
const AMBIENT_ATTEMPTS_PER_ITEM := 4


static func resolve(table_id: String, ctx: SpawnContext) -> Array[SpawnResult]:
	var out: Array[SpawnResult] = []
	_resolve_into(table_id, ctx, out, 0)
	return out


## Ambient scatter for `place`, up to `budget` results. Anchored items come
## first and count against the budget.
static func resolve_place(place: Place, budget: int) -> Array[SpawnResult]:
	var out: Array[SpawnResult] = resolve_anchored(place)
	var table_id := ambient_table_for(place)
	var ctx := SpawnContext.for_slot(place, "ambient")
	var attempts := 0
	while out.size() < budget and attempts < budget * AMBIENT_ATTEMPTS_PER_ITEM:
		attempts += 1
		_resolve_into(table_id, ctx, out, 0)
	if out.size() > budget:
		out.resize(budget)
	return out


## Uniques and relics placed by history. Nothing places them yet.
static func resolve_anchored(_place: Place) -> Array[SpawnResult]:
	var out: Array[SpawnResult] = []
	return out


static func ambient_table_for(place: Place) -> String:
	return "ambient.ruin" if place.has_tag("place.ruin") else "ambient.wilderness"


## resolve(), but only ever rolled once per place and slot: the first result
## is stored in MainGameState.spawn_records (and so in the save) and handed
## back on every later visit, even if the tables change in between.
static func resolve_slot_once(table_id: String, ctx: SpawnContext) -> Array[SpawnResult]:
	return _once(ctx, func() -> Array[SpawnResult]: return resolve(table_id, ctx))


## resolve_place(), rolled once per place.
static func resolve_place_once(place: Place, budget: int) -> Array[SpawnResult]:
	var ctx := SpawnContext.for_slot(place, "ambient")
	return _once(ctx, func() -> Array[SpawnResult]: return resolve_place(place, budget))


static func _once(ctx: SpawnContext, roll: Callable) -> Array[SpawnResult]:
	var place_records: Dictionary = MainGameState.spawn_records.get(ctx.place_id, {})
	if place_records.has(ctx.slot_id):
		return _results_from_records(place_records[ctx.slot_id])
	var results: Array[SpawnResult] = roll.call()
	place_records[ctx.slot_id] = _records_from_results(results)
	MainGameState.spawn_records[ctx.place_id] = place_records
	return results


static func _records_from_results(results: Array[SpawnResult]) -> Array:
	var records: Array = []
	for result in results:
		var record := ItemGenerator.item_to_record(result.item, result.quantity)
		record["spawn_id"] = result.spawn_id
		records.append(record)
	return records


static func _results_from_records(records: Array) -> Array[SpawnResult]:
	var out: Array[SpawnResult] = []
	for record: Dictionary in records:
		var item := ItemGenerator.item_from_record(record)
		if item:
			out.append(SpawnResult.make(item, int(record.get("quantity", 1)), String(record.get("spawn_id", ""))))
	return out


# ─── Resolution ───────────────────────────────────────────────────────────────

static func _resolve_into(table_id: String, ctx: SpawnContext, out: Array[SpawnResult], depth: int) -> void:
	if depth > MAX_DEPTH:
		push_warning("[ItemSpawnResolver] Nesting deeper than %d at %s — cycle?" % [MAX_DEPTH, table_id])
		return
	var table := ItemDatabase.get_spawn_table(table_id)
	if table == null:
		return

	var candidates := _eligible_entries(table, ctx)
	var rolls := ctx.rng.randi_range(table.rolls.x, table.rolls.y)
	for _i in rolls:
		var entry := _pick(candidates, ctx.rng)
		if entry == null:
			break
		if not table.allow_repeats:
			candidates.erase(entry)
		var count := ctx.rng.randi_range(entry.count.x, entry.count.y)
		if not entry.table_id.is_empty():
			for _n in count:
				_resolve_into(entry.table_id, ctx, out, depth + 1)
			continue
		var template_id := _template_for(entry, ctx)
		if template_id.is_empty() or count <= 0:
			continue
		_emit(template_id, count, entry, ctx, out)


static func _eligible_entries(table: ItemSpawnTable, ctx: SpawnContext) -> Array[ItemSpawnEntry]:
	var out: Array[ItemSpawnEntry] = []
	for entry in table.entries:
		if entry.weight <= 0.0:
			continue
		if ctx.tier < entry.tier_range.x or ctx.tier > entry.tier_range.y:
			continue
		if entry.era_range.x >= 0 and ctx.era < entry.era_range.x:
			continue
		if entry.era_range.y >= 0 and ctx.era > entry.era_range.y:
			continue
		if not _context_allows(entry, ctx):
			continue
		if not ctx.chronicle.matches(entry.chronicle_condition, ctx):
			continue
		out.append(entry)
	return out


static func _context_allows(entry: ItemSpawnEntry, ctx: SpawnContext) -> bool:
	for tag in entry.context_require:
		if not ctx.has_tag(tag):
			return false
	for tag in entry.context_exclude:
		if ctx.has_tag(tag):
			return false
	return true


static func _pick(entries: Array[ItemSpawnEntry], rng: RandomNumberGenerator) -> ItemSpawnEntry:
	var total := 0.0
	for entry in entries:
		total += entry.weight
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for entry in entries:
		roll -= entry.weight
		if roll < 0.0:
			return entry
	return entries.back()


## The template an entry resolves to. Tag queries never return unique items —
## those are placed by the anchored tier, not rolled.
static func _template_for(entry: ItemSpawnEntry, ctx: SpawnContext) -> String:
	if not entry.item_id.is_empty():
		return entry.item_id
	var ids := ItemDatabase.find_by_tags(entry.item_tags, [ItemDatabase.UNIQUE_TAG])
	if ids.is_empty():
		return ""
	return ids[ctx.rng.randi() % ids.size()]


## Stackable items come out as one stack; anything else as `count` separate
## items, each with its own spawn id, rarity and seed.
##
## An entry naming a specific item spawns it at the template's own rarity — a
## merchant's guaranteed dagger is a plain dagger — unless the entry sets a
## positive rarity_bias. Tag-pool entries always roll.
static func _emit(template_id: String, count: int, entry: ItemSpawnEntry, ctx: SpawnContext, out: Array[SpawnResult]) -> void:
	var stacks := 1
	var per_stack := count
	var template: Item = ItemDatabase.all_items.get(template_id)
	if template and not template.stackable:
		stacks = count
		per_stack = 1
	var rolls_rarity := entry.item_id.is_empty() or entry.rarity_bias > 0.0
	for _s in stacks:
		var spawn_id := "%s/%s/%d" % [ctx.place_id, ctx.slot_id, out.size()]
		var rarity: int = -1
		if rolls_rarity:
			rarity = ItemGenerator.roll_rarity(ctx.rng, ctx.tier, entry.rarity_bias)
		elif template:
			rarity = template.rarity
		var seed_value := ctx.rng.randi() & 0x7FFFFFFF
		var item := ItemGenerator.generate_from_template(template_id, rarity, seed_value, spawn_id)
		if item == null:
			continue
		if item.rarity >= Item.Rarity.RARE:
			item.provenance = {
				"origin_place": ctx.place_id,
				"faction": _faction_of(ctx),
				"spawn_id": spawn_id,
			}
		out.append(SpawnResult.make(item, per_stack, spawn_id))


static func _faction_of(ctx: SpawnContext) -> String:
	for tag in ctx.tags:
		if tag.begins_with("faction."):
			return tag.trim_prefix("faction.")
	return ""
