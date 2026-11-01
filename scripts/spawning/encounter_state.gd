extends Node

## The living population of the world, per region (autoload EncounterState).
##
## A pool counts who *lives* in a region; spawning an encounter shows part of
## that population and takes nothing from it. Only deaths and the daily
## simulation change the counts. Also holds per-tile cooldowns and the
## survivor snapshots that make a quick revisit find the same creatures.
##
## Regions are set up lazily the first time anything touches them. Their
## dominant biome and neighbours come from `world` (MainGame: region_biome(),
## region_neighbours()), or from register_region() in test scenes.

const VERSION := 1
## A tile re-entered within this many game hours brings back its survivors.
const REVISIT_HOURS := 6.0
## How hard predators press on their prey's growth, per unit of predator fill.
const PREDATION_PRESSURE := 0.5
## Time skips longer than this many days are simulated in WEEK_STEP-day steps.
const DAILY_STEPS := 365
const WEEK_STEP := 7

## Answers region_biome(region_id) and region_neighbours(region_id).
var world: Object = null
var world_seed: int = 0
## region_id -> { pool_id -> float count }. Spawning uses floor().
var pools: Dictionary = {}
## region_id -> the last day simulated there.
var region_days: Dictionary = {}
## tile_key -> { entry_id -> game hour the cooldown ends }
var cooldowns: Dictionary = {}
## tile_key -> { "hour": float, "survivors": Array of {entry_id, variant, group, index, tile} }
var snapshots: Dictionary = {}
## region_id -> { "biome": String, "neighbours": Array }. Rebuilt, never saved.
var _region_info: Dictionary = {}


func _ready() -> void:
	reset()
	WorldClock.day_changed.connect(_on_day_changed)


func reset() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = rng.randi()
	pools.clear()
	region_days.clear()
	cooldowns.clear()
	snapshots.clear()


## Fix a region's biome and neighbours instead of asking `world`.
func register_region(region_id: String, biome: String, neighbours: Array = []) -> void:
	_region_info[region_id] = {"biome": biome, "neighbours": neighbours.duplicate()}


func forget_region(region_id: String) -> void:
	_region_info.erase(region_id)
	pools.erase(region_id)
	region_days.erase(region_id)


# ─── Queries ───────────────────────────────────────────────────────────────────

func has_region(region_id: String) -> bool:
	return pools.has(region_id)


func pool_count(region_id: String, pool_id: String) -> float:
	_ensure_region(region_id)
	return float(pools[region_id].get(pool_id, 0.0))


func set_pool_count(region_id: String, pool_id: String, count: float) -> void:
	_ensure_region(region_id)
	pools[region_id][pool_id] = maxf(0.0, count)


## The capacity a pool is held to in a region right now, prey cap included.
func capacity(region_id: String, pool_id: String) -> float:
	_ensure_region(region_id)
	var def: PopulationPoolDef = EncounterDatabase.get_pool(pool_id)
	if def == null:
		return 0.0
	return _capacity(def, region_biome(region_id), pools[region_id])


func region_biome(region_id: String) -> String:
	return str(_info(region_id)["biome"])


## { pool_id -> {count, capacity} } for every pool living in the region.
func region_summary(region_id: String) -> Dictionary:
	_ensure_region(region_id)
	var out := {}
	for pool_id: String in pools[region_id]:
		out[pool_id] = {"count": pools[region_id][pool_id], "capacity": capacity(region_id, pool_id)}
	return out


# ─── Simulation ────────────────────────────────────────────────────────────────

## Bring a region up to `to_day`, covering loads, rests and travel that skipped
## the daily tick.
func catch_up_region(region_id: String, to_day: int) -> void:
	_ensure_region(region_id, to_day)
	var day: int = region_days[region_id]
	var steps := 0
	while day < to_day:
		var dt := 1 if steps < DAILY_STEPS else mini(WEEK_STEP, to_day - day)
		day += dt
		_step_region(region_id, day, dt)
		steps += 1
	region_days[region_id] = day


func _on_day_changed(day: int) -> void:
	for region_id: String in pools.keys():
		catch_up_region(region_id, day)


