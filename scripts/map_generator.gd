@tool

# ==========
# Canonical map generator for local areas and settlements (dungeons/special
# locations to follow). Serves both authoring and runtime:
#  - In-editor: with generate_on_ready enabled the scene regenerates on open;
#    hand-edit the result and save it as a static scene.
#  - Runtime settlements: scenes using this script + a MapConfig generate on
#    load via setup_and_generate(). Baked static scenes set
#    generate_on_ready = false and keep their painted tiles.
#  - Runtime wilderness/local maps: callers set generate_on_ready = false and
#    call generate_local_map(metadata).
# ==========


extends Node2D
class_name MapGenerator

# ── Tileset backend ────────────────────────────────────────────────────────
# The roguelike sheet (resources/the_roguelike.tres) drives generation through
# resources/tileset_catalog.gd + resources/roguelike_tileset_build.gd.
const RoguelikeCatalog := preload("res://resources/roguelike_tileset_build.gd")
const Layout := preload("res://resources/tileset_catalog.gd")

# ── TileMapLayer nodes ──────────────────────────────────────────────────────
@onready var ground: TileMapLayer = $base_terrain
@onready var road: TileMapLayer = $road
@onready var terrain_features: TileMapLayer = $terrain_features
@onready var structures_exterior: TileMapLayer = $structures_exterior
@onready var structures_interior: TileMapLayer = $structures_interior
@onready var foliage: TileMapLayer = $foliage
@onready var decor_exterior: TileMapLayer = $decor_exterior
@onready var decor_interior: TileMapLayer = $decor_interior

# Mirror of OverworldGenerator.Tile for reference
enum OverworldTile {WATER, GRASS, MOUNTAIN}
enum GroundTile {GRASS, STONE, DIRT, WATER}

# Map our enum types to terrain sets
const GROUND_TERRAIN_MAP = {
	GroundTile.STONE: "stone",
	GroundTile.GRASS: "grass",
	GroundTile.DIRT: "dirt",
	GroundTile.WATER: "water"
}

# Surface laid on base_terrain beneath any surface that cannot go there itself
# (see _paint_surface). Must be one of the `ground` band surfaces.
const BASE_FILL_SURFACE := "grass"

# The only surface the road layer ever draws (see _paint_surface).
const ROAD_SURFACE := GROUND_TERRAIN_MAP[GroundTile.STONE]

# Terrain cells for batch processing
var terrain_cells = {
	"stone": [],
	"grass": [],
	"dirt": [],
	"water": []
}

# ── Building footprints (roguelike sheet) ───────────────────────────────────
# The roguelike sheet has no premade local-map building sprites — its
# whole-building glyphs are world-map icons (local_gen = false in the band
# table) — so buildings are drawn from wall and door tiles and are sized like
# rooms rather than city blocks.
#
# `ground` is the yard the building stands in and must be a surface name (see
# SURFACE_BANDS); `floor` is what is laid inside it and must be a
# Layout.FLOOR_TILES material. An entry that names no floor gets the default.
const BUILDING_SPRITES := {
	Structure.StructureType.HOUSE:  {"size": Vector2i(5, 5),   "ground": "dirt", "floor": "dirt", "spacing": 2},
	Structure.StructureType.SHOP:   {"size": Vector2i(6, 5),   "ground": "dirt", "floor": "stone_floor", "spacing": 2},
	# Packed earth under rushes, which is what a village tavern actually had, and
	# it tells a tavern apart from the house next door at a glance.
	Structure.StructureType.TAVERN: {"size": Vector2i(8, 6),   "ground": "dirt", "floor": "dark_wood", "spacing": 3},
	Structure.StructureType.MANOR:  {"size": Vector2i(10, 8),  "ground": "dirt", "floor": "stone_floor", "spacing": 3},
}

func _building_def(building_type: int):
	return BUILDING_SPRITES.get(building_type)

const WIDTH = 80
const HEIGHT = 80

# Default terrain type per settlement density tier.
# Replaces the old MapType-keyed SETTLEMENT_TERRAIN.
const SETTLEMENT_TERRAIN_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {
		"primary": "grass", "secondary": "dirt", "paths": ROAD_SURFACE
	},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		"primary": "grass", "secondary": "grass", "paths": ROAD_SURFACE
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		"primary": "grass", "secondary": "dirt", "paths": ROAD_SURFACE
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": ROAD_SURFACE
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		"primary": "grass", "secondary": "dirt", "paths": ROAD_SURFACE
	},
	MapConfig.BuildingDensity.CITY: {
		"primary": "grass", "secondary": "dirt", "paths": ROAD_SURFACE
	},
}

