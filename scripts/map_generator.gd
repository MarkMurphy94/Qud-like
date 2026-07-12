@tool

# ==========
# Canonical map generator for local areas and settlements (dungeons/special
# locations to follow). Serves both authoring and runtime:
#  - In-editor: with generate_on_ready enabled the scene regenerates on open;
#    hand-edit the result and save it as a static scene.
#  - Runtime settlements: scenes using this script + a MapConfig generate on
#    load via setup_and_generate(). Baked static scenes set
#    generate_on_ready = false and keep their painted tiles.
#  - Runtime wilderness: AreaContainer instantiates wilderness_area.tscn with
#    generate_on_ready = false and calls generate_local_map(metadata).
# ==========


#  temperate_medieval_village.tres and grassland_poneti.tres custom data layers:
	# category              (String) – tilemaplayer grouping; top-level tile_catalog key
	# layers                (String) – space-separated list of relevant TileMapLayer names
	# type                  (String) – tile type, e.g. tree/bush/flower_patch/house; tile_catalog sub-key
	# subtype               (String) – finer-grained variant of `type`
	# building_id           (String) – layer named "building_id" in grassland_poneti.tres,
	#                                  "building id" in temperate_medieval_village.tres
	# tags                  (String) – space-separated proc-gen tags (formerly "proc gen tags")
	# interior              (bool)   – true if this tile belongs to a building interior
	# associated buildings  (String) – space-separated building types this tile is associated with
	# affiliations          (String) – space-separated faction/affiliation tags
	# classes               (String) – space-separated class tags
	# cultures              (String) – space-separated culture tags
	# climates              (String) – space-separated climate tags
	# biomes                (String) – space-separated biome tags
	# placeholder           (String) – placeholder marker, if any


extends Node2D
class_name MapGenerator

# ── TileMapLayer nodes ──────────────────────────────────────────────────────
# grassland_poneti.tres  → ground terrain, road, and terrain features
# temperate_medieval_village.tres → premade building sprites
@onready var ground: TileMapLayer = $base_terrain
@onready var road: TileMapLayer = $road
@onready var terrain_features: TileMapLayer = $terrain_features
@onready var structures_exterior: TileMapLayer = $structures_exterior
@onready var structures_interior: TileMapLayer = $structures_interior
@onready var foliage: TileMapLayer = $foliage
@onready var structures: Node2D = $structures
@onready var decor_exterior: TileMapLayer = $decor_exterior
@onready var tilemaps = {
	"GROUND": ground,
	"INTERIOR_FLOOR": structures_interior,
	"WALLS": structures_interior,
	"FURNITURE": structures_interior,
	"ITEMS": structures_interior,
	"DOORS": structures_interior,
	"ROOF": structures_interior
}

# Mirror of OverworldGenerator.Tile for reference
enum OverworldTile {WATER, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, DIRT, WATER}
enum DecorationTile {WALL_BANNER, WALL_TORCH, FLOOR_RUG, FLOOR_POTTERY}
enum HamletStructureType {HOUSE, SHOP, TEMPLE, TOWER, WALL}

# Area generation types – mirrors MapConfig.MapType for backward compat.
# Settlement sub-types (town vs city vs castle) are now inferred from
# MapConfig.BuildingDensity and/or culture rather than hard-coded here.
enum MapType {
	NON_SETTLEMENT, # Natural local area with possible hamlet
	SETTLEMENT, # Towns, cities, etc.
	CASTLE_INTERIOR, # Interior of a castle
	DUNGEON # Dungeon level
}

# ── image Source IDs within grassland_poneti.tres ─────────────────────────────────
const GROUND_SOURCE_ID = 0 # TileGrass.png – autotile terrain
const FOLIAGE_SOURCE_ID = 3 # TreesAndBushes – trees, bushes, flowers with proc-gen tags for runtime discovery
# Foliage and terrain-feature tiles are discovered at runtime via _build_tile_catalog()
# using the custom data layers in grassland_poneti.tres (category / type / tag_1 / tag_2).

# ── image Source IDs within temperate_medieval_village.tres ───────────────────────
const STRUCT_SOURCE_TOWERS = 1 # Towers.png
const STRUCT_SOURCE_TOWN = 2 # TownSprites.png
const STRUCT_SOURCE_VILLAGE = 3 # VillageBuildingSprites.png
const STRUCT_SOURCE_WOODEN = 5 # WoodenElements.png – fences, props

# ── Terrain set IDs (grassland_poneti.tres terrain set 0) ───────────────────
const TERRAINS = {
	"stone": 0, # change to new terrain set index when updated in grassland_poneti.tres
	"grass": 1,
	"dirt": 2,
	"water": 3, # change to new terrain set index when updated in grassland_poneti.tres
	"wheat_field": 4, # change to new terrain set index when updated in grassland_poneti.tres
}

# Map our enum types to terrain sets
const GROUND_TERRAIN_MAP = {
	GroundTile.STONE: "stone",
	GroundTile.GRASS: "grass",
	GroundTile.DIRT: "dirt",
	GroundTile.WATER: "water"
}

# Terrain cells for batch processing
var terrain_cells = {
	"stone": [],
	"grass": [],
	"dirt": [],
	"water": []
}

# ── Building sprite definitions (temperate_medieval_village.tres) ────────────
# Each entry maps a Structure.StructureType to the atlas coords of the premade
# exterior and interior sprites.  "size" is the sprite footprint in ground
# tiles (= size_in_atlas of the exterior sprite).
# IMPORTANT: verify these atlas coords against your tileset editor – they must
# match the actual sprite positions in VillageBuildingSprites.png / TownSprites.png.
const BUILDING_SPRITES = {
	Structure.StructureType.HOUSE: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(0, 0),
		"size": Vector2i(12, 10),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(0, 10),
		"interior_size": Vector2i(12, 7),
		"ground": "dirt",
		"spacing": 2,
	},
	Structure.StructureType.SHOP: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(26, 30),
		"size": Vector2i(13, 13),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(26, 43),
		"interior_size": Vector2i(13, 14),
		"ground": "stone",
		"spacing": 2,
	},
	Structure.StructureType.TAVERN: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(2, 25),
		"size": Vector2i(20, 16),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(1, 41),
		"interior_size": Vector2i(21, 17),
		"ground": "stone",
		"spacing": 3,
	},
	Structure.StructureType.MANOR: {
		"exterior_source": STRUCT_SOURCE_VILLAGE,
		"exterior_atlas": Vector2i(59, 0),
		"size": Vector2i(25, 20),
		"interior_source": STRUCT_SOURCE_VILLAGE,
		"interior_atlas": Vector2i(59, 20),
		"interior_size": Vector2i(24, 16),
		"ground": "stone",
		"spacing": 4,
	},
}

# Maps the old HamletStructureType enum to Structure.StructureType so hamlet
# buildings can share the BUILDING_SPRITES table.
const HAMLET_TYPE_MAP = {
	HamletStructureType.HOUSE: Structure.StructureType.HOUSE,
	HamletStructureType.SHOP: Structure.StructureType.SHOP,
	HamletStructureType.TEMPLE: Structure.StructureType.TAVERN,
	HamletStructureType.TOWER: Structure.StructureType.HOUSE,
	HamletStructureType.WALL: Structure.StructureType.HOUSE,
}

const WIDTH = 80
const HEIGHT = 80
const TILE_SIZE = 16 # Pixel size per atlas cell (both tilesets)
const TERRAIN_SET_ID = 0 # Terrain set index in grassland_poneti.tres

# Default terrain type per settlement density tier.
# Replaces the old MapType-keyed SETTLEMENT_TERRAIN.
const SETTLEMENT_TERRAIN_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		"primary": "grass", "secondary": "grass", "paths": "dirt"
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": "dirt"
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": "stone"
	},
	MapConfig.BuildingDensity.CITY: {
		"primary": "grass", "secondary": "dirt", "paths": "stone"
	},
}

# How many of each building type to place per BuildingDensity tier.
const BUILDING_COUNTS_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		Structure.StructureType.HOUSE: 4,
		Structure.StructureType.TAVERN: 0,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		Structure.StructureType.HOUSE: 8,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		Structure.StructureType.HOUSE: 10,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 2,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		Structure.StructureType.HOUSE: 16,
		Structure.StructureType.TAVERN: 2,
		Structure.StructureType.SHOP: 3,
		Structure.StructureType.MANOR: 1,
	},
	MapConfig.BuildingDensity.CITY: {
		Structure.StructureType.HOUSE: 24,
		Structure.StructureType.TAVERN: 3,
		Structure.StructureType.SHOP: 4,
		Structure.StructureType.MANOR: 2,
	},
}

# Foliage density multipliers per MapConfig.TreeDensity enum.
# Values are lower than before because each foliage sprite now occupies many
# tiles (e.g. a tree is 6×8).  The used_cells check prevents overlapping.
const TREE_DENSITY_VALUES = {
	MapConfig.TreeDensity.NONE: 0.0,
	MapConfig.TreeDensity.SPARSE: 0.15,
	MapConfig.TreeDensity.FOREST: 0.30,
}

# Tiles of "worn ground" influence around each building footprint — used to
# skew settlement ground toward the secondary (trampled) terrain near walls.
const WEAR_RADIUS := 6

# Road generation parameters
const ROAD_WIDTH = 2
const PLAZA_MIN_SIZE = 4
const PLAZA_MAX_SIZE = 8
const PLAZA_DISTANCE_THRESHOLD = 10

# Unified building scene (building.tscn): contains one child Node2D per
# building_id (e.g. "house_1", "tavern_1"), each holding both its exterior
# and interior sub-hierarchy. building_ids_by_type is built at runtime by
# inspecting this scene's children, keyed by Structure.StructureType inferred
# from each child's name (see _structure_type_from_name()).
const BUILDING_SCENE: PackedScene = preload("res://scenes/building.tscn")
# Authoring-only placeholder child in building.tscn; never a valid variant.
const BUILDING_TEMPLATE_NODE_NAME := "node_hierarchy_template"