## One step of `dt` days: logistic growth less predation, then migration.
## Growth per capita means an emptied pool never regrows on its own.
func _step_region(region_id: String, day: int, dt: int) -> void:
	var counts: Dictionary = pools[region_id]
	var biome := region_biome(region_id)
	var caps := {}
	for pool_id: String in counts:
		var def: PopulationPoolDef = EncounterDatabase.get_pool(pool_id)
		caps[pool_id] = _capacity(def, biome, counts) if def else 0.0

	var next := counts.duplicate()
	for pool_id: String in counts:
		var def: PopulationPoolDef = EncounterDatabase.get_pool(pool_id)
		var count: float = counts[pool_id]
		if def == null or count <= 0.0:
			continue
		var cap: float = caps[pool_id]
		var rate: float = def.regrowth_per_day
		var growth: float
		if cap > 0.0:
			growth = rate * count * (1.0 - count / cap)
		else:
			growth = -rate * count  # nothing left to eat
		growth -= PREDATION_PRESSURE * _predator_fill(pool_id, counts, caps) * rate * count
		var updated := count + growth * dt
		# A multi-day step must not overshoot the capacity it is growing toward.
		if growth > 0.0 and cap > 0.0:
			updated = minf(updated, maxf(cap, count))
		next[pool_id] = maxf(0.0, updated)
	pools[region_id] = next
	_migrate(region_id, day, dt, caps)


func _capacity(def: PopulationPoolDef, biome: String, counts: Dictionary) -> float:
	var cap: float = def.base_capacity(biome)
	if not def.prey.is_empty():
		var fed := 0.0
		for prey_id: String in def.prey:
			fed += float(counts.get(prey_id, 0.0)) * float(def.prey[prey_id])
		cap = minf(cap, fed)
	return cap


## Summed fill of the pools that hunt `pool_id` here.
func _predator_fill(pool_id: String, counts: Dictionary, caps: Dictionary) -> float:
	var fill := 0.0
	for other_id: String in counts:
		var def: PopulationPoolDef = EncounterDatabase.get_pool(other_id)
		if def == null or not def.prey.has(pool_id) or caps[other_id] <= 0.0:
			continue
		fill += float(counts[other_id]) / float(caps[other_id])
	return minf(fill, 1.5)


func _migrate(region_id: String, day: int, dt: int, caps: Dictionary) -> void:
	var neighbours: Array = _info(region_id)["neighbours"]
	if neighbours.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, region_id])
	var counts: Dictionary = pools[region_id]
	for pool_id: String in counts.keys():
		var def: PopulationPoolDef = EncounterDatabase.get_pool(pool_id)
		var count: float = counts[pool_id]
		var cap: float = caps.get(pool_id, 0.0)
		if def == null or count <= 0.0:
			continue
		if count > cap and def.migration_rate > 0.0:
			var target: String = neighbours[rng.randi() % neighbours.size()]
			_transfer(region_id, target, pool_id, minf(count - cap, def.migration_rate * (count - cap) * dt))
		elif cap > 0.0 and count / cap < def.migrate_when_depleted_below:
			var target := _most_headroom(neighbours, pool_id)
			if not target.is_empty():
				_transfer(region_id, target, pool_id, count)


func _transfer(from_id: String, to_id: String, pool_id: String, amount: float) -> void:
	if amount <= 0.0:
		return
	_ensure_region(to_id, int(region_days[from_id]))
	if not pools[to_id].has(pool_id):
		return  # the population cannot live there
	pools[from_id][pool_id] = maxf(0.0, float(pools[from_id][pool_id]) - amount)
	pools[to_id][pool_id] = float(pools[to_id][pool_id]) + amount


func _most_headroom(neighbours: Array, pool_id: String) -> String:
	var best := ""
	var best_room := 0.0
	for region_id: String in neighbours:
		_ensure_region(region_id)
		if not pools[region_id].has(pool_id):
			continue
		var room := capacity(region_id, pool_id) - float(pools[region_id][pool_id])
		if room > best_room:
			best_room = room
			best = region_id
	return best


func _ensure_region(region_id: String, start_day: int = -1) -> void:
	if pools.has(region_id):
		return
	var biome := region_biome(region_id)
	var counts := {}
	for def: PopulationPoolDef in EncounterDatabase.pools.values():
		if def.lives_in(biome):
			counts[def.id] = def.initial_fill * def.base_capacity(biome)
	# Predators start within what their prey can feed.
	for pool_id: String in counts:
		var def: PopulationPoolDef = EncounterDatabase.get_pool(pool_id)
		counts[pool_id] = minf(counts[pool_id], def.initial_fill * _capacity(def, biome, counts))
	pools[region_id] = counts
	region_days[region_id] = start_day if start_day >= 0 else WorldClock.day()