# How many of each building type to place per BuildingDensity tier.
const BUILDING_COUNTS_BY_DENSITY = {
	MapConfig.BuildingDensity.NONE: {},
	MapConfig.BuildingDensity.SMALL_VILLAGE: {
		Structure.StructureType.HOUSE: 4,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.LARGE_VILLAGE: {
		Structure.StructureType.HOUSE: 8,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 1,
		Structure.StructureType.CHURCH: 1,
		Structure.StructureType.BLACKSMITH: 1,
		Structure.StructureType.MANOR: 0,
	},
	MapConfig.BuildingDensity.SMALL_TOWN: {
		Structure.StructureType.HOUSE: 10,
		Structure.StructureType.TAVERN: 1,
		Structure.StructureType.SHOP: 2,
		Structure.StructureType.MANOR: 1,
		Structure.StructureType.CHURCH: 1,
		Structure.StructureType.BLACKSMITH: 1,				
	},
	MapConfig.BuildingDensity.LARGE_TOWN: {
		Structure.StructureType.HOUSE: 16,
		Structure.StructureType.TAVERN: 2,
		Structure.StructureType.SHOP: 3,
		Structure.StructureType.MANOR: 1,
		Structure.StructureType.CHURCH: 1,
		Structure.StructureType.BLACKSMITH: 1,		
	},
	MapConfig.BuildingDensity.CITY: {
		Structure.StructureType.HOUSE: 24,
		Structure.StructureType.TAVERN: 3,
		Structure.StructureType.SHOP: 4,
		Structure.StructureType.MANOR: 2,
		Structure.StructureType.CHURCH: 2,
		Structure.StructureType.BARRACKS: 1,
		Structure.StructureType.BLACKSMITH: 2,
	},
}

# How loosely a settlement sits inside its own footprint, per density tier.
#
# Buildings used to be dropped anywhere in the full 80x80 map, so a five-house
# village came out as five homesteads a screen apart — the map was the search
# area no matter how little there was to put in it. Instead the buildable core
# is sized to what the buildings actually need: the radius of a disc that would
# just hold their combined footprint, multiplied by the value below to buy room
# for streets, yards and the gaps that make a place look lived-in.
#
# 1.0 would pack every building wall-to-wall. Villages take the smaller numbers
# because a handful of houses has to hug to read as a hamlet at all; a city has
# enough buildings to look dense at a looser ratio, and still ends up filling
# most of the map.
const SETTLEMENT_SPREAD := {
	MapConfig.BuildingDensity.NONE: 1.65,
	MapConfig.BuildingDensity.SMALL_VILLAGE: 1.65,
	MapConfig.BuildingDensity.LARGE_VILLAGE: 1.70,
	MapConfig.BuildingDensity.SMALL_TOWN: 1.70,
	MapConfig.BuildingDensity.LARGE_TOWN: 1.45,
	MapConfig.BuildingDensity.CITY: 1.50,
}

# Valid positions weighed up per building before one is chosen. One candidate is
# "take the first random spot that fits" — the old behaviour, and the other half
# of why settlements sprawled. Considering a couple of dozen lets the cohesion
# score below actually pull the next building toward its neighbours.
const SETTLEMENT_PLACEMENT_CANDIDATES := 24

# Distance (in tiles, centre to centre) at which a building stops reading as
# part of the same cluster as its nearest neighbour. Scores fall off linearly to
# zero here, so anything further away is simply "detached" with no preference
# between one gap and a bigger one.
const SETTLEMENT_NEIGHBOUR_SPAN := 18.0

# Foliage density multipliers per MapConfig.TreeDensity enum.
# Values are lower than before because each foliage sprite now occupies many
# tiles (e.g. a tree is 6×8).  The used_cells check prevents overlapping.
const TREE_DENSITY_VALUES = {
	MapConfig.TreeDensity.NONE: 0.0,
	MapConfig.TreeDensity.SPARSE: 0.15,
	MapConfig.TreeDensity.FOREST: 0.5,
}

# Tiles of "worn ground" influence around each building footprint — used to
# skew settlement ground toward the secondary (trampled) terrain near walls.
const WEAR_RADIUS := 6

# Largest gap add_foliage() will enforce between two placements of the same
# atlas tile. The gap actually used is this or the number of distinct tiles in
# the pool, whichever is smaller — see add_foliage() for why.
const FOLIAGE_SAME_TILE_MIN_DIST := 8

# How thickly the coarse ground cut (band row 10) is scattered over each base
# surface, as a fraction of that surface's cells. Grass hides its rubble under
# turf, bare dirt shows more of it, and stony ground is mostly the coarse stuff
# already — so the frequency is a property of the terrain, not one global rate.
# Scaled by MapConfig.ground_detail_density and clumped by cluster noise.
const GROUND_DETAIL_DENSITY := {
	"grass": 0.08,
	"dirt": 0.20,
	"stone": 0.30,
	"water": 0.0,
}

# Per-biome multiplier on the rates above: bare, dead and eroded environments
# break up more than lush or snow-covered ones. Biomes absent here scatter at
# the unmodified rate.
const GROUND_DETAIL_BIOME_SCALE := {
	"desert": 1.4,
	"dead": 1.4,
	"volcanic": 1.3,
	"swamp": 1.2,
	"cursed": 1.2,
	"savannah": 1.1,
	"boreal": 0.8,
	"jungle": 0.7,
	"arctic": 0.5,
}

# Road generation parameters
const ROAD_WIDTH = 2

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
@export_tool_button("Generate") var btn_generate = func(): _editor_generate()
@export_tool_button("Clear") var btn_clear = func(): _editor_clear()
@export_tool_button("Bake To Scene") var btn_bake = func(): _editor_bake()
@export_group("")

# ════════════════════════════════════════════════════════════════════════
#  EDITOR TOOLS
#
#  Generate regenerates in place, replacing the old "Scene > Reload Saved
#  Scene" ritual. Bake To Scene saves the current generated + hand-edited map
#  as a standalone static scene at bake_dir/<map_name>.tscn; the baked scene
#  keeps this script with generate_on_ready = false, so it loads its painted
#  tiles verbatim.
# ════════════════════════════════════════════════════════════════════════

func _editor_generate() -> void:
	if not Engine.is_editor_hint():
		return
	if noise == null:
		noise = FastNoiseLite.new()
	clear_all_layers()
	_rebuild_tile_catalog()
	setup_and_generate()

func _editor_clear() -> void:
	if not Engine.is_editor_hint():
		return
	clear_all_layers()

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

# Cached map cell list used by shuffled scatter passes.
var _all_cells: Array[Vector2i] = []

# Runtime tile catalog built from tileset custom data (category / type / tag_1 / tag_2).
# Structure: tile_catalog[category][type] = Array[{source_id, atlas, size, tag_1, tag_2}]
var tile_catalog: Dictionary = {}

## Cells where a prop tagged as a container (see tileset_catalog.gd) was painted.
## Vector2i cell → { role, loot_table, layer, atlas, open_atlas, locked_chance }.
## The tile itself is ordinary scenery — this is only the note that something
## lootable belongs there, which ContainerSpawner reads after generation.
var container_cells: Dictionary = {}

## Cells covered by a building footprint and the cleared yard around it, so the
## scatter passes can leave them alone. Buildings used to be masked off simply
## by having their yard painted on the road layer; the yard is ordinary ground
## now, so the mask is kept explicitly.
var building_clear_cells: Dictionary = {}

## Buildings standing on the current map, as [{type, pos, size}, …]. Filled by
## every route that places them, so NPCSpawner need not know which one ran.
var map_buildings: Array = []

# Normalized copy of the TileMetadata dict passed to generate_local_map()
# (runtime wilderness path); empty for settlement/editor generation.
var current_metadata: Dictionary = {}

## Biome the current map draws its art from, as the lowercase name the band
## table in tileset_catalog.gd uses ("temperate", "swamp", "arctic", …).
##
## This is a view onto MapConfig.biome rather than a copy of it — the config is
## the one setting, so there is no second value to keep in sync. Empty only when
## there is no config at all, which disables biome filtering.
var map_biome: String:
	get:
		return biome_name(map_template.biome) if map_template else ""
	set(value):
		if map_template:
			map_template.biome = biome_from_name(value)


# ════════════════════════════════════════════════════════════════════════
#  BIOME NAMES
#
#  Translates between MapConfig.Biome and the lowercase names the band table
#  in tileset_catalog.gd uses for its biome columns. Derived from the enum
#  member names, so adding a biome to MapConfig picks up its column
#  automatically as long as the two spell it the same way; an unknown name
#  falls back to TEMPERATE.
# ════════════════════════════════════════════════════════════════════════

static func biome_name(biome: int) -> String:
	var names := MapConfig.Biome.keys()
	if biome < 0 or biome >= names.size():
		return ""
	return String(names[biome]).to_lower()


static func biome_from_name(biome: String) -> MapConfig.Biome:
	var index: int = MapConfig.Biome.keys().find(biome.to_upper())
	if index < 0:
		return MapConfig.Biome.TEMPERATE
	return index as MapConfig.Biome

func clear_all_layers() -> void:
	ground.clear()
	road.clear()
	foliage.clear()
	terrain_features.clear()
	structures_exterior.clear()
	structures_interior.clear()
	decor_exterior.clear()
	decor_interior.clear()
	container_cells.clear()
	building_clear_cells.clear()
	map_buildings.clear()

func _ready() -> void:
	# Validate required TileMapLayer nodes
	for layer_node in [ground, road, terrain_features, structures_exterior, structures_interior, decor_exterior, decor_interior]:
		if not layer_node:
			push_error("Missing TileMapLayer node in MapGenerator scene '%s'!" % name)
			return
	_ensure_all_cells()
	noise = FastNoiseLite.new()
	_rebuild_tile_catalog()
	if generate_on_ready:
		clear_all_layers()
		setup_and_generate()

func _ensure_all_cells() -> void:
	if not _all_cells.is_empty():
		return
	for y in HEIGHT:
		for x in WIDTH:
			_all_cells.append(Vector2i(x, y))

# ════════════════════════════════════════════════════════════════════════
#  TILE CATALOG
#
#  tile_catalog[category][type] = Array[entry] is built from the roguelike
#  master sheet via resources/tileset_catalog.gd.
# ════════════════════════════════════════════════════════════════════════

func _rebuild_tile_catalog() -> void:
	var ts := ground.tile_set
	if ts == null:
		tile_catalog = {}
		push_error("No TileSet on ground layer – tile catalog empty")
		return
	tile_catalog = RoguelikeCatalog.build(ts)


func _catalog_pool(category: String, tile_type: String) -> Array:
	var pool: Array = tile_catalog.get(category, {}).get(tile_type, [])
	return RoguelikeCatalog.of_biome(RoguelikeCatalog.of_theme(pool), map_biome)


## The catalog entry for a named Layout.FLOOR_TILES material, or {} when the
## sheet has no such tile and the caller should fall back.
##
## Routed through the band table rather than a fixed pool, because the floor
## materials do not share one: `dirt` is base ground, the boards and flagstones
## are the detail row above it. Reads the raw catalog on purpose — a floor is a
## specific material the building asked for, and the theme/biome filter in
## _catalog_pool would throw it away for being the wrong climate, which is how
## the boards (borrowed from the tropical block) would vanish.
func _floor_entry(floor_material: String) -> Dictionary:
	var atlas: Vector2i = Layout.floor_atlas(floor_material)
	var band: Dictionary = Layout.category_band_for_row(atlas.y)
	var route: Dictionary = Layout.category_route(band.get("category", ""))
	if route.is_empty():
		return {}
	return RoguelikeCatalog.entry_at(
		tile_catalog.get(route["category"], {}).get(route["type"], []), atlas)


func _catalog_types(category: String) -> Dictionary:
	var out: Dictionary = {}
	for tile_type in tile_catalog.get(category, {}):
		out[tile_type] = _catalog_pool(category, tile_type)
	return out


# ═══════════════════════════════════════════════════════════════════════
#  SURFACE PAINTING
#
#  The one place that knows how a named surface ("grass", "dirt", "stone",
#  "water", "wheat_field") reaches the tilemap. The roguelike sheet has no
#  terrain sets, so cells are painted individually from the matching band pool,
#  varied by a position hash mixed with the map seed — the same seed always
#  repaints identically, without threading an RNG through every caller.
#
#  base_terrain is the opaque, full-coverage fill under everything else and
#  carries nothing but the `ground` band. Every other surface is drawn from the
#  transparent cut of the sheet, so painting it there would leave holes in the
#  fill — and get_cell_ground_type() reads the base band back to decide what a
#  cell is. A non-ground surface aimed at base_terrain is therefore split: the
#  ground fill goes down first and the surface is laid over it on
#  terrain_features, which draws directly above base_terrain.
#
#  The road layer is the mirror of that rule: it draws roads and nothing else.
#  Callers used to name a path surface ("dirt", "stone"), but "dirt" resolves to
#  the same `ground` band base_terrain is painted from, so every village path
#  came out as a copy of the terrain underneath it. Whatever a caller asks for,
#  the road layer paints ROAD_SURFACE.
# ═══════════════════════════════════════════════════════════════════════

func _paint_surface(layer: TileMapLayer, cells: Array, surface: String) -> void:
	if layer == null or cells.is_empty():
		return

	var target := layer
	if layer == road:
		surface = ROAD_SURFACE
	elif layer == ground and not _is_base_surface(surface):
		_fill_cells(ground, cells, BASE_FILL_SURFACE)
		target = terrain_features
	_fill_cells(target, cells, surface)


func _fill_cells(layer: TileMapLayer, cells: Array, surface: String) -> void:
	var pool := _surface_pool(surface)
	if pool.is_empty():
		push_warning("MapGenerator: no '%s' tiles in the catalog — skipping %d cells"
			% [surface, cells.size()])
		return
	for cell: Vector2i in cells:
		var pick: Dictionary = pool[_cell_hash(cell) % pool.size()]
		layer.set_cell(cell, pick["source_id"], pick["atlas"])


func _is_base_surface(surface: String) -> bool:
	var route: Dictionary = Layout.surface_route(surface)
	return route["category"] == "surface" and route["type"] == "ground"


func _surface_pool(surface: String) -> Array:
	var route: Dictionary = Layout.surface_route(surface)
	return _catalog_pool(route["category"], route["type"])


func _cell_hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ current_map_seed)