# Maps a building.tscn child's name (with any trailing "_<n>" suffix
# stripped) to the Structure.StructureType it represents.
const STRUCTURE_TYPE_NAME_MAP := {
	"house": Structure.StructureType.HOUSE,
	"log_cabin": Structure.StructureType.HOUSE, # cabin variant placed as a house
	"tavern": Structure.StructureType.TAVERN,
	"shop": Structure.StructureType.SHOP,
	"church": Structure.StructureType.CHURCH,
	"wall": Structure.StructureType.WALL,
	"manor": Structure.StructureType.MANOR,
	"barracks": Structure.StructureType.BARRACKS,
	"castle_keep": Structure.StructureType.CASTLE_KEEP,
}

@export var map_template: MapConfig

## When true (authoring scenes, runtime settlement scenes) the map regenerates
## in _ready(). Baked static scenes and the runtime wilderness scene set this
## false: baked scenes keep their saved tiles, wilderness waits for
## generate_local_map(metadata).
@export var generate_on_ready: bool = true

# ── Editor tools (inspector buttons) ────────────────────────────────────────
@export_group("Editor Tools")
## Folder that Bake To Scene writes to; the filename comes from
## map_template.map_name (snake_cased).
@export_dir var bake_dir: String = "res://scenes/generated"
@export_tool_button("Generate") var btn_generate = _editor_generate
@export_tool_button("Clear") var btn_clear = _editor_clear
@export_tool_button("Bake To Scene") var btn_bake = _editor_bake
@export_group("")

## Regenerate in place — replaces the old "Scene > Reload Saved Scene" ritual.
func _editor_generate() -> void:
	if not Engine.is_editor_hint():
		return
	if noise == null:
		noise = FastNoiseLite.new()
	clear_all_layers()
	tile_catalog.clear()
	for ts in get_all_tile_sets():
		_build_tile_catalog(ts)
	_build_building_registry()
	setup_and_generate()

func _editor_clear() -> void:
	if not Engine.is_editor_hint():
		return
	clear_all_layers()

## Saves the current (generated + hand-edited) map as a standalone static
## scene at bake_dir/<map_name>.tscn. The baked scene keeps this script with
## generate_on_ready = false, so it loads its painted tiles verbatim while
## still satisfying the loader contract (tilemaps dict, is_walkable,
## map_template for the NPC spawner).
func _editor_bake() -> void:
	if not Engine.is_editor_hint():
		return
	if map_template == null or map_template.map_name.strip_edges().is_empty():
		push_error("MapGenerator bake: set map_template.map_name first — it becomes the scene filename.")
		return

	var original_template := map_template
	var original_flag := generate_on_ready
	# The baked scene owns a deep copy of the config so runtime layout
	# mutations can't leak between scenes sharing an embedded subresource.
	map_template = original_template.duplicate(true)
	generate_on_ready = false

	# Everything under this node must be owned by it to survive pack().
	for child in get_children():
		child.owner = self
		_set_owner_recursive(child, self)

	var packed := PackedScene.new()
	var err := packed.pack(self)
	if err != OK:
		push_error("MapGenerator bake: pack failed (error %d)" % err)
	else:
		DirAccess.make_dir_recursive_absolute(bake_dir)
		var path := "%s/%s.tscn" % [bake_dir, map_template.map_name.to_snake_case()]
		err = ResourceSaver.save(packed, path)
		if err != OK:
			push_error("MapGenerator bake: save failed (error %d) -> %s" % [err, path])
		else:
			print_rich("[b]Baked[/b] static scene -> %s" % path)
			print("Next: in game.tscn add a LocalMapTile (under town_tiles/city_tiles) with scene_path=\"%s\" and a TileMetadata whose coords match overworld_tile %s." % [path, map_template.overworld_tile])

	# Restore live authoring state.
	map_template = original_template
	generate_on_ready = original_flag

var noise: FastNoiseLite

# Overworld tile type enum value (OverworldTile); named to avoid clash with $base_terrain node
var base_terrain_type: int = OverworldTile.GRASS
var overworld_position: Vector2i

# Deterministic map seed to decouple sub-feature seeding from RNG consumption order
var current_map_seed: int = 0

# Runtime tile catalog built from tileset custom data (category / type / tag_1 / tag_2).
# Structure: tile_catalog[category][type] = Array[{source_id, atlas, size, tag_1, tag_2}]
var tile_catalog: Dictionary = {}

# Registry of available building.tscn variants, built at runtime by
# _build_building_registry(). Keyed by Structure.StructureType -> Array[String]
# of matching child node names (building_ids) found in building.tscn.
var building_ids_by_type: Dictionary = {}

# Instantiated building.tscn scenes, one per placed building; tracked so
# clear_all_layers() can free them before each regeneration.
var building_instances: Array = []

# Normalized copy of the TileMetadata dict passed to generate_local_map()
# (runtime wilderness path); empty for settlement/editor generation.
var current_metadata: Dictionary = {}

func clear_all_layers() -> void:
	ground.clear()
	road.clear()
	foliage.clear()
	terrain_features.clear()
	structures_exterior.clear()
	structures_interior.clear()
	decor_exterior.clear()
	for instance in building_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	building_instances.clear()

func _ready() -> void:
	# Validate required TileMapLayer nodes
	for layer_node in [ground, road, terrain_features, structures_exterior, structures_interior]:
		if not layer_node:
			push_error("Missing TileMapLayer node in MapGenerator scene '%s'!" % name)
			return
	noise = FastNoiseLite.new()
	tile_catalog.clear()
	for ts in get_all_tile_sets():
		_build_tile_catalog(ts)
	_build_building_registry()
	if generate_on_ready:
		clear_all_layers()
		setup_and_generate()

# Scans all atlas sources in the ground TileSet and builds tile_catalog from custom data.
# Call once after the tileset is loaded (i.e. from _ready()).

# Looks up a custom data value trying each name in order, returning the first
# non-null result. Used where a layer's name differs slightly between
# tilesets (e.g. "building_id" vs "building id").
func _get_custom_data_any(tile_data: TileData, names: Array):
	for n in names:
		var v = tile_data.get_custom_data(n)
		if v != null:
			return v
	return null

# Strips a trailing "_<digits>" suffix from a building.tscn child name (e.g.
# "house_1" -> "house", "log_cabin_1" -> "log_cabin") and looks it up in
# STRUCTURE_TYPE_NAME_MAP. Returns -1 if the name doesn't map to a known type.
func _structure_type_from_name(node_name: String) -> int:
	var parts := node_name.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return STRUCTURE_TYPE_NAME_MAP.get("_".join(parts), -1)

# Discovers available building variants by instantiating BUILDING_SCENE once
# and grouping its direct children (building_ids) by the Structure.StructureType
# inferred from each child's name. Skips BUILDING_TEMPLATE_NODE_NAME. Rebuilding
# this way (rather than hardcoding) means new building_id variants added to
# building.tscn are picked up automatically, no script changes required.
func _build_building_registry() -> void:
	building_ids_by_type.clear()
	var temp := BUILDING_SCENE.instantiate()
	for child in temp.get_children():
		if child.name == BUILDING_TEMPLATE_NODE_NAME:
			continue
		var struct_type := _structure_type_from_name(child.name)
		if struct_type == -1:
			continue
		if not building_ids_by_type.has(struct_type):
			building_ids_by_type[struct_type] = []
		building_ids_by_type[struct_type].append(String(child.name))
	temp.queue_free()
	print("Building registry built: ", building_ids_by_type)

# Parses a space-separated custom data String into an Array of tags.
# Used for "tags", "associated buildings", "affiliations", "classes",
# "cultures", "climates", and "biomes" layers, which all share this format.
func _parse_string_list(raw) -> Array:
	var list: Array = []
	if not raw is String:
		return list
	for entry in raw.split(" "):
		var stripped: String = entry.strip_edges()
		if not stripped.is_empty():
			list.append(stripped)
	return list

func get_all_tile_sets() -> Array:
	var tile_sets = []
	for node in [ground, road, terrain_features, structures_exterior, decor_exterior, structures_interior, foliage]:
		if node is TileMapLayer:
			var ts = node.tile_set
			if ts and not tile_sets.has(ts):
				tile_sets.append(ts)
	return tile_sets

func _build_tile_catalog(ts: TileSet) -> void:
	if not ts:
		push_error("No TileSet on ground layer – tile catalog empty")
		return
	for i in ts.get_source_count():
		var source_id := ts.get_source_id(i)
		var source := ts.get_source(source_id)
		if not source is TileSetAtlasSource:
			continue
		var atlas_source := source as TileSetAtlasSource
		for t in atlas_source.get_tiles_count():
			var coords := atlas_source.get_tile_id(t)
			var tile_data := atlas_source.get_tile_data(coords, 0)
			if not tile_data:
				continue
			# Not every TileSet defines the "category"/"type" custom data layers
			# (e.g. the premade building tileset) — get_custom_data() returns
			# null in that case, so guard before assigning to a String var.
			var category_raw = tile_data.get_custom_data("category")
			var tile_type_raw = tile_data.get_custom_data("type")
			if category_raw == null or tile_type_raw == null:
				continue
			var category: String = category_raw
			var tile_type: String = tile_type_raw
			if category.is_empty() or tile_type.is_empty():
				continue

			var subtype_raw = tile_data.get_custom_data("subtype")
			# "building_id"/"building id" layer name differs between tilesets — check both.
			var building_id_raw = _get_custom_data_any(tile_data, ["building_id", "building id"])
			var tags := _parse_string_list(tile_data.get_custom_data("tags"))
			var interior_raw = tile_data.get_custom_data("interior")
			var associated_buildings := _parse_string_list(tile_data.get_custom_data("associated buildings"))
			var affiliations := _parse_string_list(tile_data.get_custom_data("affiliations"))
			var classes := _parse_string_list(tile_data.get_custom_data("classes"))
			var cultures := _parse_string_list(tile_data.get_custom_data("cultures"))
			var climates := _parse_string_list(tile_data.get_custom_data("climates"))
			var biomes := _parse_string_list(tile_data.get_custom_data("biomes"))

			print("category: %s  type: %s, tags: %s" % [category, tile_type, tags])
			if not tile_catalog.has(category):
				tile_catalog[category] = {}
			if not tile_catalog[category].has(tile_type):
				tile_catalog[category][tile_type] = []
			tile_catalog[category][tile_type].append({
				"source_id": source_id,
				"atlas": coords,
				"size": atlas_source.get_tile_size_in_atlas(coords),
				"subtype": subtype_raw if subtype_raw is String else "",
				"building_id": building_id_raw if building_id_raw is String else "",
				"tags": tags,
				"interior": bool(interior_raw) if interior_raw != null else false,
				"associated_buildings": associated_buildings,
				"affiliations": affiliations,
				"classes": classes,
				"cultures": cultures,
				"climates": climates,
				"biomes": biomes,
			})
	print("Tile catalog built. Categories: ", tile_catalog.keys())