func _info(region_id: String) -> Dictionary:
	if not _region_info.has(region_id):
		var biome := ""
		var neighbours: Array = []
		if is_instance_valid(world):
			biome = str(world.region_biome(region_id))
			neighbours = world.region_neighbours(region_id).duplicate()
		_region_info[region_id] = {"biome": biome, "neighbours": neighbours}
	return _region_info[region_id]


# ─── Deaths, cooldowns, snapshots ──────────────────────────────────────────────

## Connected to every encounter NPC's npc_died. One fewer of its kind lives in
## the region, and its encounter rests on that tile.
func record_death(npc: Node) -> void:
	var spawn: Dictionary = npc.get_meta("spawn", {})
	if spawn.is_empty():
		return
	var region_id := str(spawn.get("region_id", ""))
	var pool_id := str(spawn.get("pool_id", ""))
	if not region_id.is_empty() and not pool_id.is_empty():
		_ensure_region(region_id)
		if pools[region_id].has(pool_id):
			pools[region_id][pool_id] = maxf(0.0, float(pools[region_id][pool_id]) - 1.0)
	var entry: EncounterEntry = EncounterDatabase.get_entry(str(spawn.get("entry_id", "")))
	if entry:
		start_cooldown(str(spawn.get("tile_key", "")), entry, WorldClock.total_hours())


func start_cooldown(tile_key: String, entry: EncounterEntry, now_hour: float) -> void:
	if entry.cooldown_hours <= 0.0 or tile_key.is_empty():
		return
	if not cooldowns.has(tile_key):
		cooldowns[tile_key] = {}
	cooldowns[tile_key][entry.id] = now_hour + entry.cooldown_hours


## { entry_id -> end hour } of the cooldowns still running on a tile.
func cooldowns_for(tile_key: String, now_hour: float) -> Dictionary:
	var out := {}
	for entry_id: String in cooldowns.get(tile_key, {}):
		var ends: float = cooldowns[tile_key][entry_id]
		if ends > now_hour:
			out[entry_id] = ends
	return out


func store_snapshot(tile_key: String, hour: float, survivors: Array) -> void:
	snapshots[tile_key] = {"hour": hour, "survivors": survivors.duplicate(true)}


## The tile's snapshot if it is younger than REVISIT_HOURS, else {}.
func snapshot_for(tile_key: String, now_hour: float) -> Dictionary:
	var snapshot: Dictionary = snapshots.get(tile_key, {})
	if snapshot.is_empty() or now_hour - float(snapshot["hour"]) >= REVISIT_HOURS or now_hour < float(snapshot["hour"]):
		return {}
	return snapshot


# ─── Save / load ───────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var now := WorldClock.total_hours()
	var live_snapshots := {}
	for tile_key: String in snapshots:
		if not snapshot_for(tile_key, now).is_empty():
			live_snapshots[tile_key] = snapshots[tile_key]
	var live_cooldowns := {}
	for tile_key: String in cooldowns:
		var running := cooldowns_for(tile_key, now)
		if not running.is_empty():
			live_cooldowns[tile_key] = running
	return {
		"version": VERSION,
		"world_seed": world_seed,
		"pools": pools.duplicate(true),
		"region_days": region_days.duplicate(),
		"cooldowns": live_cooldowns,
		"snapshots": live_snapshots.duplicate(true),
	}


## An empty or unknown-version dict starts a fresh world.
func from_dict(data: Dictionary) -> void:
	reset()
	if data.is_empty():
		return
	if int(data.get("version", 0)) != VERSION:
		push_warning("[EncounterState] Unknown spawn_state version %s; starting fresh populations" % data.get("version"))
		return
	world_seed = int(data.get("world_seed", world_seed))
	pools = (data.get("pools", {}) as Dictionary).duplicate(true)
	region_days = (data.get("region_days", {}) as Dictionary).duplicate()
	cooldowns = (data.get("cooldowns", {}) as Dictionary).duplicate(true)
	snapshots = (data.get("snapshots", {}) as Dictionary).duplicate(true)