# ════════════════════════════════════════════════════════════════════════
#  GENERATION ENTRY POINTS
#
#  setup_and_generate() is the authoring / settlement route; generate_local_map()
#  is the runtime wilderness route, taking a TileMetadata (or Dictionary) from
#  the world generator and folding it into map_template so every helper below
#  reads from one authoritative source — including the persisted seed, so
#  revisits reproduce the same map.
#
#  Settlement layout priority is: a layout MainGameState stored on a previous
#  visit > a dataset authored into the MapConfig > fresh generation. Generated
#  layouts are written back to MainGameState (which the save system already
#  serializes), keyed by map_template.overworld_tile, so revisits and save/load
#  rebuild the identical settlement via build_settlement_from_dataset(). The
#  autoload isn't registered in the editor or headless script contexts, so
#  _main_game_state() resolves it by path rather than as a compile-time global.
# ════════════════════════════════════════════════════════════════════════

func setup_and_generate(
		map_type: int = -1,
		overworld_tile_type: int = OverworldTile.GRASS,
		world_position: Vector2i = Vector2i.ZERO,
		seed_value: int = 0
	) -> void:
	if map_template == null:
		push_error("MapGenerator: map_template is required")
		return
	if map_type == -1:
		map_type = int(map_template.map_type)
	if seed_value == 0:
		seed_value = int(map_template.SEED)
	overworld_position = world_position
	base_terrain_type = overworld_tile_type
	var local_rng = RandomNumberGenerator.new()
	if seed_value == 0:
		local_rng.seed = randi()
	else:
		local_rng.seed = seed_value

	match map_type:
		MapConfig.MapType.NON_SETTLEMENT:
			generate_local_area(overworld_tile_type, world_position, local_rng)
		MapConfig.MapType.SETTLEMENT, MapConfig.MapType.CASTLE_INTERIOR:
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

func _main_game_state() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("MainGameState")

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

func _paint_settlement_ground(building_rects: Array[Rect2i]) -> void:
	var settlement_terrain := _get_settlement_terrain()
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
	for y in HEIGHT:
		for x in WIDTH:
			var pos := Vector2i(x, y)
			var patch_val := (patch_noise.get_noise_2d(x, y) + 1.0) / 2.0
			patch_val += float(wear.get(pos, 0.0)) * 0.35
			var terrain_type: String = settlement_terrain["secondary"] if patch_val > 0.62 else settlement_terrain["primary"]
			terrain_cells[terrain_type].append(pos)
	for terrain in terrain_cells:
		_paint_surface(ground, terrain_cells[terrain], terrain)


## Ground is expected to be painted already — buildings draw their own yards.
func _place_buildings(buildings: Array) -> void:
	for entry in buildings:
		place_building_settlement(entry["pos"], entry["size"], entry["type"])
	map_buildings = buildings

func _buildings_from_structures(structures: Array[Structure]) -> Array:
	var out: Array = []
	for b: Structure in structures:
		if b == null:
			continue
		var sprite_def = _building_def(int(b.TYPE))
		if not sprite_def:
			continue
		out.append({"type": int(b.TYPE), "pos": b.POSITION, "size": sprite_def["size"]})
	return out


func build_settlement_from_dataset() -> void:
	clear_all_layers()

	current_map_seed = int(map_template.SEED)
	# Terrain variant picking consumes the global RNG (see generate_local_area).
	seed(current_map_seed)
	_configure_ground_noise(current_map_seed)

	var buildings := _buildings_from_structures(map_template.important_buildings)
	buildings.append_array(_buildings_from_structures(map_template.buildings))

	var building_rects: Array[Rect2i] = []
	for entry in buildings:
		building_rects.append(Rect2i(entry["pos"], entry["size"]))
	_paint_settlement_ground(building_rects)
	_place_buildings(buildings)

	generate_roads_between_buildings(buildings, RandomNumberGenerator.new())
	generate_edge_roads()
	var feature_rng := RandomNumberGenerator.new()
	feature_rng.seed = current_map_seed ^ 0x7EA7F00D
	add_terrain_features(feature_rng)
	add_foliage()
	add_decor_exterior(buildings)
	add_decor_interior(buildings)

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
	# map_type, set just above, picks settlement vs wilderness generation.
	setup_and_generate(-1, terrain, world_pos, map_seed)

