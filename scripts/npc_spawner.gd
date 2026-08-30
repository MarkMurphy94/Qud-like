extends Node
class_name NPCSpawner

## Fills a freshly generated local map with NPCs.
##
## Lives as a child of the MapGenerator it populates (see local_scene.tscn), so
## the NPCs share that map's lifetime. MainGame drives it through
## populate_local_map() on entry and clear() on exit.
##
## Everyone spawned here is born into the politics of the tile: their names come
## from its culture, and lawful folk are sworn to whoever rules it — see
## get_faction_for_coord() and NPC.LAWFUL_ROLES.

@export var npc_scene: PackedScene = preload("res://scenes/npc.tscn")

## The MapGenerator whose painted map this spawner fills. Normally the parent;
## the export is an escape hatch for other scene layouts.
@export var map_generator_path: NodePath

## Set by caller when loading a settlement scene.
var settlement_data: MapConfig = null
## Metadata for the area being populated, normalised to a Dictionary. Accepts
## the same shapes MapGenerator.generate_local_map() does, since both are fed
## from the same dict MainGame builds.
var area_metadata: Dictionary = {}

var spawned_npcs: Array = []
var rng := RandomNumberGenerator.new()
var _map: MapGenerator = null

# Margin in tiles so NPCs don't spawn right on the map edge.
const SPAWN_MARGIN_TILES: int = 2

func _ready():
	if not map_generator_path.is_empty():
		_map = get_node_or_null(map_generator_path) as MapGenerator
	if _map == null:
		_map = get_parent() as MapGenerator

func clear():
	for n in spawned_npcs:
		if is_instance_valid(n):
			n.remove_from_group("NPCs")
			n.queue_free()
	spawned_npcs.clear()

# ─── Entry point ───────────────────────────────────────────────────────────────

## Populate the local map that was just generated from `metadata` — the same
## value MapGenerator.generate_local_map() consumed. Picks settlement or
## wilderness spawning from the overworld hints so callers don't have to.
func populate_local_map(metadata) -> void:
	set_area_metadata(metadata)
	if _has_settlement():
		settlement_data = _map.map_template if _map else null
		spawn_settlement_npcs()
	else:
		spawn_wilderness_npcs()

## Accepts a TileMetadata resource or a plain Dictionary, mirroring
## MapGenerator.generate_local_map().
func set_area_metadata(metadata) -> void:
	if metadata is TileMetadata:
		area_metadata = (metadata as TileMetadata).to_dict()
	elif metadata is Dictionary:
		area_metadata = metadata
	else:
		area_metadata = {}

## The overworld hint is nested under "overworld" but mirrored top-level, so
## check both rather than depending on which builder produced the dict.
func _has_settlement() -> bool:
	var overworld = area_metadata.get("overworld", {})
	if overworld is Dictionary and overworld.has("has_settlement"):
		return bool(overworld["has_settlement"])
	return bool(area_metadata.get("has_settlement", false))

## Naming profiles of the people whose land this is, stamped into the metadata
## by MainGame. Empty for areas built without a culture map, which leaves the
## NPC on the generic name lists.
func _name_profiles() -> Dictionary:
	var profiles = area_metadata.get("name_profiles", {})
	return profiles if profiles is Dictionary else {}

# ─── Settlement spawning ───────────────────────────────────────────────────────

## Spawns a settlement's population. `density_override` is a
## MapConfig.BuildingDensity; -1 uses settlement_data.building_density.
func spawn_settlement_npcs(density_override: int = -1) -> void:
	if not settlement_data:
		push_warning("NPCSpawner: no settlement_data set")
		return
	clear()

	# Prefer the authored settlement entry's seed. Procedural areas have no such
	# entry, and fall back to the MapConfig SEED the generator already set from
	# the map metadata — that keeps NPC placement in step with the layout.
	var settlement_entry := _find_settlement_entry()
	if not settlement_entry.is_empty():
		_assign_seed(settlement_entry)
	elif settlement_data.SEED != 0:
		rng.seed = settlement_data.SEED
	else:
		rng.randomize()

	var density: int = density_override if density_override >= 0 else int(settlement_data.building_density)
	var counts_map: Dictionary = MainGameState.settlement_npc_counts.get(density, {})

	# Building positions are preferred but optional — NPCs fall back to random
	# positions within the map bounds if none are available.
	var homes := _building_positions()
	if not homes.is_empty():
		homes.shuffle()
	var home_index := 0

	var area_key := _area_key()

	for npc_type: MainGameState.NpcType in counts_map.keys():
		var target_count: int = counts_map[npc_type]
		for i in target_count:
			var spawn_tile: Vector2i
			if not homes.is_empty():
				spawn_tile = homes[home_index % homes.size()]
				home_index += 1
			else:
				spawn_tile = _random_tile()
			# A building's stored position is its top-left wall cell, so nudge every
			# spawn onto solid ground rather than dropping NPCs inside geometry.
			var world_pos := _walkable_world_pos(spawn_tile)
			var npc_id := "%s_%s_%d" % [area_key, str(npc_type), i]
			var npc := _spawn_npc(npc_type, world_pos, "", npc_id)
			npc.set_locations(world_pos)
			spawned_npcs.append(npc)
		