func setup_and_generate(
		map_type = map_template.map_type,
		overworld_tile_type: int = OverworldTile.GRASS,
		world_position: Vector2i = Vector2i.ZERO,
		seed_value: int = map_template.SEED
	) -> void:
	overworld_position = world_position
	var local_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		local_rng.seed = randi()
	else:
		local_rng.seed = seed_value

	match map_type:
		MapType.NON_SETTLEMENT:
			generate_local_area(overworld_tile_type, world_position, local_rng)
		MapType.SETTLEMENT, MapType.CASTLE_INTERIOR:
			# Layout priority: MainGameState stored layout (persisted from a
			# previous visit this save) > authored dataset baked into the
			# MapConfig > fresh generation.
			if not Engine.is_editor_hint() and _restore_settlement_layout():
				build_settlement_from_dataset()
			elif map_template.buildings and map_template.buildings.size() > 0:
				build_settlement_from_dataset()
			else:
				generate_settlement(local_rng)
	print("area seed is: ", local_rng.seed)

# Resolves the MainGameState autoload without a compile-time global, so this
# @tool script stays loadable in the editor and headless script contexts
# where autoload singletons aren't registered.
func _main_game_state() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("MainGameState")

## Rebuilds map_template.SEED + buildings from the MainGameState entry for
## this settlement, if a previous visit stored one. Returns true when a stored
## layout was applied. Keyed by map_template.overworld_tile.
func _restore_settlement_layout() -> bool:
	if map_template.overworld_tile == Vector2i.ZERO:
		return false
	var mgs := _main_game_state()
	if mgs == null:
		return false
	var key: String = mgs.make_settlement_key(int(map_template.map_type), map_template.overworld_tile)
	var entry: Dictionary = mgs.get_settlement(key)
	var stored = entry.get("buildings")
	if not stored is Array or (stored as Array).is_empty():
		return false
	map_template.SEED = int(entry.get("seed", map_template.SEED))
	map_template.buildings.clear()
	for bd in stored:
		if not bd is Dictionary:
			continue
		var s := Structure.new()
		s.TYPE = int(bd.get("type", Structure.StructureType.HOUSE)) as Structure.StructureType
		s.POSITION = bd.get("pos", Vector2i.ZERO)
		s.INTERIOR_SIZE = bd.get("size", Vector2i.ZERO)
		map_template.buildings.append(s)
	print("Restored settlement layout '%s' (%d buildings) from MainGameState" % [key, map_template.buildings.size()])
	return true

## Persists the generated layout into MainGameState.settlements (which the
## save system already serializes), so revisits and save/load rebuild the
## identical settlement via build_settlement_from_dataset(). Requires
## map_template.overworld_tile to be set on the settlement's MapConfig.
func _store_settlement_layout(seed_used: int) -> void:
	if Engine.is_editor_hint():
		return # autoloads aren't available in the editor; authoring uses bake instead
	if map_template.overworld_tile == Vector2i.ZERO:
		push_warning("MapGenerator: map_template.overworld_tile not set — settlement layout won't persist between visits")
		return
	var mgs := _main_game_state()
	if mgs == null:
		return
	var entry: Dictionary = mgs.ensure_settlement_config(
		int(map_template.map_type), map_template.overworld_tile, seed_used)
	entry["seed"] = seed_used
	if map_template.map_name != "":
		entry["name"] = map_template.map_name
	var stored_buildings: Array = []
	for b: Structure in map_template.buildings:
		if b == null:
			continue
		stored_buildings.append({
			"type": int(b.TYPE),
			"pos": b.POSITION,
			"size": b.INTERIOR_SIZE,
		})
	entry["buildings"] = stored_buildings

# Build a settlement from a saved dataset (no randomness in placement)
func build_settlement_from_dataset() -> void:
	clear_all_layers()

	var area_size = Vector2i(WIDTH, HEIGHT)
	var settlement_terrain = _get_settlement_terrain()
	current_map_seed = int(map_template.SEED)
	# Terrain variant picking consumes the global RNG (see generate_local_area).
	seed(current_map_seed)
	_configure_ground_noise(current_map_seed)

	# Building footprints are known up front here, so ground wear can be
	# computed before any terrain is painted.
	var building_rects: Array[Rect2i] = []
	for b: Structure in map_template.important_buildings + map_template.buildings:
		if b == null:
			continue
		var b_sprite_def = BUILDING_SPRITES.get(int(b.TYPE))
		if b_sprite_def:
			building_rects.append(Rect2i(b.POSITION, b_sprite_def["size"]))
	var wear := _build_wear_grid(building_rects)

	# Low-frequency patch noise: secondary terrain forms connected worn patches
	# instead of per-cell speckle, skewed toward buildings where the ground is
	# trampled bare.
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = current_map_seed ^ 0x51A7E5
	patch_noise.frequency = 1.0 / (map_template.noise_scale * 1.5)
	patch_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	patch_noise.fractal_octaves = 3

	for terrain in terrain_cells:
		terrain_cells[terrain].clear()
	for y in area_size.y:
		for x in area_size.x:
			var pos := Vector2i(x, y)
			var patch_val := (patch_noise.get_noise_2d(x, y) + 1.0) / 2.0
			patch_val += float(wear.get(pos, 0.0)) * 0.35
			var terrain_type: String = settlement_terrain["secondary"] if patch_val > 0.62 else settlement_terrain["primary"]
			terrain_cells[terrain_type].append(pos)
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			ground.set_cells_terrain_connect(terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)

	var placed_for_roads: Array = []
	for b: Structure in map_template.important_buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var pos: Vector2i = b.POSITION
		var size: Vector2i = sprite_def["size"]
		place_building_settlement(pos, size, enum_type)
		placed_for_roads.append({"type": enum_type, "pos": pos, "size": size})

	for b: Structure in map_template.buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var pos: Vector2i = b.POSITION
		var size: Vector2i = sprite_def["size"]
		place_building_settlement(pos, size, enum_type)
		placed_for_roads.append({"type": enum_type, "pos": pos, "size": size})

	generate_roads_between_buildings(placed_for_roads, RandomNumberGenerator.new())
	generate_edge_roads()
	var feature_rng := RandomNumberGenerator.new()
	feature_rng.seed = current_map_seed ^ 0x7EA7F00D
	add_terrain_features(feature_rng)
	add_foliage()
	add_decor_exterior(placed_for_roads)

func get_settlement_details() -> Dictionary:
	var details := {
		"type": int(map_template.map_type),
		"seed": map_template.SEED,
		"width": WIDTH,
		"height": HEIGHT,
		"pos": overworld_position,
		"buildings": {},
		"important_npcs": {}
	}
	var idx := 0
	for b: Structure in map_template.buildings:
		if b == null:
			continue
		var sprite_def = BUILDING_SPRITES.get(int(b.TYPE))
		var bsize: Vector2i = sprite_def["size"] if sprite_def else Vector2i(4, 4)
		var building_id = "%s_%d" % [str(b.TYPE).to_lower(), idx]
		details.buildings[building_id] = {
			"id": building_id,
			"type": int(b.TYPE),
			"pos": b.POSITION,
			"size": bsize,
			"zones": b.ZONES,
			"inhabitants": [],
			"interior_features": b.INTERIOR_FEATURES,
			"scripted_content": b.SCRIPTED_CONTENT
		}
		idx += 1
	return details

# Legacy function for backward compatibility
func setup_and_generate_local(overworld_tile_type: int, world_position: Vector2i, seed_value: int = 0) -> void:
	setup_and_generate(MapType.NON_SETTLEMENT, overworld_tile_type, world_position, seed_value)

## Runtime entry point for wilderness tiles (called by AreaContainer).
## Accepts a TileMetadata Resource or Dictionary from the world generator,
## merges it into map_template, and generates using the metadata's persisted
## seed so revisits reproduce the same map.
func generate_local_map(metadata) -> void:
	if typeof(metadata) == TYPE_OBJECT and metadata is TileMetadata:
		current_metadata = (metadata as TileMetadata).to_dict()
	elif metadata is Dictionary:
		current_metadata = metadata
	else:
		current_metadata = {}

	var world_pos: Vector2i = current_metadata.get("coords", Vector2i.ZERO)
	var terrain: int = current_metadata.get("terrain", OverworldTile.GRASS)
	var map_seed: int = int(current_metadata.get("seed", 0))

	_apply_metadata_to_config()

	clear_all_layers()
	var local_rng := RandomNumberGenerator.new()
	generate_local_area(terrain, world_pos, local_rng, map_seed)