func _merged_overworld_metadata() -> Dictionary:
	var merged: Dictionary = {}
	var from_nested = current_metadata.get("overworld", {})
	if from_nested is Dictionary:
		merged = (from_nested as Dictionary).duplicate(true)
	# Backward compatibility: legacy callers may only pass top-level keys.
	if current_metadata.has("has_settlement") and not merged.has("has_settlement"):
		merged["has_settlement"] = current_metadata["has_settlement"]
	if current_metadata.has("is_forest") and not merged.has("is_forest"):
		merged["is_forest"] = current_metadata["is_forest"]
	if current_metadata.has("terrain") and not merged.has("terrain"):
		merged["terrain"] = current_metadata["terrain"]
	if current_metadata.has("biome") and not merged.has("biome"):
		merged["biome"] = current_metadata["biome"]
	return merged

func _apply_metadata_to_config() -> void:
	# Seed: generate_edge_roads and other helpers derive sub-seeds from
	# map_template.SEED, so it must match the metadata seed for determinism.
	map_template.SEED = int(current_metadata.get("seed", 0))
	var overworld_data: Dictionary = _merged_overworld_metadata()

	var settlement_density := int(current_metadata.get(
		"settlement_density", overworld_data.get("settlement_density", -1)))
	if settlement_density >= 0:
		map_template.map_type = MapConfig.MapType.SETTLEMENT
		map_template.building_density = settlement_density as MapConfig.BuildingDensity
	else:
		map_template.map_type = MapConfig.MapType.NON_SETTLEMENT
		map_template.building_density = MapConfig.BuildingDensity.NONE

	map_template.overworld_tile = current_metadata.get("coords", Vector2i.ZERO)
	map_template.buildings.clear()
	map_template.map_name = str(current_metadata.get("name", ""))
	map_biome = current_metadata.get("biome", "")

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

	# Optional overworld hint: forest tiles default to denser foliage when no
	# explicit profile was provided for this tile.
	var is_forest_tile: bool = bool(overworld_data.get("is_forest", false))
	if is_forest_tile and not foliage_profile.has("tree_density"):
		map_template.tree_density = MapConfig.TreeDensity.FOREST
	if is_forest_tile and not foliage_profile.has("bush_density"):
		map_template.bush_density = maxf(map_template.bush_density, 0.08)

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
		_paint_surface(ground, terrain_cells[terrain], terrain)

	var feature_buildings := _generate_misc_features(local_rng)
	map_buildings = feature_buildings
	# The scatter passes below steer around roads, so footpaths between a hamlet's
	# buildings are what keeps its props from spreading evenly over the whole yard.
	generate_roads_between_buildings(feature_buildings, local_rng)
	generate_edge_roads()
	add_terrain_features(local_rng)
	add_foliage()
	add_decor_exterior(feature_buildings)
	add_decor_interior(feature_buildings)

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
	_configure_ground_noise(int(map_template.SEED))

	current_map_seed = map_template.SEED

	var occupied_space_grid = []
	for y in area_size.y:
		occupied_space_grid.append([])
		for x in area_size.x:
			occupied_space_grid[y].append(false)

	# Every position is chosen before anything is drawn, so the ground pass below
	# can wear the earth around the whole settlement at once.
	var chosen: Array = []
	# Everything this settlement will put down, so the buildable core can be
	# sized before the first building is placed rather than growing to fit.
	var core := _settlement_core_rect(area_size, building_counts, _settlement_spread())

	for b: Structure in map_template.important_buildings:
		if b == null:
			continue
		var enum_type: int = int(b.TYPE)
		var sprite_def = _building_def(enum_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		var pos: Vector2i = b.POSITION
		if pos == Vector2i.ZERO:
			pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, enum_type, core, chosen)
			b.POSITION = pos
		if pos.x != -1:
			mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
			chosen.append({"type": enum_type, "pos": pos, "size": size})

	var building_order = [Structure.StructureType.MANOR, Structure.StructureType.TAVERN, Structure.StructureType.SHOP, Structure.StructureType.HOUSE]
	for building_type in building_order:
		var count: int = building_counts.get(building_type, 0)
		var sprite_def = _building_def(building_type)
		if not sprite_def:
			continue
		var size: Vector2i = sprite_def["size"]
		for _i in count:
			var pos = find_valid_building_position_settlement(area_size, size, occupied_space_grid, settlement_rng, building_type, core, chosen)
			if pos.x != -1:
				mark_occupied_settlement(occupied_space_grid, pos, size, sprite_def["spacing"])
				chosen.append({"type": building_type, "pos": pos, "size": size})
				var s := Structure.new()
				s.TYPE = building_type
				s.POSITION = pos
				s.INTERIOR_SIZE = size
				s.ZONES = []
				s.INTERIOR_FEATURES = []
				s.SCRIPTED_CONTENT = null
				map_template.buildings.append(s)

	var building_rects: Array[Rect2i] = []
	for entry in chosen:
		building_rects.append(Rect2i(entry["pos"], entry["size"]))
	_paint_settlement_ground(building_rects)
	_place_buildings(chosen)

	generate_roads_between_buildings(chosen, settlement_rng)
	generate_edge_roads()
	add_terrain_features(settlement_rng)
	add_foliage()
	add_decor_exterior(chosen)
	add_decor_interior(chosen)

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

# ════════════════════════════════════════════════════════════════════════
#  NOISE & SEEDING HELPERS
#
#  The shared ground noise uses fBm octaves to roughen terrain boundaries
#  (coastline-like edges instead of smooth blobs) and domain warp to break up
#  the round, axis-agnostic shapes single-frequency noise produces.
#
#  The scatter passes below layer several fields: a low-frequency forest mask
#  (high = forest core, low = open clearing), mid-frequency cluster masks that
#  gather one feature family into patches, and a wear grid falling from 1.0 at
#  building walls to 0 at WEAR_RADIUS tiles out (Chebyshev). _cluster_weight()
#  turns a cluster sample into a density weight in [0, 2] — near zero outside
#  the family's patches, up to 2x inside, averaging ~1 map-wide.
#
#  All of them derive from _foliage_derived_seed() so the fields line up (e.g.
#  flowers avoid the same forest cores trees fill), and cells are visited in a
#  deterministic Fisher-Yates order: a fixed top-left scan lets earlier cells
#  greedily claim multi-tile footprints, skewing every feature toward the
#  top-left. Array.shuffle() would use the global RNG and break seeding, hence
#  _shuffled_cells().
# ════════════════════════════════════════════════════════════════════════

func _configure_ground_noise(seed_value: int) -> void:
	noise.seed = seed_value
	noise.frequency = 1.0 / map_template.noise_scale
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = map_template.noise_scale

func _foliage_derived_seed() -> int:
	return int(current_map_seed) ^ (overworld_position.x * 73856093) ^ (overworld_position.y * 19349663) ^ int(base_terrain_type)

func _make_forest_noise(derived_seed: int) -> FastNoiseLite:
	var forest_noise := FastNoiseLite.new()
	forest_noise.seed = derived_seed ^ 0x1A2B3C4D
	forest_noise.frequency = 1.0 / (map_template.noise_scale * 4.0)
	return forest_noise

func _make_cluster_noise(seed_value: int) -> FastNoiseLite:
	var cluster_noise := FastNoiseLite.new()
	cluster_noise.seed = seed_value
	cluster_noise.frequency = 1.0 / (map_template.noise_scale * 2.5)
	return cluster_noise

func _cluster_weight(cluster_noise: FastNoiseLite, pos: Vector2i) -> float:
	var v := (cluster_noise.get_noise_2d(pos.x, pos.y) + 1.0) / 2.0
	return smoothstep(0.35, 0.65, v) * 2.0

func _shuffled_cells(shuffle_rng: RandomNumberGenerator) -> Array[Vector2i]:
	_ensure_all_cells()
	var cells: Array[Vector2i] = _all_cells.duplicate()
	for i in range(cells.size() - 1, 0, -1):
		var j := shuffle_rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells

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