## Looks up the settlement entry in MainGameState by map_name first,
## then by overworld_tile key (make_settlement_key), so both hand-crafted
## and dynamically-generated settlements are found.
func _find_settlement_entry() -> Dictionary:
	if not settlement_data:
		return {}
	# 1. Direct name lookup (covers hardcoded entries like "town_1")
	var map_name := settlement_data.map_name
	if MainGameState.settlements.has(map_name):
		return MainGameState.settlements[map_name]
	# 2. Tile-based key lookup (covers dynamically-created settlements)
	if settlement_data.overworld_tile != Vector2i.ZERO:
		for mtype in MapConfig.MapType.values():
			var key := MainGameState.make_settlement_key(mtype, settlement_data.overworld_tile)
			if MainGameState.settlements.has(key):
				return MainGameState.settlements[key]
	return {}

# ─── Wilderness spawning ───────────────────────────────────────────────────────

## Spawns wildlife/monsters for a procedural area.
## Count is auto-derived from encounter_difficulty in area_metadata if not
## specified explicitly (pass a non-negative value to override).
func spawn_wilderness_npcs(count: int = -1) -> void:
	clear()
	if not npc_scene:
		return

	var difficulty: int = int(area_metadata.get("encounter_difficulty", 1))
	if area_metadata.has("seed"):
		rng.seed = int(area_metadata["seed"])
	else:
		rng.randomize()

	# Derive count from difficulty if not provided: 2–8 creatures.
	if count < 0:
		count = clamp(2 + (difficulty - 1) * 2, 2, 8)

	var area_key := _area_key()
	for i in count:
		var npc_type := _wilderness_npc_type()
		var pos := _walkable_world_pos(_random_tile())
		var npc := _spawn_npc(npc_type, pos, "", "wild_%s_%d" % [area_key, i])
		npc.set_locations(pos)
		spawned_npcs.append(npc)

## Determines the NPC type for a wilderness spawn.
## Uses wildlife.common from area_metadata when populated; defaults to ANIMAL.
func _wilderness_npc_type() -> MainGameState.NpcType:
	var wildlife = area_metadata.get("wildlife", {})
	if wildlife is Dictionary:
		var common: Array = wildlife.get("common", [])
		if not common.is_empty():
			const TYPE_MAP = {
				"animal": MainGameState.NpcType.ANIMAL,
				"monster": MainGameState.NpcType.MONSTER,
				"bandit": MainGameState.NpcType.BANDIT,
				"soldier": MainGameState.NpcType.SOLDIER,
			}
			var pick: String = str(common[rng.randi() % common.size()]).to_lower()
			if TYPE_MAP.has(pick):
				return TYPE_MAP[pick]
	return MainGameState.NpcType.ANIMAL

# ─── Shared helpers ────────────────────────────────────────────────────────────

func _spawn_npc(npc_type: MainGameState.NpcType, world_pos: Vector2, variant: String = "", npc_id: String = "") -> NPC:
	var inst: NPC = npc_scene.instantiate()
	inst.npc_type = npc_type
	if variant.is_empty():
		variant = _get_random_variant_for_type(npc_type)
	inst.npc_variant = variant
	inst.npc_id = npc_id
	inst.culture_name_profiles = _name_profiles()
	# Neutral and lawful folk belong to whoever rules the ground under them;
	# outlaws, beasts and monsters belong to nobody and stay factionless. The
	# role has to be read off the profile table here rather than from the NPC,
	# which has not run its own _ready() yet.
	if NPC.role_for(npc_type, variant) in NPC.LAWFUL_ROLES:
		inst.faction = get_faction_for_coord(_area_coords())
	# Type, variant, id, culture and faction are all set before add_child, so the
	# NPC's own _ready applies the profile, paints on its livery, and generates a
	# name seeded off that id — the same NPC comes back the same on every revisit.
	add_child(inst)
	inst.global_position = world_pos
	inst.add_to_group("NPCs")
	return inst