## Push relevant world-generator metadata fields into map_template so every
## generation helper (add_foliage, generate_edge_roads, _generate_misc_features)
## reads from a single authoritative source.
func _apply_metadata_to_config() -> void:
	# Seed: generate_edge_roads and other helpers derive sub-seeds from
	# map_template.SEED, so it must match the metadata seed for determinism.
	map_template.SEED = int(current_metadata.get("seed", 0))

	# Road exits & surface
	map_template.road_exits = current_metadata.get("road_exits", 0)
	map_template.road_terrain = current_metadata.get("road_terrain", "dirt")

	# Foliage profile → tree_density enum + bush/rock floats
	var foliage_profile: Dictionary = current_metadata.get("foliage_profile", {})
	if foliage_profile.has("tree_density"):
		var td: float = foliage_profile["tree_density"]
		if td <= 0.0:
			map_template.tree_density = MapConfig.TreeDensity.NONE
		elif td < 0.25:
			map_template.tree_density = MapConfig.TreeDensity.SPARSE
		else:
			map_template.tree_density = MapConfig.TreeDensity.FOREST
	if foliage_profile.has("bush_density"):
		map_template.bush_density = foliage_profile["bush_density"]
	if foliage_profile.has("rock_density"):
		map_template.rock_density = foliage_profile["rock_density"]
		# The new tileset expresses rocks as clustered stone terrain features.
		map_template.stone_feature_density = foliage_profile["rock_density"]

	# Misc features — translate structured TileMetadata dicts into the enum
	# array that _generate_misc_features() reads.
	var features: Array[MapConfig.MiscFeatures] = []
	if current_metadata.get("hamlet", false):
		features.append(MapConfig.MiscFeatures.HAMLET)
	var farm_data = current_metadata.get("farm_plot", null)
	if farm_data is Dictionary and farm_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.FARM)
	var dungeon_data = current_metadata.get("dungeon_entrance", null)
	if dungeon_data is Dictionary and dungeon_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.DUNGEON_ENTRANCE)
	var camp_data = current_metadata.get("camp", null)
	if camp_data is Dictionary and camp_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.CAMP)
	var ruins_data = current_metadata.get("ruins", null)
	if ruins_data is Dictionary and ruins_data.get("exists", false):
		features.append(MapConfig.MiscFeatures.RUIN)
	map_template.misc_features = features

func generate_local_area(overworld_tile_type: int, world_position: Vector2i, local_rng: RandomNumberGenerator, seed_override: int = 0) -> void:
	base_terrain_type = overworld_tile_type
	overworld_position = world_position
	print("Generating local area at position: ", world_position, " with terrain type: ", base_terrain_type)

	# Seed priority: explicit override (runtime metadata seed) > the RNG's
	# existing seed (assigned by setup_and_generate from map_template.SEED,
	# or randi() when SEED is 0).
	var map_seed: int = seed_override if seed_override != 0 else int(local_rng.seed)
	current_map_seed = map_seed
	local_rng.seed = map_seed
	# set_cells_terrain_connect picks among same-terrain variant tiles using
	# the GLOBAL RNG — seed it so revisits repaint identical tile variants.
	seed(map_seed)
	_configure_ground_noise(map_seed)
	print("local area seed: ", map_seed, " for terrain: ", base_terrain_type)

	for terrain in terrain_cells:
		terrain_cells[terrain].clear()

	var area_size = Vector2i(WIDTH, HEIGHT)
	for y in area_size.y:
		for x in area_size.x:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2
			var ground_tile = get_ground_tile(x, y, height)
			var terrain_type = GROUND_TERRAIN_MAP[ground_tile]
			terrain_cells[terrain_type].append(Vector2i(x, y))

	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			ground.set_cells_terrain_connect(
				terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)

	if base_terrain_type == OverworldTile.GRASS:
		maybe_add_water_features(local_rng)

	_generate_misc_features(local_rng)
	generate_edge_roads()
	add_terrain_features(local_rng)
	add_foliage()

# Generate settlement function driven by MapConfig fields.
func generate_settlement(settlement_rng: RandomNumberGenerator) -> void:
	map_template.SEED = settlement_rng.seed
	var area_size = Vector2i(WIDTH, HEIGHT)
	var density: int = int(map_template.building_density)
	var building_counts: Dictionary = BUILDING_COUNTS_BY_DENSITY.get(density, {})
	print("Generating settlement '%s' density=%d  counts=%s" % [map_template.map_name, density, building_counts])

	clear_all_layers()
	# The MainGameState entry (written below) is the durable copy of the
	# layout; clear anything a previous in-session generation appended to the
	# shared embedded MapConfig so regeneration can't duplicate buildings.
	map_template.buildings.clear()
	# Terrain variant picking consumes the global RNG (see generate_local_area).
	seed(int(map_template.SEED))
	# Seed the ground noise explicitly — previously generate_settlement sampled
	# whatever state the noise object happened to be in.
	_configure_ground_noise(int(map_template.SEED))

	for terrain in terrain_cells:
		terrain_cells[terrain].clear()

	for y in area_size.y:
		for x in area_size.x:
			var height = noise.get_noise_2d(x, y)
			height = (height + 1) / 2
			var ground_tile = get_ground_tile(x, y, height)
			var terrain_type = GROUND_TERRAIN_MAP[ground_tile]
			terrain_cells[terrain_type].append(Vector2i(x, y))
	
	for terrain in terrain_cells:
		if not terrain_cells[terrain].is_empty():
			ground.set_cells_terrain_connect(
				terrain_cells[terrain], TERRAIN_SET_ID, TERRAINS[terrain], false)
		else:
			print("No cells for terrain type: ", terrain)

	current_map_seed = map_template.SEED

	var occupied_space_grid = []
	for y in area_size.y:
		occupied_space_grid.append([])
		for x in area_size.x:
			occupied_space_grid[y].append(false)

	var placed_buildings: Array = []

	for b: Structure in map_template.important_buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = BUILDING_SPRITES.get(enum_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		var pos: Vector2i = b.POSITION
		if pos == Vector2i.ZERO:
			pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, enum_type)
			b.POSITION = pos
		if pos.x != -1:
			place_building_settlement(pos, size, enum_type)
			mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
			placed_buildings.append({"type": enum_type, "pos": pos, "size": size})

	var building_order = [Structure.StructureType.MANOR, Structure.StructureType.TAVERN, Structure.StructureType.SHOP, Structure.StructureType.HOUSE]
	for building_type in building_order:
		var count: int = building_counts.get(building_type, 0)
		var sprite_def = BUILDING_SPRITES.get(building_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		for _i in count:
			var pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, building_type)
			if pos.x != -1:
				place_building_settlement(pos, size, building_type)
				mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
				placed_buildings.append({"type": building_type, "pos": pos, "size": size})
				var s := Structure.new()
				s.TYPE = building_type
				s.POSITION = pos
				s.INTERIOR_SIZE = size
				s.ZONES = []
				s.INTERIOR_FEATURES = []
				s.SCRIPTED_CONTENT = null
				map_template.buildings.append(s)
	
	generate_roads_between_buildings(placed_buildings, settlement_rng)
	generate_edge_roads()
	add_terrain_features(settlement_rng)
	add_foliage()
	add_decor_exterior(placed_buildings)

	_store_settlement_layout(int(map_template.SEED))

	print_rich("Generated settlement with ", map_template.buildings.size(), " buildings")

func get_ground_tile(_x: int, _y: int, height: float) -> int:
	if base_terrain_type == OverworldTile.GRASS:
		if height > 0.8:
			return GroundTile.STONE
		return GroundTile.GRASS
	if base_terrain_type == OverworldTile.MOUNTAIN:
		if height < 0.4:
			return GroundTile.GRASS
		elif height < 0.7:
			return GroundTile.DIRT
		return GroundTile.STONE
	if base_terrain_type == OverworldTile.WATER:
		return GroundTile.WATER
	return GroundTile.GRASS

# ── Generation helpers ──────────────────────────────────────────────────────

# Configures the shared ground noise. fBm octaves roughen terrain boundaries
# (coastline-like edges instead of smooth blobs) and domain warp breaks up the
# round, axis-agnostic shapes single-frequency noise produces.
func _configure_ground_noise(seed_value: int) -> void:
	noise.seed = seed_value
	noise.frequency = 1.0 / map_template.noise_scale
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = map_template.noise_scale

# Stable per-area seed shared by the foliage and terrain-feature passes so
# their noise fields line up (e.g. flowers avoiding the same forest cores).
func _foliage_derived_seed() -> int:
	return int(current_map_seed) ^ (overworld_position.x * 73856093) ^ (overworld_position.y * 19349663) ^ int(base_terrain_type)

# Low-frequency forest mask — large blobs defining where forest regions exist.
# High values = forest core, low values = open clearing.
func _make_forest_noise(derived_seed: int) -> FastNoiseLite:
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = derived_seed ^ 0x1A2B3C4D
	forest_noise.frequency = 1.0 / (map_template.noise_scale * 4.0)
	return forest_noise

# Mid-frequency mask used to gather a terrain-feature family into patches.
func _make_cluster_noise(seed_value: int) -> FastNoiseLite:
	var cluster_noise := FastNoiseLite.new()
	cluster_noise.seed = seed_value
	cluster_noise.frequency = 1.0 / (map_template.noise_scale * 2.5)
	return cluster_noise