# ════════════════════════════════════════════════════════════════════════
#  SCATTER PASSES
#
#  Foliage, exterior decor, ground detail and terrain features, in the order
#  they run. Each claims cells in a `used_cells` dict so multi-tile sprites
#  never overlap, and each skips roads, building footprints and anything a
#  previous pass already placed.
#
#  Ground detail is the coarse ground cut (band row 10) scattered over the base
#  terrain painted from row 9, at a rate per base surface (GROUND_DETAIL_
#  DENSITY) and biome, clumped by its own cluster noise. Keeping both rows in
#  one surface pool alternated them cell by cell in a visible grid, which is why
#  they are separate bands.
# ════════════════════════════════════════════════════════════════════════

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

	var foliage_rng := RandomNumberGenerator.new()
	foliage_rng.seed = derived_seed ^ 0x5A5A5A5A

	var tree_tiles: Array = _catalog_pool("foliage", "tree")
	var bush_tiles: Array = _catalog_pool("foliage", "bush")

	# Track which cells are already covered by a placed multi-tile sprite
	var used_cells: Dictionary = {}
	# Track origin positions per atlas tile to prevent identical sprites clustering.
	# Key: "sourceId_atlasX_atlasY"  Value: Array[Vector2i] of placed origins
	var placed_type_positions: Dictionary = {}

	# Minimum gap between two placements of the SAME atlas tile. Written for
	# tilesets that draw a dozen different trees, where 8 tiles is roughly one
	# sprite width and the rule only breaks up visible repeats.
	#
	# The roguelike sheet draws ONE tree per biome, so a flat 8-tile gap stops
	# being an anti-repeat rule and becomes a hard ceiling on the whole map:
	# one tree per 8x8 area per distinct tile, i.e. ~3% of cells with a two-tile
	# pool. Both SPARSE and FOREST ask for far more than that, so both saturated
	# at the same count and tree_density had no visible effect. Scaling the gap
	# to how many distinct tiles the pool actually offers leaves varied tilesets
	# exactly as they were and lets a one-per-biome pool pack as densely as the
	# density asks.
	var tree_spacing: int = mini(tree_tiles.size(), FOLIAGE_SAME_TILE_MIN_DIST)
	var bush_spacing: int = mini(bush_tiles.size(), FOLIAGE_SAME_TILE_MIN_DIST)

	# Visit cells in shuffled order — a fixed top-left scan lets earlier cells
	# greedily claim multi-tile footprints, skewing forests toward the top-left
	# of every eligible region.
	for pos: Vector2i in _shuffled_cells(foliage_rng):
		var x := pos.x
		var y := pos.y
		if used_cells.has(pos):
			continue

		# Building footprints and the cleared yard around them.
		if building_clear_cells.has(pos):
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

			var candidates: Array = []
			# Anti-repeat gap for whichever pool this cell ends up drawing from.
			var same_tile_gap: int = tree_spacing
			if detail_value < local_tree_density:
				candidates = tree_tiles
			elif detail_value < local_tree_density + local_bush_density:
				candidates = bush_tiles
				same_tile_gap = bush_spacing

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
					if same_tile_gap > 1 and placed_type_positions.has(type_key):
						for prev_pos: Vector2i in placed_type_positions[type_key]:
							if maxi(absi(pos.x - prev_pos.x), absi(pos.y - prev_pos.y)) < same_tile_gap:
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

func _allows_exterior_placement(entry: Dictionary) -> bool:
	var placement: String = entry.get("placement", "both")
	return placement == "both" or placement == "exterior"

func _allows_interior_placement(entry: Dictionary) -> bool:
	var placement: String = entry.get("placement", "both")
	return placement == "both" or placement == "interior"

## Every prop the catalog knows that may stand in the given context, as a flat
## pool ready for _pick_weighted().
func _prop_pool(interior: bool) -> Array:
	var decor_types: Dictionary = _catalog_types("decor_exterior")
	var pool: Array = []
	for tile_type in decor_types:
		for entry in decor_types[tile_type]:
			if interior:
				if _allows_interior_placement(entry):
					pool.append(entry)
			elif _allows_exterior_placement(entry):
				pool.append(entry)
	return pool