## Stable identifier for the area being populated, used to seed NPC ids (and so
## their names). Tile coords, since that is the one thing that distinguishes two
## maps generated from the same shared MapConfig.
func _area_key() -> String:
	return str(area_metadata.get("coords", area_metadata.get("seed", "unknown")))


## The overworld tile this local map stands on.
func _area_coords() -> Vector2i:
	var coords = area_metadata.get("coords", Vector2i.ZERO)
	return coords if coords is Vector2i else Vector2i.ZERO


## The faction that rules the overworld tile `coord`, as a `faction_id`, or ""
## where nobody holds it — unclaimed land, or a scene with no world map.
##
## Asks the live faction map rather than the metadata, because provinces change
## hands in play while the metadata was stamped on entry. The stamp is the
## fallback for scenes with no faction map to ask, and it only speaks for this
## area's own tile.
func get_faction_for_coord(coord: Vector2i) -> String:
	var factions = _faction_map()
	if factions:
		var ruler = factions.ruler_for_tile(coord)
		return ruler.faction_id if ruler else ""
	if coord == _area_coords():
		return str(area_metadata.get("ruling_faction", ""))
	return ""


## The overworld's map of organisations, or null in the test scenes and anything
## opened straight from the editor.
func _faction_map():
	var root := get_tree().current_scene
	return root.faction_map() if root and root.has_method("faction_map") else null


## Tile positions of the buildings NPCs can call home.
##
## Read from the generator's own record, which the settlement, stored-layout and
## hamlet routes all fill. MapConfig.buildings only ever describes settlements,
## so asking it left hamlet NPCs standing wherever the dice put them.
func _building_positions() -> Array:
	if _map and not _map.map_buildings.is_empty():
		var out: Array = []
		for b in _map.map_buildings:
			out.append(b["pos"])
		return out
	if settlement_data:
		return _extract_building_positions(settlement_data.buildings)
	return []


## Extracts tile-space positions from an Array of Structure resources or legacy Dictionaries.
func _extract_building_positions(buildings: Array) -> Array:
	var out: Array = []
	for b in buildings:
		if b is Structure:
			if b.POSITION != Vector2i.ZERO:
				out.append(b.POSITION)
		elif b is Dictionary and b.has("POSITION"):
			out.append(b["POSITION"])
	return out

## A random tile inside the map, kept clear of the edge.
func _random_tile() -> Vector2i:
	return Vector2i(
		rng.randi_range(SPAWN_MARGIN_TILES, MapGenerator.WIDTH - 1 - SPAWN_MARGIN_TILES),
		rng.randi_range(SPAWN_MARGIN_TILES, MapGenerator.HEIGHT - 1 - SPAWN_MARGIN_TILES)
	)

## World position of the nearest walkable tile to `tile`, so an NPC is never
## dropped inside a wall or a building footprint. Falls back to a plain tile
## conversion when there is no host MapGenerator to ask.
func _walkable_world_pos(tile: Vector2i) -> Vector2:
	if _map:
		return _map.tile_to_world(_map.nearest_walkable(tile))
	return Vector2(tile) * MainGameState.TILE_SIZE

func _assign_seed(entry: Dictionary) -> void:
	if entry.has("seed") and entry["seed"] != null:
		rng.seed = entry["seed"]
	else:
		rng.randomize()

func _get_random_variant_for_type(npc_type: MainGameState.NpcType) -> String:
	# Variant names come straight from the NPC profile table, so adding a variant
	# there is enough for the spawner to start rolling it.
	var variants: Array = NPC.variants_for(npc_type)
	if variants.is_empty():
		return "default"
	return variants[rng.randi() % variants.size()]

func _get_variant_for_role(npc_type: MainGameState.NpcType, role: String = "") -> String:
	# Helper to select appropriate variants based on role/context
	# You can expand this later with more sophisticated logic
	match npc_type:
		MainGameState.NpcType.SOLDIER:
			if role == "guard":
				return "default"
			elif role == "elite":
				return "knight"
			else:
				return _get_random_variant_for_type(npc_type)
		MainGameState.NpcType.PEASANT:
			if role == "worker":
				var workers = ["farmer", "blacksmith", "baker"]
				return workers[rng.randi() % workers.size()]
			else:
				return _get_random_variant_for_type(npc_type)
		_:
			return _get_random_variant_for_type(npc_type)