# Converts a cluster-noise sample into a density weight in [0, 2]: near zero
# outside the family's patches, up to 2x inside, averaging ~1 map-wide.
func _cluster_weight(cluster_noise: FastNoiseLite, pos: Vector2i) -> float:
	var v := (cluster_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
	return smoothstep(0.35, 0.65, v) * 2.0

func _has_neighbor_of_type(pos: Vector2i, target_type: int) -> bool:
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if get_cell_ground_type(pos + offset) == target_type:
			return true
	return false

# All map cells in a deterministic shuffled order (Fisher–Yates driven by the
# supplied RNG; Array.shuffle() would use the global RNG and break seeding).
func _shuffled_cells(shuffle_rng: RandomNumberGenerator) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in HEIGHT:
		for x in WIDTH:
			cells.append(Vector2i(x, y))
	for i in range(cells.size() - 1, 0, -1):
		var j := shuffle_rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells

# Ground-wear map around building footprints: 1.0 at the walls, falling to 0
# at WEAR_RADIUS tiles out (Chebyshev distance).
func _build_wear_grid(building_rects: Array[Rect2i]) -> Dictionary:
	var wear: Dictionary = {}
	for rect in building_rects:
		for y in range(rect.position.y - WEAR_RADIUS, rect.end.y + WEAR_RADIUS):
			for x in range(rect.position.x - WEAR_RADIUS, rect.end.x + WEAR_RADIUS):
				if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
					continue
				var dx := maxi(0, maxi(rect.position.x - x, x - rect.end.x + 1))
				var dy := maxi(0, maxi(rect.position.y - y, y - rect.end.y + 1))
				var w := 1.0 - float(maxi(dx, dy)) / float(WEAR_RADIUS)
				if w <= 0.0:
					continue
				var cell := Vector2i(x, y)
				wear[cell] = maxf(float(wear.get(cell, 0.0)), w)
	return wear

func add_foliage() -> void:
	var derived_seed := _foliage_derived_seed()

	# High-frequency detail noise — fine-grained placement decisions within regions
	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = derived_seed
	detail_noise.frequency = 1.0 / (map_template.noise_scale * 0.5)

	var forest_noise := _make_forest_noise(derived_seed)

	# Warp noise — displaces sample coordinates so forest edges become curved
	# and irregular rather than axis-aligned bands.
	var warp_noise := FastNoiseLite.new()
	warp_noise.seed = derived_seed ^ 0xDEAD1234
	warp_noise.frequency = 1.0 / (map_template.noise_scale * 1.5)

	# Bark color noise — large slow-changing regions share a dominant bark color
	# so birch groves, oak stands, etc. cluster naturally.
	var bark_noise := FastNoiseLite.new()
	bark_noise.seed = derived_seed ^ 0x7E3F9A1B
	bark_noise.frequency = 1.0 / (map_template.noise_scale * 3.0)

	var foliage_rng := RandomNumberGenerator.new()
	foliage_rng.seed = derived_seed ^ 0x5A5A5A5A

	var tree_tiles: Array = tile_catalog.get("foliage", {}).get("tree", [])
	var bush_tiles: Array = tile_catalog.get("foliage", {}).get("bush", [])

	# Split tree tiles by bark color tag and alive/dead status.
	var brown_bark_tiles: Array = []
	var white_bark_tiles: Array = []
	var grey_bark_tiles: Array = []
	var dead_tree_tiles: Array = []
	var other_tree_tiles: Array = []
	for _td in tree_tiles:
		var _tags: Array = _td.get("tags", [])
		if "dead" in _tags or "broken" in _tags:
			dead_tree_tiles.append(_td)
		elif "brown_bark" in _tags:
			brown_bark_tiles.append(_td)
		elif "white_bark" in _tags:
			white_bark_tiles.append(_td)
		elif "grey_bark" in _tags:
			grey_bark_tiles.append(_td)
		else:
			other_tree_tiles.append(_td)
	var all_live_trees: Array = brown_bark_tiles + grey_bark_tiles + white_bark_tiles + other_tree_tiles

	# Track which cells are already covered by a placed multi-tile sprite
	var used_cells: Dictionary = {}
	# Track origin positions per atlas tile to prevent identical sprites clustering.
	# Key: "sourceId_atlasX_atlasY"  Value: Array[Vector2i] of placed origins
	var placed_type_positions: Dictionary = {}
	const FOLIAGE_SAME_TILE_MIN_DIST := 8

	# Visit cells in shuffled order — a fixed top-left scan lets earlier cells
	# greedily claim multi-tile footprints, skewing forests toward the top-left
	# of every eligible region.
	for pos: Vector2i in _shuffled_cells(foliage_rng):
		var x := pos.x
		var y := pos.y
		if used_cells.has(pos):
			continue

		# Skip if a road tile is present at this cell or within 1 tile
		var near_road := false
		for check_dy in range(-1, 2):
			for check_dx in range(-1, 2):
				if road.get_cell_source_id(pos + Vector2i(check_dx, check_dy)) != -1:
					near_road = true
					break
			if near_road:
				break
		if near_road:
			continue

		var ground_type = get_cell_ground_type(pos)
		if ground_type == -1:
			print("Could not determine ground type for cell %s, skipping foliage" % pos)
			continue

		if ground_type in [GroundTile.GRASS, GroundTile.DIRT, GroundTile.STONE]:
			var local_tree_density: float = TREE_DENSITY_VALUES.get(
				int(map_template.tree_density), 0.06)
			var local_bush_density: float = map_template.bush_density * 0.4

			# Forest mask (0–1), smoothstepped so clearings stay genuinely clear
			# and cores stay dense, instead of a linear haze of trees everywhere.
			var forest_mask := (forest_noise.get_noise_2d(x, y) + 1.0) / 2.0
			local_tree_density *= smoothstep(0.35, 0.7, forest_mask) * 2.0

			# Bushes are the forest-edge understory: they peak in the transition
			# band around the mask midpoint and thin out in deep forest and open
			# ground, leaving a shrubby fringe around each stand of trees.
			var edge_band := 1.0 - clampf(absf(forest_mask - 0.5) / 0.25, 0.0, 1.0)
			local_bush_density *= 0.3 + 1.4 * edge_band

			# Domain warping: offset the detail noise sample coords using a
			# perpendicular warp so forest edges curve organically.
			var warp_strength := map_template.noise_scale * 0.35
			var wx := x + warp_strength * warp_noise.get_noise_2d(x * 0.5, y * 0.5)
			var wy := y + warp_strength * warp_noise.get_noise_2d(x * 0.5 + 31.7, y * 0.5 + 17.3)
			var detail_value := (detail_noise.get_noise_2d(wx, wy) + 1.0) / 2.0

			match ground_type:
				GroundTile.DIRT:
					local_tree_density *= 0.3
					local_bush_density *= 0.5
				GroundTile.STONE:
					local_tree_density *= 0.5
					local_bush_density *= 0.7

			# Bark-color region: sample once per cell so all trees at this
			# location share the same preferred species.
			var bark_val := (bark_noise.get_noise_2d(x, y) + 1.0) / 2.0
			var dominant_bark: Array
			if bark_val < 0.33:
				dominant_bark = brown_bark_tiles
			elif bark_val < 0.66:
				dominant_bark = grey_bark_tiles
			else:
				dominant_bark = white_bark_tiles
			if dominant_bark.is_empty():
				dominant_bark = all_live_trees

			var candidates: Array = []
			if detail_value < local_tree_density:
				var tree_roll := foliage_rng.randf()
				# Dead/broken trees are rare in the open but more common deep
				# in the forest where old growth crowds itself out.
				var dead_chance := 0.015 + 0.05 * smoothstep(0.55, 0.85, forest_mask)
				if tree_roll < dead_chance and not dead_tree_tiles.is_empty():
					candidates = dead_tree_tiles
				elif tree_roll < 0.75 and not dominant_bark.is_empty():
					# dominant bark color for this region
					candidates = dominant_bark
				elif not all_live_trees.is_empty():
					# ~25 % chance: any live tree (fringe / mixed edge)
					candidates = all_live_trees
				else:
					candidates = tree_tiles
			elif detail_value < local_tree_density + local_bush_density:
				candidates = bush_tiles

			if not candidates.is_empty():
				var fdata: Dictionary = candidates[foliage_rng.randi() % candidates.size()]
				var fsize: Vector2i = fdata["size"]
				# Only place if the full sprite footprint is free
				var area_free = true
				for dy in fsize.y:
					for dx in fsize.x:
						if used_cells.has(pos + Vector2i(dx, dy)):
							area_free = false
							break
					if not area_free:
						break
				if area_free:
					var type_key := "%d_%d_%d" % [fdata["source_id"], fdata["atlas"].x, fdata["atlas"].y]
					var too_close := false
					if placed_type_positions.has(type_key):
						for prev_pos: Vector2i in placed_type_positions[type_key]:
							if maxi(absi(pos.x - prev_pos.x), absi(pos.y - prev_pos.y)) < FOLIAGE_SAME_TILE_MIN_DIST:
								too_close = true
								break
					if not too_close:
						var flip_h := 4096 if foliage_rng.randf() < 0.5 else 0
						foliage.set_cell(pos, fdata["source_id"], fdata["atlas"], flip_h)
						for dy in fsize.y:
							for dx in fsize.x:
								used_cells[pos + Vector2i(dx, dy)] = true
						if not placed_type_positions.has(type_key):
							placed_type_positions[type_key] = []
						placed_type_positions[type_key].append(pos)

func add_decor_exterior(placed_buildings: Array) -> void:
	var decor_types: Dictionary = tile_catalog.get("decor_exterior", {})
	if decor_types.is_empty():
		return

	# Split tiles into wall-adjacent and open pools
	var wall_adjacent_tiles: Array = []
	var open_tiles: Array = []
	for tile_type in decor_types:
		for entry in decor_types[tile_type]:
			if "wall_adjacent" in entry.get("tags", []):
				wall_adjacent_tiles.append(entry)
			else:
				open_tiles.append(entry)

	var decor_rng := RandomNumberGenerator.new()
	decor_rng.seed = current_map_seed ^ 0xBADC0FFE
	var used_cells: Dictionary = {}

	for building in placed_buildings:
		var bpos: Vector2i = building["pos"]
		var bsize: Vector2i = building["size"]

		# Wall-adjacent tiles: place in the 1-tile border just outside the footprint
		for dx in range(-1, bsize.x + 1):
			for dy in range(-1, bsize.y + 1):
				if dx >= 0 and dx < bsize.x and dy >= 0 and dy < bsize.y:
					continue
				var cell := bpos + Vector2i(dx, dy)
				if cell.x < 0 or cell.x >= WIDTH or cell.y < 0 or cell.y >= HEIGHT:
					continue
				if used_cells.has(cell) or road.get_cell_source_id(cell) != -1:
					continue
				if structures_exterior.get_cell_source_id(cell) != -1:
					continue
				if wall_adjacent_tiles.is_empty() or decor_rng.randf() > 0.15:
					continue
				var entry: Dictionary = wall_adjacent_tiles[decor_rng.randi() % wall_adjacent_tiles.size()]
				var esize: Vector2i = entry["size"]
				var fits := true
				for edy in esize.y:
					for edx in esize.x:
						var ec := cell + Vector2i(edx, edy)
						if ec.x >= WIDTH or ec.y >= HEIGHT or used_cells.has(ec):
							fits = false; break
					if not fits: break
				if fits:
					decor_exterior.set_cell(cell, entry["source_id"], entry["atlas"])
					for edy in esize.y:
						for edx in esize.x:
							used_cells[cell + Vector2i(edx, edy)] = true

		# Open tiles: scatter in the 2–4 tile ring around the building
		if open_tiles.is_empty():
			continue
		for dx in range(-4, bsize.x + 4):
			for dy in range(-4, bsize.y + 4):
				var dist_x := maxi(0, maxi(-dx, dx - bsize.x + 1))
				var dist_y := maxi(0, maxi(-dy, dy - bsize.y + 1))
				if dist_x + dist_y <= 1:
					continue
				var cell := bpos + Vector2i(dx, dy)
				if cell.x < 0 or cell.x >= WIDTH or cell.y < 0 or cell.y >= HEIGHT:
					continue
				if used_cells.has(cell) or road.get_cell_source_id(cell) != -1:
					continue
				if structures_exterior.get_cell_source_id(cell) != -1:
					continue
				if decor_rng.randf() > 0.08:
					continue
				var entry: Dictionary = open_tiles[decor_rng.randi() % open_tiles.size()]
				if "rare" in entry.get("tags", []) and decor_rng.randf() < 0.7:
					continue
				var esize: Vector2i = entry["size"]
				var fits := true
				for edy in esize.y:
					for edx in esize.x:
						var ec := cell + Vector2i(edx, edy)
						if ec.x >= WIDTH or ec.y >= HEIGHT or used_cells.has(ec):
							fits = false; break
					if not fits: break
				if fits:
					decor_exterior.set_cell(cell, entry["source_id"], entry["atlas"])
					for edy in esize.y:
						for edx in esize.x:
							used_cells[cell + Vector2i(edx, edy)] = true

func add_terrain_features(local_rng: RandomNumberGenerator) -> void:
	# Feature pools read from tileset custom data via tile_catalog.
	var tf: Dictionary = tile_catalog.get("terrain_features", {})
	var fol: Dictionary = tile_catalog.get("foliage", {})

	# Flowers are split across "terrain_features/flowers" (source 0) and
	# "foliage/flowers" (source 2) in the tileset, so merge both pools.
	var grass_patch_tiles: Array = tf.get("grass patch", [])
	var flower_tiles: Array = tf.get("flowers", []) + fol.get("flowers", [])
	var puddle_tiles: Array = tf.get("puddle", [])
	var dirt_patch_tiles: Array = tf.get("dirt patch", [])
	var mud_tiles: Array = tf.get("mud patch", [])
	var stone_tiles: Array = tf.get("rock patch", []) + tf.get("crevasse", [])

	var used_cells: Dictionary = {}

	# Per-family cluster masks: each feature family gets its own low-frequency
	# noise so features drift into patches (flower drifts, rock fields, wet
	# hollows) instead of an even sprinkle across the whole map.
	var derived_seed := _foliage_derived_seed()
	var flower_mask := _make_cluster_noise(derived_seed ^ 0x0F10)
	var scruff_mask := _make_cluster_noise(derived_seed ^ 0x5C2F)
	var wet_mask := _make_cluster_noise(derived_seed ^ 0x0DD1)
	var rock_mask := _make_cluster_noise(derived_seed ^ 0x50CC)
	# Flowers favour open clearings, so sample the same forest mask foliage uses.
	var forest_noise := _make_forest_noise(derived_seed)

	# Shuffled visit order so multi-tile features don't systematically win
	# contested space toward the top-left (same fix as add_foliage).
	for pos: Vector2i in _shuffled_cells(local_rng):
		if used_cells.has(pos):
			continue

		if road.get_cell_source_id(pos) != -1:
			continue

		var ground_type := get_cell_ground_type(pos)
		if ground_type == -1 or ground_type == GroundTile.WATER:
			continue

		if local_rng.randf() > map_template.terrain_feature_density:
			continue

		# Puddles and mud collect in low, wet ground: gate on the ground height
		# noise so wet features pool in hollows rather than on rises.
		var height := (noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
		var wet_weight := _cluster_weight(wet_mask, pos) * (1.0 if height < 0.5 else 0.25)

		# Build candidate pool from whichever categories roll active for this cell
		var candidates: Array = []
		match ground_type:
			GroundTile.GRASS:
				# Grass tufts thicken along grass↔dirt boundaries (scruffy fringes)
				var grass_weight := _cluster_weight(scruff_mask, pos)
				if _has_neighbor_of_type(pos, GroundTile.DIRT):
					grass_weight = maxf(grass_weight, 1.5)
				if local_rng.randf() < map_template.grass_feature_density * grass_weight:
					candidates.append_array(grass_patch_tiles)
				# Flowers cluster in drifts and favour clearings over forest floor
				var forest_mask := (forest_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
				var clearing := 1.0 - smoothstep(0.35, 0.7, forest_mask)
				if local_rng.randf() < map_template.flower_density * _cluster_weight(flower_mask, pos) * (0.25 + 0.75 * clearing):
					candidates.append_array(flower_tiles)
				if local_rng.randf() < map_template.puddle_density * wet_weight:
					candidates.append_array(puddle_tiles)
			GroundTile.DIRT:
				if local_rng.randf() < map_template.dirt_feature_density * _cluster_weight(scruff_mask, pos):
					candidates.append_array(dirt_patch_tiles)
				if local_rng.randf() < map_template.mud_feature_density * wet_weight:
					candidates.append_array(mud_tiles)
				if local_rng.randf() < map_template.puddle_density * wet_weight:
					candidates.append_array(puddle_tiles)
			GroundTile.STONE:
				if local_rng.randf() < map_template.stone_feature_density * _cluster_weight(rock_mask, pos):
					candidates.append_array(stone_tiles)

		if candidates.is_empty():
			continue

		var fdata: Dictionary = candidates[local_rng.randi() % candidates.size()]
		var fsize: Vector2i = fdata["size"]

		# Verify the full footprint is free of existing features and roads
		var area_free := true
		for dy in fsize.y:
			for dx in fsize.x:
				var check := pos + Vector2i(dx, dy)
				if check.x >= WIDTH or check.y >= HEIGHT:
					area_free = false
					break
				if used_cells.has(check):
					area_free = false
					break
				if road.get_cell_source_id(check) != -1:
					area_free = false
					break
			if not area_free:
				break
		if not area_free:
			continue

		terrain_features.set_cell(pos, fdata["source_id"], fdata["atlas"])
		for dy in fsize.y:
			for dx in fsize.x:
				used_cells[pos + Vector2i(dx, dy)] = true

# Water features are gated OFF until water tiles exist in grassland_poneti.tres
# (the "water" terrain set index is a placeholder). Flip this on once the water
# terrain is painted — the generation below is already deterministic.
const WATER_FEATURES_ENABLED := false

func maybe_add_water_features(local_rng: RandomNumberGenerator) -> void:
	if not WATER_FEATURES_ENABLED:
		return
	# 30% chance to add a water feature
	if local_rng.randf() > 0.3:
		return
	# Decide between lake or river
	if local_rng.randf() > 0.5:
		generate_lake(local_rng)
	else:
		generate_river(local_rng)

func generate_lake(local_rng: RandomNumberGenerator) -> void:
	var center = Vector2i(
		local_rng.randi_range(10, WIDTH - 10),
		local_rng.randi_range(10, HEIGHT - 10)
	)
	var size = local_rng.randi_range(3, 8)

	var water_cells = []

	for y in range(-size, size + 1):
		for x in range(-size, size + 1):
			var pos = center + Vector2i(x, y)
			if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
				continue

			var dist = sqrt(x * x + y * y)
			if dist <= size + local_rng.randf() * 2 - 1: # Irregular edges
				water_cells.append(pos)

	# Apply water terrain to all cells at once using the terrain system
	if water_cells.size() > 0:
		ground.set_cells_terrain_connect(water_cells, TERRAIN_SET_ID, TERRAINS["water"])

func generate_river(local_rng: RandomNumberGenerator) -> void:
	var start = Vector2i(
		local_rng.randi_range(0, WIDTH),
		0 if local_rng.randi() % 2 == 0 else HEIGHT - 1
	)
	var end = Vector2i(
		local_rng.randi_range(0, WIDTH),
		HEIGHT - 1 if start.y == 0 else 0
	)

	var river_cells = []
	var current = start
	while current != end:
		river_cells.append(current)

		# Move towards end with some randomness
		var dir = Vector2(end - current).normalized()
		current += Vector2i(
			sign(dir.x) if local_rng.randf() > 0.3 else local_rng.randi_range(-1, 1),
			sign(dir.y)
		)
		current.x = clamp(current.x, 0, WIDTH - 1)
		current.y = clamp(current.y, 0, HEIGHT - 1)

	# Apply water terrain to all river cells at once using the terrain system
	if river_cells.size() > 0:
		ground.set_cells_terrain_connect(river_cells, TERRAIN_SET_ID, TERRAINS["water"])

func get_cell_ground_type(coords: Vector2i) -> int:
	var tile_data = ground.get_cell_tile_data(coords)
	if not tile_data:
		return -1
	var terrain = tile_data.terrain
	for tile in GROUND_TERRAIN_MAP:
		if TERRAINS[GROUND_TERRAIN_MAP[tile]] == terrain:
			return tile
	return -1

# Returns the tileset "type" custom data string for the foliage tile at coords,
# or an empty string if no foliage is present.
func get_cell_foliage_type(coords: Vector2i) -> String:
	var source_id := foliage.get_cell_source_id(coords)
	if source_id == -1:
		return ""
	var ts := ground.tile_set
	if not ts:
		return ""
	var source := ts.get_source(source_id)
	if not source is TileSetAtlasSource:
		return ""
	var tile_data := (source as TileSetAtlasSource).get_tile_data(
			foliage.get_cell_atlas_coords(coords), 0)
	if not tile_data:
		return ""
	return tile_data.get_custom_data("type")

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
	var ground_type = get_cell_ground_type(pos)
	if ground_type == GroundTile.WATER:
		return false
	# Block if any foliage sprite is at this position
	if foliage.get_cell_source_id(pos) != -1:
		return false
	# Block if static collision geometry (building walls, props) covers the tile
	if _is_physics_blocked(pos):
		return false
	return true

## Point-queries the 2D physics space at the tile centre so navigation and
## walkability respect the same tileset collision polygons the movement
## raycasts hit (building walls, blocking props). Only static geometry counts:
## CharacterBody2D colliders (player, NPCs) are ignored so moving actors don't
## poison the nav grid. Note the physics space registers freshly added
## TileMapLayers on the next physics step — query after a physics frame when
## building grids for a just-loaded area.
func _is_physics_blocked(pos: Vector2i) -> bool:
	if Engine.is_editor_hint() or not is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var params := PhysicsPointQueryParameters2D.new()
	params.position = ground.to_global(ground.map_to_local(pos))
	params.collide_with_areas = false
	params.collide_with_bodies = true
	for hit in space.intersect_point(params, 4):
		var collider = hit.get("collider")
		if collider is TileMapLayer or collider is StaticBody2D:
			return true
	return false

func generate_hamlet(hamlet_type: String, local_rng: RandomNumberGenerator) -> void:
	var building_count = 0
	match hamlet_type:
		"village":
			building_count = local_rng.randi_range(3, 6)
		"farm":
			building_count = local_rng.randi_range(2, 4)
	
	# Create a grid to track building placement
	var occupation_grid = []
	for y in HEIGHT:
		occupation_grid.append([])
		for x in WIDTH:
			occupation_grid[y].append(false)
	
	# Place buildings
	var buildings_placed = 0
	var attempts = 0
	while buildings_placed < building_count and attempts < 100:
		var building_type = HamletStructureType.values()[local_rng.randi() % HamletStructureType.size()]
		if try_place_building(building_type, occupation_grid, local_rng):
			buildings_placed += 1
		attempts += 1

func try_place_building(hamlet_type: int, occupation_grid: Array, local_rng: RandomNumberGenerator) -> bool:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	if not sprite_def:
		return false
	var size: Vector2i = sprite_def["size"]
	var pos = find_valid_building_position(Vector2i(WIDTH, HEIGHT), size, occupation_grid, local_rng, hamlet_type)
	if pos.x == -1:
		return false
	place_building(pos, size, hamlet_type)
	mark_occupied(occupation_grid, pos, size, sprite_def["spacing"])
	return true

func find_valid_building_position(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, local_rng: RandomNumberGenerator, hamlet_type: int) -> Vector2i:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	var spacing: int = sprite_def["spacing"] if sprite_def else 1
	var attempts = 0
	
	while attempts < 100:
		var x = local_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = local_rng.randi_range(spacing, area_size.y - size.y - spacing)
		var valid = true
		
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x = x + dx
				var check_y = y + dy
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
			if not valid:
				break
		
		if valid:
			return Vector2i(x, y)
		attempts += 1
	
	return Vector2i(-1, -1)

func mark_occupied(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

# Place a hamlet building using a premade sprite
func place_building(pos: Vector2i, size: Vector2i, hamlet_type: int) -> void:
	var struct_type: int = HAMLET_TYPE_MAP.get(hamlet_type, Structure.StructureType.HOUSE)
	var sprite_def = BUILDING_SPRITES.get(struct_type)
	if not sprite_def:
		push_warning("No BUILDING_SPRITES entry for hamlet type %d" % hamlet_type)
		return
	print("Placing hamlet building type %d at %s" % [hamlet_type, pos])
	_place_building_sprite(pos, size, sprite_def, struct_type)

# Settlement-specific building functions
func find_valid_building_position_settlement(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, settlement_rng: RandomNumberGenerator, building_type: int) -> Vector2i:
	var sprite_def = BUILDING_SPRITES.get(building_type)
	var spacing: int = sprite_def["spacing"] if sprite_def else 1
	var attempts = 0
	var best_pos = Vector2i(-1, -1)
	var best_score = -1.0
	var center = Vector2(area_size.x / 2.0, area_size.y / 2.0)
	var max_distance = center.length()
	
	var density: int = int(map_template.building_density)
	var use_scoring: bool = density >= MapConfig.BuildingDensity.SMALL_TOWN
	var positions_to_try = 10 if use_scoring else 1
	
	while attempts < 100:
		var x = settlement_rng.randi_range(spacing, area_size.x - size.x - spacing)
		var y = settlement_rng.randi_range(spacing, area_size.y - size.y - spacing)
		var valid = true
		
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x = x + dx
				var check_y = y + dy
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
			if not valid:
				break
		
		if valid:
			if not use_scoring:
				return Vector2i(x, y)
			var pos_center = Vector2(x + size.x / 2.0, y + size.y / 2.0)
			var distance = pos_center.distance_to(center)
			var score = 1.0 - (distance / max_distance)
			score += settlement_rng.randf_range(-0.1, 0.1)
			if score > best_score:
				best_score = score
				best_pos = Vector2i(x, y)
			positions_to_try -= 1
			if positions_to_try <= 0:
				return best_pos
		
		attempts += 1
	
	return best_pos if best_pos.x != -1 else Vector2i(-1, -1)

func mark_occupied_settlement(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

# Place a settlement building using a premade sprite
func place_building_settlement(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var sprite_def = BUILDING_SPRITES.get(building_type)
	if not sprite_def:
		push_warning("No BUILDING_SPRITES entry for building type %d" % building_type)
		return
	print("Placing settlement building type %d at %s" % [building_type, pos])
	_place_building_sprite(pos, size, sprite_def, building_type)

# ── Shared sprite placement ────────────────────────────────────────────────
# Paints ground terrain under the footprint, clears foliage, then instances
# the unified building scene (exterior + interior) for this building.
# structures_exterior/structures_interior share the same coordinate space as
# the ground layer provided both tilesets use the same tile_size (16 × 16 px).
func _place_building_sprite(pos: Vector2i, size: Vector2i, sprite_def: Dictionary, building_type: int) -> void:
	# Seeded RNG for deterministic patch variation tied to building position
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = int(pos.x * 73856093) ^ int(pos.y * 19349663)

	# Patch is centered explicitly on the building's center tile so all four
	# sides have equal margin.  MIN_CLEAR tiles around the footprint are always
	# included; JITTER additional tiles are added probabilistically for organic
	# edges.
	const MIN_CLEAR := 2
	const JITTER    := 5
	var cx := pos.x + size.x / 2
	var cy := pos.y + size.y / 2

	var building_cells: Array[Vector2i] = []
	for dy in range(-(size.y / 2 + MIN_CLEAR + JITTER), size.y / 2 + MIN_CLEAR + JITTER + 1):
		for dx in range(-(size.x / 2 + MIN_CLEAR + JITTER), size.x / 2 + MIN_CLEAR + JITTER + 1):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
				continue
			# Manhattan distance outside the building footprint
			var dist_x := 0
			if x < pos.x:
				dist_x = pos.x - x
			elif x >= pos.x + size.x:
				dist_x = x - (pos.x + size.x - 1)
			var dist_y := 0
			if y < pos.y:
				dist_y = pos.y - y
			elif y >= pos.y + size.y:
				dist_y = y - (pos.y + size.y - 1)
			var dist := dist_x + dist_y
			if dist <= MIN_CLEAR:
				building_cells.append(Vector2i(x, y))
			elif dist <= MIN_CLEAR + JITTER:
				var chance := 1.0 - float(dist - MIN_CLEAR) / float(JITTER + 1)
				if patch_rng.randf() < chance:
					building_cells.append(Vector2i(x, y))

	var gterrain: String = sprite_def.get("ground", "dirt")
	if TERRAINS.has(gterrain):
		road.set_cells_terrain_connect(building_cells, TERRAIN_SET_ID, TERRAINS[gterrain])

	# Clear foliage under the building
	for cell in building_cells:
		if foliage.get_cell_source_id(cell) != -1:
			foliage.set_cell(cell, -1)

	# Spawn the unified building scene (exterior + interior in one), picking a
	# building_id variant discovered for this Structure.StructureType.
	_spawn_building_instance(pos, building_type, patch_rng)

# Picks a building_id variant registered for `building_type` (deterministically
# via `variant_rng`, seeded from position by the caller) and instantiates
# BUILDING_SCENE, positioning it to align with the ground/structure layers.
func _spawn_building_instance(pos: Vector2i, building_type: int, variant_rng: RandomNumberGenerator) -> void:
	var variants: Array = building_ids_by_type.get(building_type, [])
	if variants.is_empty():
		push_warning("No building scene variant found for building type %d" % building_type)
		return
	var building_id: String = variants[variant_rng.randi() % variants.size()]

	var instance := BUILDING_SCENE.instantiate()
	instance.building_id = building_id
	instance.name = "building_%s_%d" % [building_id, building_instances.size()]
	instance.position = structures_exterior.map_to_local(pos)
	structures.add_child(instance)
	# Newly added nodes have no `owner` by default, so they won't appear in the
	# editor's Scene panel (or get saved with the scene) even though they
	# render correctly. Setting owner to the edited scene root fixes this when
	# running as a @tool script; at runtime we fall back to this node's own
	# owner (which is null unless this generator is itself part of a larger
	# scene, in which case setting owner is harmless).
	var scene_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root:
		instance.owner = scene_root
		_set_owner_recursive(instance, scene_root)
	building_instances.append(instance)

# Recursively sets `owner` on every descendant of `node` so procedurally
# instantiated scenes appear in the editor's Scene panel and are persisted
# when the containing scene is saved.
func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)

func generate_roads_between_buildings(placed_buildings: Array, _settlement_rng: RandomNumberGenerator) -> void:
	# Simple implementation - just connect buildings with paths
	for i in range(placed_buildings.size()):
		var building_a = placed_buildings[i]
		for j in range(i + 1, placed_buildings.size()):
			var building_b = placed_buildings[j]
			
			# Skip if buildings are too far apart
			var distance = (building_a["pos"] - building_b["pos"]).length()
			if distance > 20: # Maximum road distance
				continue
			
			# Generate simple road between buildings
			generate_road_between_buildings(building_a, building_b)

func generate_road_between_buildings(building_a: Dictionary, building_b: Dictionary) -> void:
	var start = get_door_position_settlement(building_a)
	var end = get_door_position_settlement(building_b)
	
	# Seeded RNG for deterministic variation unique to this road segment
	var road_rng := RandomNumberGenerator.new()
	road_rng.seed = int(start.x * 73856093) ^ int(start.y * 19349663) ^ int(end.x * 2654435761) ^ int(end.y * 805459861)
	
	var path = get_varied_path(start, end, road_rng)
	
	# Get appropriate road terrain type from the map config
	var surface: String = _get_settlement_terrain()["paths"]
	
	# Collect road cells, varying width per cell for an organic look
	var road_cells = []
	for pos in path:
		# Width is mostly 1 tile each side, occasionally 2
		var half_w: int = 1 if road_rng.randf() > 0.25 else 2
		for dx in range(-half_w, half_w + 1):
			for dy in range(-half_w, half_w + 1):
				var road_pos = pos + Vector2i(dx, dy)
				if road_pos.x >= 0 and road_pos.x < WIDTH and road_pos.y >= 0 and road_pos.y < HEIGHT:
					road_cells.append(road_pos)
	
	# Apply terrain change using terrain sets for proper transitions
	if road_cells.size() > 0:
		road.set_cells_terrain_connect(road_cells, TERRAIN_SET_ID, TERRAINS[surface])

func get_door_position_settlement(building: Dictionary) -> Vector2i:
	# Returns the center of the south wall of the building as the door position
	return Vector2i(
		building["pos"].x + (building["size"].x >> 1),
		building["pos"].y + building["size"].y - 1
	)

func get_path_between_settlements(start: Vector2i, end: Vector2i) -> Array:
	# Simple Manhattan line-drawing path
	var path = []
	var current = start
	
	while current != end:
		path.append(current)
		var diff = end - current
		if abs(diff.x) > abs(diff.y):
			current.x += sign(diff.x)
		else:
			current.y += sign(diff.y)
			
	path.append(end)
	return path

# Like get_path_between_settlements but adds winding, irregular drift for a
# more organic, hand-laid road feel.  The road occasionally enters a "wander"
# mode where it drifts perpendicular to the goal for 1–5 steps before
# correcting, producing visible curves and bends.
func get_varied_path(start: Vector2i, end: Vector2i, path_rng: RandomNumberGenerator) -> Array:
	var path: Array = []
	var current := start
	var wander_steps := 0   # steps remaining in current sideways drift
	var wander_dir := 1     # perpendicular drift direction: +1 or -1

	# Safety cap: Manhattan distance × 4 so a very wandery road can't loop forever
	var max_steps = (abs(end.x - start.x) + abs(end.y - start.y)) * 4 + 10

	while current != end and path.size() < max_steps:
		path.append(current)
		var diff := end - current
		var dominant_x = abs(diff.x) >= abs(diff.y)

		# Occasionally start a new perpendicular wander burst
		if wander_steps <= 0 and path_rng.randf() < 0.25:
			wander_steps = path_rng.randi_range(2, 5)
			wander_dir = 1 if path_rng.randf() > 0.5 else -1

		if wander_steps > 0:
			# Move sideways relative to the dominant travel axis
			if dominant_x:
				# Travelling mostly horizontally → wander in Y
				var ny := current.y + wander_dir
				if ny >= 0 and ny < HEIGHT:
					current.y = ny
					wander_steps -= 1
				else:
					wander_steps = 0  # hit the map edge, abort wander
					current.x += sign(diff.x)
			else:
				# Travelling mostly vertically → wander in X
				var nx := current.x + wander_dir
				if nx >= 0 and nx < WIDTH:
					current.x = nx
					wander_steps -= 1
				else:
					wander_steps = 0
					current.y += sign(diff.y)
		else:
			# Normal progress toward the goal with a small jitter chance
			if dominant_x:
				if abs(diff.y) > 0 and path_rng.randf() < 0.1:
					current.y += sign(diff.y)
				else:
					current.x += sign(diff.x)
			else:
				if abs(diff.x) > 0 and path_rng.randf() < 0.1:
					current.x += sign(diff.x)
				else:
					current.y += sign(diff.y)

	path.append(end)
	return path

# ═══════════════════════════════════════════════════════════════════════
#  MAP-CONFIG DRIVEN HELPERS
# ═══════════════════════════════════════════════════════════════════════

## Return the settlement terrain palette (primary / secondary / paths)
## based on the current map_template.building_density.
func _get_settlement_terrain() -> Dictionary:
	var density: int = int(map_template.building_density)
	if SETTLEMENT_TERRAIN_BY_DENSITY.has(density):
		return SETTLEMENT_TERRAIN_BY_DENSITY[density]
	return SETTLEMENT_TERRAIN_BY_DENSITY[MapConfig.BuildingDensity.SMALL_VILLAGE]

## Draw road segments from each active edge midpoint to the map centre.
## Reads road_exits and road_terrain from map_template (MapConfig).
## Because the exit bitmask is assigned symmetrically by the world generator,
## a road that leaves this tile to the east will always enter the eastern
## neighbour from the west.
func generate_edge_roads() -> void:
	var exits: int = map_template.road_exits
	if exits == 0:
		return

	var center := Vector2i(WIDTH >> 1, HEIGHT >> 1)
	var road_half := ROAD_WIDTH >> 1

	# Collect edge entry points for every active exit direction
	var endpoints: Array[Vector2i] = []
	if exits & MapConfig.RoadExit.NORTH:
		endpoints.append(Vector2i(center.x, 0))
	if exits & MapConfig.RoadExit.SOUTH:
		endpoints.append(Vector2i(center.x, HEIGHT - 1))
	if exits & MapConfig.RoadExit.EAST:
		endpoints.append(Vector2i(WIDTH - 1, center.y))
	if exits & MapConfig.RoadExit.WEST:
		endpoints.append(Vector2i(0, center.y))

	if endpoints.is_empty():
		return

	# Choose road surface — fallback to "dirt" if the key is unknown
	var surface: String = map_template.road_terrain
	if not TERRAINS.has(surface):
		surface = "dirt"
	var road_terrain_id: int = TERRAINS[surface]

	# Seeded RNG for deterministic edge-road variation
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = int(map_template.SEED) ^ 0xDEADBEEF

	# Draw each road segment from the edge toward the centre
	var road_cells: Array[Vector2i] = []
	for ep: Vector2i in endpoints:
		var path: Array = get_varied_path(ep, center, edge_rng)
		for cell: Vector2i in path:
			# Vary width: mostly road_half, occasionally one wider
			var hw: int = road_half if edge_rng.randf() > 0.2 else road_half + 1
			for dx in range(-hw, hw + 1):
				for dy in range(-hw, hw + 1):
					var rp := cell + Vector2i(dx, dy)
					if rp.x >= 0 and rp.x < WIDTH and rp.y >= 0 and rp.y < HEIGHT:
						road_cells.append(rp)

	if road_cells.is_empty():
		return

	road.set_cells_terrain_connect(road_cells, TERRAIN_SET_ID, road_terrain_id, false)

## Process MapConfig.misc_features to place hamlets, farms, camps, etc.
## This replaces the old random 30% hamlet-chance logic with data-driven features.
func _generate_misc_features(local_rng: RandomNumberGenerator) -> void:
	for feature in map_template.misc_features:
		match feature:
			MapConfig.MiscFeatures.HAMLET:
				generate_hamlet("village", local_rng)
			MapConfig.MiscFeatures.FARM:
				generate_hamlet("farm", local_rng)
			MapConfig.MiscFeatures.DUNGEON_ENTRANCE:
				# TODO: generate dungeon entrance
				pass
			MapConfig.MiscFeatures.CAMP:
				# TODO: generate camp
				pass
			MapConfig.MiscFeatures.RUIN:
				# TODO: generate ruin
				pass
			MapConfig.MiscFeatures.SHRINE_SITE:
				# TODO: generate shrine site
				pass
			MapConfig.MiscFeatures.HIDDEN_SITE:
				# TODO: generate hidden site
				pass