## Weighted pick from a prop pool. The weight rides on each catalog entry (see
## tileset_catalog.gd), so which props dominate a map is authored data rather
## than a rule here; entries without one fall back to an even chance.
func _pick_weighted(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for entry in pool:
		total += maxf(0.0, float(entry.get("weight", 1.0)))
	if total <= 0.0:
		return pool[rng.randi() % pool.size()]
	var roll := rng.randf() * total
	for entry in pool:
		roll -= maxf(0.0, float(entry.get("weight", 1.0)))
		if roll <= 0.0:
			return entry
	return pool[pool.size() - 1]

## Remember that `entry` was painted at `cell` if it stands in for a lootable
## container. Called right after the prop is set, so the note and the tile can
## never disagree about where the container is.
func _note_container(cell: Vector2i, entry: Dictionary, layer_name: String) -> void:
	var role: String = String(entry.get("container", ""))
	if role.is_empty():
		return
	var loot_table: String = String(entry.get("loot_table", ""))
	container_cells[cell] = {
		"role": role,
		# An untagged container falls back to a table named after its role, so a
		# new prop only needs `container` set to be lootable.
		"loot_table": loot_table if not loot_table.is_empty() else role,
		"layer": layer_name,
		"source_id": entry["source_id"],
		"atlas": entry["atlas"],
		"open_atlas": entry.get("open_atlas", entry["atlas"]),
		"locked_chance": float(entry.get("locked_chance", 0.0)),
	}

## The TileMapLayer a container record was painted on, or null. Lets a
## container repaint its own tile without holding a node reference that a
## regenerate would leave dangling.
func layer_named(layer_name: String) -> TileMapLayer:
	match layer_name:
		"decor_interior":
			return decor_interior
		"decor_exterior":
			return decor_exterior
		_:
			return null

func add_decor_exterior(placed_buildings: Array) -> void:
	var all_tiles: Array = _prop_pool(false)
	if all_tiles.is_empty():
		return

	# The roguelike catalog does not carry per-tile tags; use the same pool for
	# border and open placement bands.
	var wall_adjacent_tiles: Array = all_tiles
	var open_tiles: Array = all_tiles

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
				var entry: Dictionary = _pick_weighted(wall_adjacent_tiles, decor_rng)
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
					_note_container(cell, entry, "decor_exterior")
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
				var entry: Dictionary = _pick_weighted(open_tiles, decor_rng)
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
					_note_container(cell, entry, "decor_exterior")
					for edy in esize.y:
						for edx in esize.x:
							used_cells[cell + Vector2i(edx, edy)] = true

func add_decor_interior(placed_buildings: Array) -> void:
	var interior_tiles: Array = _prop_pool(true)
	if interior_tiles.is_empty():
		return

	var decor_rng := RandomNumberGenerator.new()
	decor_rng.seed = current_map_seed ^ 0xC0FFEE11
	var used_cells: Dictionary = {}

	for building in placed_buildings:
		var bpos: Vector2i = building["pos"]
		var bsize: Vector2i = building["size"]
		if bsize.x < 3 or bsize.y < 3:
			continue

		# One-tile-inside ring (hugging interior walls).
		var left := bpos.x + 1
		var right := bpos.x + bsize.x - 2
		var top := bpos.y + 1
		var bottom := bpos.y + bsize.y - 2

		var edge_cells: Array[Vector2i] = []
		for x in range(left, right + 1):
			edge_cells.append(Vector2i(x, top))
			if bottom != top:
				edge_cells.append(Vector2i(x, bottom))
		for y in range(top + 1, bottom):
			edge_cells.append(Vector2i(left, y))
			if right != left:
				edge_cells.append(Vector2i(right, y))

		for cell in edge_cells:
			if decor_rng.randf() > 0.22:
				continue
			if used_cells.has(cell):
				continue
			if structures_exterior.get_cell_source_id(cell) != -1:
				continue
			if decor_interior.get_cell_source_id(cell) != -1:
				continue

			var entry: Dictionary = _pick_weighted(interior_tiles, decor_rng)
			var esize: Vector2i = entry["size"]
			var fits := true
			for edy in esize.y:
				for edx in esize.x:
					var ec := cell + Vector2i(edx, edy)
					if ec.x < left or ec.x > right or ec.y < top or ec.y > bottom:
						fits = false
						break
					if used_cells.has(ec) or structures_exterior.get_cell_source_id(ec) != -1 or decor_interior.get_cell_source_id(ec) != -1:
						fits = false
						break
				if not fits:
					break
			if not fits:
				continue

			# Interior props live on their own dedicated layer.
			decor_interior.set_cell(cell, entry["source_id"], entry["atlas"])
			_note_container(cell, entry, "decor_interior")
			for edy in esize.y:
				for edx in esize.x:
					used_cells[cell + Vector2i(edx, edy)] = true

func _scatter_ground_detail(local_rng: RandomNumberGenerator) -> void:
	var pool: Array = _catalog_pool("terrain_features", "ground_detail")
	if pool.is_empty():
		return

	var biome_scale: float = GROUND_DETAIL_BIOME_SCALE.get(map_biome, 1.0)
	var config_scale: float = map_template.ground_detail_density if map_template else 1.0
	var mask := _make_cluster_noise(_foliage_derived_seed() ^ 0x6D07)

	for surface in terrain_cells:
		var rate: float = GROUND_DETAIL_DENSITY.get(surface, 0.0) * biome_scale * config_scale
		if rate <= 0.0:
			continue
		for pos: Vector2i in terrain_cells[surface]:
			# Roads, building footprints (painted on the road layer) and anything
			# already standing on the feature layer keep their own surface.
			if road.get_cell_source_id(pos) != -1:
				continue
			if structures_exterior.get_cell_source_id(pos) != -1:
				continue
			if terrain_features.get_cell_source_id(pos) != -1:
				continue
			if local_rng.randf() >= rate * _cluster_weight(mask, pos):
				continue
			var pick: Dictionary = pool[local_rng.randi() % pool.size()]
			terrain_features.set_cell(pos, pick["source_id"], pick["atlas"])


func add_terrain_features(local_rng: RandomNumberGenerator) -> void:
	_scatter_ground_detail(local_rng)

	# Roguelike routing exposes terrain feature pools as grass/rock/farm.
	var grass_tiles: Array = _catalog_pool("terrain_features", "grass")
	var rock_tiles: Array = _catalog_pool("terrain_features", "rock")
	var farm_tiles: Array = _catalog_pool("terrain_features", "farm")
	var plant_tiles: Array = _catalog_pool("foliage", "plant")

	var used_cells: Dictionary = {}

	# Per-family cluster masks keep each feature type in patchy clusters.
	var derived_seed := _foliage_derived_seed()
	var grass_mask := _make_cluster_noise(derived_seed ^ 0x5C2F)
	var plant_mask := _make_cluster_noise(derived_seed ^ 0x0F10)
	var rock_mask := _make_cluster_noise(derived_seed ^ 0x50CC)
	var farm_mask := _make_cluster_noise(derived_seed ^ 0x0DD1)

	# Shuffled visit order so multi-tile features don't systematically win
	# contested space toward the top-left (same fix as add_foliage).
	for pos: Vector2i in _shuffled_cells(local_rng):
		if used_cells.has(pos):
			continue

		if road.get_cell_source_id(pos) != -1:
			continue

		# Ground detail scattered above already claims this cell.
		if terrain_features.get_cell_source_id(pos) != -1:
			continue

		var ground_type := get_cell_ground_type(pos)
		if ground_type == -1 or ground_type == GroundTile.WATER:
			continue

		if local_rng.randf() > map_template.terrain_feature_density:
			continue

		# Build a candidate pool from the routed terrain-feature categories.
		var candidates: Array = []
		match ground_type:
			GroundTile.GRASS:
				if local_rng.randf() < map_template.grass_feature_density * _cluster_weight(grass_mask, pos):
					candidates.append_array(grass_tiles)
				if local_rng.randf() < map_template.flower_density * _cluster_weight(plant_mask, pos):
					candidates.append_array(plant_tiles)
			GroundTile.DIRT:
				if local_rng.randf() < map_template.dirt_feature_density * _cluster_weight(grass_mask, pos):
					candidates.append_array(grass_tiles)
				if local_rng.randf() < map_template.mud_feature_density * _cluster_weight(farm_mask, pos):
					candidates.append_array(farm_tiles)
			GroundTile.STONE:
				if local_rng.randf() < map_template.stone_feature_density * _cluster_weight(rock_mask, pos):
					candidates.append_array(rock_tiles)

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
				if terrain_features.get_cell_source_id(check) != -1:
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

# ════════════════════════════════════════════════════════════════════════
#  CELL QUERIES
#
#  Read back what is painted at a cell. The band an atlas coord falls in says
#  whether a cell is water, rock or open ground, and because surfaces that
#  cannot sit on base_terrain are laid over it on terrain_features (see SURFACE
#  PAINTING), the overlay has to answer before the base layer does. An empty
#  cell never blocks, so layers with nothing on them are transparent.
# ════════════════════════════════════════════════════════════════════════

func get_cell_ground_type(coords: Vector2i) -> int:
	match _band_category(terrain_features, coords):
		"liquid": return GroundTile.WATER
		"ground_detail", "rock": return GroundTile.STONE
	match _band_category(ground, coords):
		"ground", "grass", "farm": return GroundTile.GRASS
		_: return -1

func get_cell_foliage_type(coords: Vector2i) -> String:
	if foliage.get_cell_source_id(coords) == -1:
		return ""
	return _band_category(foliage, coords)

func _band_walkable(layer: TileMapLayer, coords: Vector2i) -> bool:
	if layer == null or layer.get_cell_source_id(coords) == -1:
		return true
	var band: Dictionary = Layout.category_band_for_row(layer.get_cell_atlas_coords(coords).y)
	return band.get("walkable", true)


func _band_category(layer: TileMapLayer, coords: Vector2i) -> String:
	if layer.get_cell_source_id(coords) == -1:
		return ""
	var band: Dictionary = Layout.category_band_for_row(layer.get_cell_atlas_coords(coords).y)
	return band.get("category", "")

# ═════════════════════════════════════════════════════════════════════
#  WORLD-MAP INTERFACE
#
#  The same coordinate / bounds / walkability surface qud_like_world_map.gd
#  exposes, so the Player can point its `world_map` reference at a generated
#  local map and keep moving without caring which kind of map it stands on.
# ═════════════════════════════════════════════════════════════════════

## Extent in tiles. Generation always paints the full WIDTH×HEIGHT grid.
var bounds: Rect2i = Rect2i(0, 0, WIDTH, HEIGHT)


func world_to_tile(world_pos: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(world_pos))


func tile_to_world(tile: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(tile))


## Map extent in pixels — used to clamp the camera.
func bounds_px() -> Rect2:
	var cell: Vector2 = Vector2(ground.tile_set.tile_size) if ground.tile_set else Vector2(16, 16)
	return Rect2(ground.to_global(Vector2(bounds.position) * cell), Vector2(bounds.size) * cell)


func is_in_bounds(tile: Vector2i) -> bool:
	return bounds.has_point(tile)


## Nearest walkable tile to `from`, searched outward in rings up to
## `max_radius`. Returns `from` unchanged if nothing walkable is in range —
## used to place the player on solid ground when entering a local map.
func nearest_walkable(from: Vector2i, max_radius: int = 64) -> Vector2i:
	if is_walkable(from):
		return from
	for radius in range(1, max_radius + 1):
		var best := Vector2i.MAX
		var best_dist := INF
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				# Ring only — the interior was covered by a smaller radius.
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := from + Vector2i(dx, dy)
				if not is_walkable(candidate):
					continue
				var dist := Vector2(candidate - from).length_squared()
				if dist < best_dist:
					best_dist = dist
					best = candidate
		if best != Vector2i.MAX:
			return best
	return from


func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= WIDTH or pos.y < 0 or pos.y >= HEIGHT:
		return false
	var ground_type = get_cell_ground_type(pos)
	if ground_type == GroundTile.WATER:
		return false

	# The band table already says which categories block, so a decorative
	# plant or grass tuft on the foliage layer does not wall the tile off.
	# Decor layers are included because props (barrels, wells, furniture) are
	# solid objects, not paint — leaving them out let the player walk through
	# every crate in a settlement.
	for layer: TileMapLayer in [foliage, terrain_features, structures_exterior,
			decor_exterior, decor_interior]:
		if not _band_walkable(layer, pos):
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

## Places a small cluster of buildings and returns them as
## [{type, pos, size}, …] so the caller can run the decor passes over them.
func generate_hamlet(hamlet_type: String, local_rng: RandomNumberGenerator) -> Array:
	var building_count: int = 0
	match hamlet_type:
		"village":
			building_count = local_rng.randi_range(3, 6)
		"farm":
			building_count = local_rng.randi_range(2, 4)
	
	# Create a grid to track building placement
	var occupation_grid: Array = []
	for y in HEIGHT:
		occupation_grid.append([])
		for x in WIDTH:
			occupation_grid[y].append(false)
	
	# Place buildings
	var hamlet_types: Array[int] = [
		Structure.StructureType.HOUSE,
		Structure.StructureType.HOUSE,
		Structure.StructureType.SHOP,
		Structure.StructureType.TAVERN,
	]
	var placed: Array = []
	# A hamlet is a handful of buildings in open wilderness, so it needs the
	# same bounded core a settlement gets — otherwise "cluster of huts" spreads
	# over the whole local map. Sized as if every building were a house, which
	# is what most of them are.
	var core := _settlement_core_rect(
		Vector2i(WIDTH, HEIGHT),
		{Structure.StructureType.HOUSE: building_count},
		SETTLEMENT_SPREAD[MapConfig.BuildingDensity.SMALL_VILLAGE])
	var attempts: int = 0
	while placed.size() < building_count and attempts < 100:
		var building_type: int = hamlet_types[local_rng.randi() % hamlet_types.size()]
		var sprite_def = _building_def(building_type)
		if sprite_def == null:
			attempts += 1
			continue
		var size: Vector2i = sprite_def["size"]
		var pos := find_valid_building_position_settlement(
			Vector2i(WIDTH, HEIGHT), size, occupation_grid, local_rng, building_type, core, placed)
		if pos.x != -1:
			place_building_settlement(pos, size, building_type)
			mark_occupied_settlement(occupation_grid, pos, size, sprite_def["spacing"])
			placed.append({"type": building_type, "pos": pos, "size": size})
		attempts += 1
	return placed

# Settlement-specific building functions

## The patch of map a settlement may build in, centred on the map.
##
## Sized from the buildings themselves (see SETTLEMENT_SPREAD) rather than from
## the map, so the search area shrinks with the settlement instead of scattering
## a village across eighty tiles of wilderness. Falls back to the whole map when
## there is nothing to measure.
func _settlement_core_rect(area_size: Vector2i, counts: Dictionary, spread: float) -> Rect2i:
	var footprint := 0.0
	for building_type in counts:
		var sprite_def = _building_def(building_type)
		if sprite_def == null:
			continue
		var size: Vector2i = sprite_def["size"]
		# Spacing is claimed on both sides: the placement check rejects anything
		# within `spacing` of the footprint and mark_occupied_settlement then
		# reserves that ring, so a house really costs (size + 2 * spacing).
		var claim := Vector2i(size.x + 2 * sprite_def["spacing"], size.y + 2 * sprite_def["spacing"])
		footprint += float(counts[building_type]) * float(claim.x * claim.y)
	if footprint <= 0.0:
		return Rect2i(Vector2i.ZERO, area_size)
	var radius := ceili(sqrt(footprint / PI) * spread)
	var half := Vector2i(radius, radius)
	return Rect2i(area_size / 2 - half, half * 2).intersection(Rect2i(Vector2i.ZERO, area_size))


func _settlement_spread() -> float:
	if map_template == null:
		return 1.7
	return SETTLEMENT_SPREAD.get(int(map_template.building_density), 1.7)


## How good a spot this is for a building that wants to belong to a settlement.
##
## Distance to the nearest neighbour dominates — that is what makes a cluster of
## houses read as a village rather than scattered homesteads. A weaker pull
## toward the core's centre keeps the settlement from drifting off in one
## direction as it grows, and gives the first building (which has no neighbour
## to measure against) somewhere sensible to stand.
func _settlement_cohesion_score(pos: Vector2i, size: Vector2i, placed: Array, core: Rect2i) -> float:
	var centre := Vector2(pos) + Vector2(size) * 0.5
	var anchor := Vector2(core.get_center())
	var anchor_span := maxf(1.0, maxf(core.size.x, core.size.y) * 0.5)
	var anchor_score := 1.0 - clampf(centre.distance_to(anchor) / anchor_span, 0.0, 1.0)

	var nearest := INF
	for building in placed:
		var other := Vector2(building["pos"]) + Vector2(building["size"]) * 0.5
		nearest = minf(nearest, centre.distance_to(other))
	if is_inf(nearest):
		return anchor_score

	var neighbour_score := 1.0 - clampf(nearest / SETTLEMENT_NEIGHBOUR_SPAN, 0.0, 1.0)
	return neighbour_score + anchor_score * 0.35


func find_valid_building_position_settlement(area_size: Vector2i, size: Vector2i, occupied_space_grid: Array, settlement_rng: RandomNumberGenerator, building_type: int, core: Rect2i = Rect2i(), placed: Array = []) -> Vector2i:
	var sprite_def = _building_def(building_type)
	var spacing: int = sprite_def["spacing"] if sprite_def else 1
	var search := core if core.has_area() else Rect2i(Vector2i.ZERO, area_size)

	# A tight core can be narrower than the building plus its spacing, so the
	# range is clamped to the map rather than handed to randi_range inverted.
	var min_x: int = clampi(search.position.x, spacing, maxi(spacing, area_size.x - size.x - spacing))
	var max_x: int = clampi(search.end.x - size.x, min_x, maxi(min_x, area_size.x - size.x - spacing))
	var min_y: int = clampi(search.position.y, spacing, maxi(spacing, area_size.y - size.y - spacing))
	var max_y: int = clampi(search.end.y - size.y, min_y, maxi(min_y, area_size.y - size.y - spacing))

	var best_pos := Vector2i(-1, -1)
	var best_score := -INF
	var candidates := SETTLEMENT_PLACEMENT_CANDIDATES
	var attempts := 0

	while attempts < 200 and candidates > 0:
		attempts += 1
		var x := settlement_rng.randi_range(min_x, max_x)
		var y := settlement_rng.randi_range(min_y, max_y)

		var valid := true
		for dy in range(-spacing, size.y + spacing):
			for dx in range(-spacing, size.x + spacing):
				var check_x := x + dx
				var check_y := y + dy
				if check_x < 0 or check_x >= area_size.x or check_y < 0 or check_y >= area_size.y:
					valid = false
					break
				if occupied_space_grid[check_y][check_x]:
					valid = false
					break
			if not valid:
				break
		if not valid:
			continue

		candidates -= 1
		var score := _settlement_cohesion_score(Vector2i(x, y), size, placed, search)
		score += settlement_rng.randf_range(-0.08, 0.08)
		if score > best_score:
			best_score = score
			best_pos = Vector2i(x, y)

	return best_pos

func mark_occupied_settlement(occupied_space_grid: Array, pos: Vector2i, size: Vector2i, spacing: int = 0) -> void:
	for y in range(pos.y - spacing, pos.y + size.y + spacing):
		for x in range(pos.x - spacing, pos.x + size.x + spacing):
			if y >= 0 and y < occupied_space_grid.size() and x >= 0 and x < occupied_space_grid[y].size():
				occupied_space_grid[y][x] = true

# Place a settlement building using a premade sprite
func place_building_settlement(pos: Vector2i, size: Vector2i, building_type: int) -> void:
	var sprite_def = _building_def(building_type)
	if not sprite_def:
		push_warning("No BUILDING_SPRITES entry for building type %d" % building_type)
		return
	_place_building_sprite(pos, size, sprite_def, building_type)

# ── Shared sprite placement ────────────────────────────────────────────────
# Paints ground terrain under the footprint, clears foliage, then stamps
# walls/door/floor tiles for the building.
func _place_building_sprite(pos: Vector2i, size: Vector2i, sprite_def: Dictionary, _building_type: int) -> void:
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

	# The yard is ground, not road, so it goes on the terrain layers. It is also
	# the mask that keeps trees out of the village: add_foliage reads
	# building_clear_cells for that, since these cells are no longer
	# distinguishable by having something painted on the road layer.
	_paint_surface(ground, building_cells, sprite_def.get("ground", "dirt"))

	# Clear foliage under the building
	for cell in building_cells:
		building_clear_cells[cell] = true
		if foliage.get_cell_source_id(cell) != -1:
			foliage.set_cell(cell, -1)
	_stamp_building_tiles(pos, size, patch_rng, str(sprite_def.get("floor", "")))


## Draw a building as tiles: a directional wall ring with a single door and a
## cleared interior floor of `floor_material` (a Layout.FLOOR_TILES name; "" for
## the default). Floor is also laid beneath the walls so the ring never sits on
## bare ground; structures_interior draws below structures_exterior, so the wall
## art stays on top.
func _stamp_building_tiles(pos: Vector2i, size: Vector2i, rng: RandomNumberGenerator,
		floor_material: String = "") -> void:
	var wall_pool := _catalog_pool("structure", "wall")
	var wall_map := RoguelikeCatalog.default_wall_entries(wall_pool)
	if wall_map.is_empty():
		push_warning("MapGenerator: no wall tiles in the catalog — building at %s not drawn" % pos)
		return
	var rect := Rect2i(pos, size)

	var floor_entry := _floor_entry(floor_material)

	# Floor first so the wall ring paints over its outer edge.
	var floor_cells: Array[Vector2i] = []
	for y in range(rect.position.y + 1, rect.end.y - 1):
		for x in range(rect.position.x + 1, rect.end.x - 1):
			floor_cells.append(Vector2i(x, y))
	if floor_entry.is_empty():
		_paint_surface(structures_interior, floor_cells, "dirt")
	else:
		for cell in floor_cells:
			structures_interior.set_cell(cell, floor_entry["source_id"], floor_entry["atlas"])

	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var role := _wall_role(Vector2i(x, y), rect)
			if role.is_empty():
				continue
			var cell := Vector2i(x, y)
			var wall: Dictionary = wall_map[role]
			structures_exterior.set_cell(cell, wall["source_id"], wall["atlas"])
			# Floor beneath the wall so gaps in the wall art read as flooring.
			if not floor_entry.is_empty():
				structures_interior.set_cell(cell, floor_entry["source_id"], floor_entry["atlas"])

	var door_cell := _pick_door_cell(rect, rng)
	var doors := _catalog_pool("structure", "door")
	if doors.is_empty():
		# No door art: leave a gap, which still reads and walks as a way in.
		structures_exterior.erase_cell(door_cell)
	else:
		var door: Dictionary = doors[rng.randi() % doors.size()]
		structures_exterior.set_cell(door_cell, door["source_id"], door["atlas"])


## The wall-map role ("nw", "n", … ) for a cell on `rect`'s perimeter, or ""
## for interior cells.
func _wall_role(cell: Vector2i, rect: Rect2i) -> String:
	var left := cell.x == rect.position.x
	var right := cell.x == rect.end.x - 1
	var top := cell.y == rect.position.y
	var bottom := cell.y == rect.end.y - 1
	if top:
		return "nw" if left else ("ne" if right else "n")
	if bottom:
		return "sw" if left else ("se" if right else "s")
	if left:
		return "w"
	if right:
		return "e"
	return ""


## A non-corner cell on the wall ring to use as the entrance. Assumes a
## footprint at least 3x3, which every BUILDING_SPRITES entry is.
func _pick_door_cell(rect: Rect2i, rng: RandomNumberGenerator) -> Vector2i:
	match rng.randi() % 4:
		0: return Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 2), rect.end.y - 1)
		1: return Vector2i(rng.randi_range(rect.position.x + 1, rect.end.x - 2), rect.position.y)
		2: return Vector2i(rect.position.x, rng.randi_range(rect.position.y + 1, rect.end.y - 2))
		_: return Vector2i(rect.end.x - 1, rng.randi_range(rect.position.y + 1, rect.end.y - 2))

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
			var distance_sq = (building_a["pos"] - building_b["pos"]).length_squared()
			if distance_sq > 400.0: # Maximum road distance squared
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
	
	# Collect road cells, varying width per cell for an organic look.
	var road_cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for pos in path:
		# Width is mostly 1 tile each side, occasionally 2
		var half_w: int = 1 if road_rng.randf() > 0.25 else 2
		for dx in range(-half_w, half_w + 1):
			for dy in range(-half_w, half_w + 1):
				var road_pos = pos + Vector2i(dx, dy)
				if road_pos.x >= 0 and road_pos.x < WIDTH and road_pos.y >= 0 and road_pos.y < HEIGHT:
					if not seen.has(road_pos):
						seen[road_pos] = true
						road_cells.append(road_pos)
	
	# Apply terrain change using terrain sets for proper transitions
	_paint_surface(road, road_cells, surface)

func get_door_position_settlement(building: Dictionary) -> Vector2i:
	# Returns the center of the south wall of the building as the door position
	return Vector2i(
		building["pos"].x + (building["size"].x >> 1),
		building["pos"].y + building["size"].y - 1
	)

# Adds winding, irregular drift for a
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
## Reads road_exits from map_template (MapConfig); the surface is always
## ROAD_SURFACE, since the road layer only ever draws roads.
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

	# Seeded RNG for deterministic edge-road variation
	var edge_rng := RandomNumberGenerator.new()
	edge_rng.seed = int(map_template.SEED) ^ 0xDEADBEEF

	# Draw each road segment from the edge toward the centre
	var road_cells: Array[Vector2i] = []
	var seen: Dictionary = {}
	for ep: Vector2i in endpoints:
		var path: Array = get_varied_path(ep, center, edge_rng)
		for cell: Vector2i in path:
			# Vary width: mostly road_half, occasionally one wider
			var hw: int = road_half if edge_rng.randf() > 0.2 else road_half + 1
			for dx in range(-hw, hw + 1):
				for dy in range(-hw, hw + 1):
					var rp := cell + Vector2i(dx, dy)
					if rp.x >= 0 and rp.x < WIDTH and rp.y >= 0 and rp.y < HEIGHT:
						if not seen.has(rp):
							seen[rp] = true
							road_cells.append(rp)

	if road_cells.is_empty():
		return

	_paint_surface(road, road_cells, ROAD_SURFACE)

## Process MapConfig.misc_features to place hamlets, farms, camps, etc.
## This replaces the old random 30% hamlet-chance logic with data-driven features.
## Places every misc feature the config asks for and returns the buildings they
## put down, in the {type, pos, size} shape the decor passes expect. Without
## this the local-area path had no building list, so props had nothing to
## cluster around and none were ever placed.
func _generate_misc_features(local_rng: RandomNumberGenerator) -> Array:
	var placed: Array = []
	for feature in map_template.misc_features:
		match feature:
			MapConfig.MiscFeatures.HAMLET:
				placed.append_array(generate_hamlet("village", local_rng))
			MapConfig.MiscFeatures.FARM:
				placed.append_array(generate_hamlet("farm", local_rng))
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
	return placed
