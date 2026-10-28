@tool
extends RefCounted
class_name TilesetCatalog

## Declarative layout of the Backterria master sheet
## "The Roguelike 1-15-1.png"  (source in resources/the_roguelike.tres).
##
## Grid: 109 cols x 46 rows @ 16px. This is the promotional layout sheet, so it
## has baked-in furniture that is NOT game art:
##   - cols 0..3      = the left category-label strip (skip)
##   - rows 0..1, 45  = header / footer banners (skip)
##
## This table is the SINGLE SOURCE OF TRUTH for tile semantics. Editing a band
## here and re-running scripts/tools/stamp_roguelike_metadata.gd re-stamps the
## tileset's custom-data layers -- no per-tile clicking in the inspector.
##
## THEME column bands were derived objectively from transparent-gutter analysis
## and are considered CONFIRMED. CATEGORY row bands are a DRAFT seeded from the
## baked label positions; verify them with the stamper's DRY_RUN report (which
## prints an annotated occupancy map) and nudge the row ranges until they line
## up with the sheet.

# --- geometry ---
const TILE_SIZE := 16
const GRID_COLS := 109
const GRID_ROWS := 46
const TEXTURE_BASENAME := "The Roguelike 1-15-1.png"  # picks the right atlas source

const ALPHA_TEXTURE_MARKER := "Alpha"

## True when `file_name` is the transparent cut of the master sheet.
static func is_alpha_texture(file_name: String) -> bool:
	return ALPHA_TEXTURE_MARKER in file_name

# --- THEME column bands (col_start..col_end inclusive) --- CONFIRMED
const THEME_BANDS := [
	{"theme": "medieval_fantasy",         "cols": [4, 13]},
	{"theme": "mediterranean_fantasy",  "cols": [16, 20]},
	{"theme": "alien",           "cols": [23, 27]}, # Space theme. Only use rows 3-10
	{"theme": "post_apocalypse", "cols": [29, 39]}, # only use rows 3-10
	{"theme": "badlands",     "cols": [41, 51]},
	{"theme": "world_wars",      "cols": [53, 63]}, # only use rows 3-10
	{"theme": "tropical",         "cols": [65, 75]},
	{"theme": "desert_culture",   "cols": [77, 87]},
	{"theme": "far_east",           "cols": [89, 96]},
	{"theme": "cyberpunk",       "cols": [98, 108]}, # don't use
]

# The theme whose art this game paints with, and the one whose columns are
# biomes rather than variants. Currently the same block; separate names because
# they are separate facts.
const DEFAULT_THEME := "medieval_fantasy"
const BIOME_THEME := "medieval_fantasy"
const BIOME_COLUMNS := {
	4: "temperate",
	5: "volcanic",
	6: "savannah",
	7: "boreal",
	8: "jungle",
	9: "arctic",
	10: "desert",
	11: "dead",
	12: "swamp",
	13: "cursed",
}
const BIOME_CATEGORIES: Array[String] = ["tree", "grass", "plant", "bush", "rock", "ground", "ground_detail"]

## Biome for an atlas coord, or "" when the tile does not vary by environment.
static func biome_for(coord: Vector2i, theme: String, category: String) -> String:
	if theme != BIOME_THEME or not BIOME_CATEGORIES.has(category):
		return ""
	return BIOME_COLUMNS.get(coord.x, "")


## Every biome that has art, in column order. Handy for validating a biome name
## or picking one at random.
static func biome_names() -> Array:
	return BIOME_COLUMNS.values()

# --- CATEGORY row bands (row_start..row_end inclusive) --- verified against the sheet
# is_map_tile == false  -> inventory / entity sprites. These belong in ItemDatabase,
#                          not the map tile catalog, so the generator ignores them.
# local_gen  == false   -> world/overworld art only; the local scene (town/interior)
#                          generator must NOT place these.
# walkable is the DEFAULT for the whole band; refine individual oddballs in OVERRIDES.
const CATEGORY_BANDS := [
	{"category": "tree",     "rows": [3, 4],   "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "grass",    "rows": [5, 5],   "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "plant",    "rows": [6, 6],   "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "bush",     "rows": [7, 7],   "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "rock",     "rows": [8, 8],   "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	# The sheet draws ground twice: row 9 is the flat, full-coverage fill for a
	# biome, row 10 the coarser rubble/tussock cut of the same environment.
	# Treating both as one category made the base layer alternate between the two
	# in a visible regular pattern, so they are split: row 9 is the only thing
	# that paints base terrain, row 10 scatters on top as a feature (and so must
	# come from the transparent cut, or it would blank the fill beneath it).
	{"category": "ground",        "rows": [9, 9],   "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": false},
	{"category": "ground_detail", "rows": [10, 10], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": false, "use_alpha": true},
	{"category": "road",     "rows": [11, 11], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "rail",     "rows": [12, 12], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "liquid",   "rows": [13, 13], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "mountain", "rows": [14, 14], "walkable": false, "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "farm",     "rows": [15, 16], "walkable": true,  "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "building", "rows": [17, 18], "walkable": false, "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "wall",     "rows": [19, 20], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "door",     "rows": [21, 21], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	# Props are opt-in: the band default of "none" keeps a prop out of both the
	# interior and exterior pools until OVERRIDES gives it a placement. That way
	# an unclassified prop is never scattered by accident (no barrels in a
	# graveyard, no gravestones in a kitchen) — commenting out an override is
	# enough to pull that tile from generation.
	{"category": "prop",     "rows": [22, 26], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true, "placement": "none"},
	# --- TODO rows 27+ : animals, monsters, heroes, and inventory sprites. Excluded from
	# the map tile catalog (spawned as entities / held as items, not painted). Sub-split
	# into animal/monster/hero bands later if themed entity selection is wanted.
	{"category": "entity_sprite", "rows": [27, 43], "walkable": true, "is_map_tile": false, "local_gen": false},
]

# --- generator pools ---
# Where MapGenerator looks for each band category: tile_catalog[category][type].
# A band with no route here is invisible to the generator.
const CATEGORY_ROUTING := {
	"tree":     {"category": "foliage",          "type": "tree"},
	"bush":     {"category": "foliage",          "type": "bush"},
	"plant":    {"category": "foliage",          "type": "plant"},
	"grass":    {"category": "terrain_features", "type": "grass"},
	"rock":     {"category": "terrain_features", "type": "rock"},
	"farm":     {"category": "terrain_features", "type": "farm"},
	"ground":   {"category": "surface",          "type": "ground"},
	# Row 10's coarse cut is never a base surface — it scatters over one as a
	# feature, so it routes to the feature layer.
	"ground_detail": {"category": "terrain_features", "type": "ground_detail"},
	"road":     {"category": "road",             "type": "road"},
	"liquid":   {"category": "surface",          "type": "water"},
	"mountain": {"category": "surface",          "type": "mountain"},
	"wall":     {"category": "structure",        "type": "wall"},
	"door":     {"category": "structure",        "type": "door"},
	"building": {"category": "structure",        "type": "building"},
	"prop":     {"category": "decor_exterior",   "type": "prop"},
}

## Surface names MapGenerator paints with → the band they draw from. Aliases
## onto CATEGORY_ROUTING rather than a second routing table, so a pool is
## defined in one place only.
##
## "grass" and "dirt" both land on the `ground` band, which has no material
## sub-columns yet, so on screen the two are currently identical.
const SURFACE_BANDS := {
	"grass":       "ground",
	"dirt":        "ground",
	"stone":       "ground_detail",
	"water":       "liquid",
	"wheat_field": "farm",
	# Paths used to be painted as "dirt" — the same band the base terrain comes
	# from — which made every road invisible.
	"road":        "road",
}

## Pool for a name with no route, so a typo paints something rather than nothing.
const FALLBACK_ROUTE := {"category": "surface", "type": "ground"}

static func surface_route(surface: String) -> Dictionary:
	return CATEGORY_ROUTING.get(SURFACE_BANDS.get(surface, ""), FALLBACK_ROUTE)


## Where a band category lands in the catalog, or {} when it is not routed there.
static func category_route(category: String) -> Dictionary:
	return CATEGORY_ROUTING.get(category, {})


# --- named tiles ---
# Single coords the generator asks for by name. A band is one atlas row and the
# columns across it are themes and biomes, so a specific material or icon cannot
# be expressed as a band — it has to be pointed at directly.

## Which building icon on the world map's `locations` layer means which size of
## settlement. Only the `building` band (rows 17–18) belongs here — that layer
## also carries roads.
const SETTLEMENT_TILES := {
	Vector2i(4, 17): MapConfig.BuildingDensity.SMALL_TOWN,
	Vector2i(6, 18): MapConfig.BuildingDensity.CITY,
	Vector2i(5, 18): MapConfig.BuildingDensity.SMALL_VILLAGE,	# will be castle once implemented
}

const NO_SETTLEMENT := -1

static func settlement_density_for(coord: Vector2i) -> int:
	return SETTLEMENT_TILES.get(coord, NO_SETTLEMENT)

## The wall ring a generated building is drawn with, by compass role.
const DEFAULT_WALL_TILES := {
	"nw": Vector2i(5, 19),
	"n":  Vector2i(6, 19),
	"ne": Vector2i(7, 19),
	"e":  Vector2i(9, 20),
	"se": Vector2i(7, 20),
	"s":  Vector2i(8, 20),
	"sw": Vector2i(5, 20),
	"w":  Vector2i(4, 19),
}

## Flooring laid inside a generated building when its BUILDING_SPRITES entry
## names no material of its own. Same base-sheet rule as FLOOR_TILES below.
const DEFAULT_FLOOR_ATLAS := Vector2i(66, 10)

## Named floor materials a building can ask for, keyed by what they look like
## rather than by which building uses them — which type gets which floor is
## MapGenerator.BUILDING_SPRITES' business, not this table's.
##
## ALWAYS PAINTED FROM THE BASE SHEET, never the alpha cut. A floor has to cover
## the ground beneath it, and the rows these coords are borrowed from belong to
## the transparent scatter version — drawn from that, floorboards show the yard
## through them. MapGenerator._floor_entry() is what enforces this, by reading
## the opaque source directly instead of going through the tile catalog.
##
## Being single coords rather than a band, they also sidestep theme and biome
## filtering: `dark_wood` is borrowed from the tropical block because that is
## where the sheet keeps its boards, and a floor should not change with the
## weather outside.
const FLOOR_TILES := {
	"dark_wood": Vector2i(66, 10),
	"stone_floor": Vector2i(5, 10),
	"dirt": Vector2i(5, 9),
}

## Atlas coord for a named floor material, falling back to the default floor so
## a typo lays boards rather than nothing.
static func floor_atlas(material: String) -> Vector2i:
	return FLOOR_TILES.get(material, DEFAULT_FLOOR_ATLAS)

## Furnishings a building type is given by rule instead of by scatter — a
## tavern's bar, a church's altar, a smithy's forge. Which building gets which
## is MapGenerator.BUILDING_INTERIORS' business; this table only says where the
## art is. Painted from the alpha cut like any other prop, so they sit on top of
## the flooring.
##
## `counter` is a single segment of bar top, meant to be laid in a short run.
## `altar` is borrowed from the mediterranean building band, which is where the
## sheet keeps its stone plinth.
const NO_FIXTURE := Vector2i(-1, -1)
const FIXTURE_TILES := {
	"counter": Vector2i(90, 24),
	"altar": Vector2i(16, 18),
	"forge": Vector2i(13, 25),
}

static func fixture_atlas(fixture: String) -> Vector2i:
	return FIXTURE_TILES.get(fixture, NO_FIXTURE)

# --- item art ---
# The sheet keeps its held/carried sprites in rows 34+, past every map-tile
# band, so they are addressed by name here rather than routed through the tile
# catalog. This is the one place item art lives: give an id a coord below and
# every icon, tooltip and dropped-item sprite picks it up (see Item.get_sprite_index).
#
# The key is the Item's `sprite_id`, or its `id` when that is left blank — so
# most items need nothing set on the resource at all. An item with no entry
# here falls back to whatever `sprite_index` its .tres carries, which is the
# escape hatch for one-off art that does not deserve a name.

## The transparent cut of the master sheet. Items are drawn over an inventory
## slot or a floor tile, so they must never carry the opaque background.
const ITEM_SHEET := preload("res://assets/The Roguelike 1-15-1 Alpha.png")
const ITEM_TILE_SIZE := Vector2i(TILE_SIZE, TILE_SIZE)
const NO_ITEM_TILE := Vector2i(-1, -1)

const ITEM_TILES := {
	# ---- medieval_fantasy (cols 4..13) ----
	# weapons — row 34
	"dagger":             Vector2i(4, 34),
	"basic_sword":        Vector2i(5, 34),
	"club":               Vector2i(6, 34),
	"axe":                Vector2i(7, 34),
	"spear":              Vector2i(8, 34),
	"warhammer":          Vector2i(9, 34),
	"bow":                Vector2i(10, 34),
	"arrow":              Vector2i(11, 34),
	"staff":              Vector2i(12, 34),
	"torch":              Vector2i(13, 34),
	# apparel — row 35
	"leather_armor":      Vector2i(4, 35),
	"leather_pants":      Vector2i(5, 35),
	"leather_boots":      Vector2i(6, 35),
	"leather_gloves":     Vector2i(7, 35),
	"belt":               Vector2i(8, 35),
	"leather_hat":        Vector2i(9, 35),
	"iron_helm":          Vector2i(10, 35),
	"round_shield":       Vector2i(11, 35),
	"heater_shield":      Vector2i(12, 35),
	"kite_shield":        Vector2i(13, 35),
	# items — row 36
	"health_potion":      Vector2i(4, 36),
	"mana_potion":        Vector2i(5, 36),
	"stamina_potion":     Vector2i(6, 36),
	"gold_key":           Vector2i(7, 36),
	"iron_key":           Vector2i(8, 36),
	"scroll":             Vector2i(9, 36),
	"old_scroll":         Vector2i(10, 36),
	"book":               Vector2i(11, 36),
	"spellbook_fireball": Vector2i(12, 36),
	"journal":            Vector2i(13, 36),
	# resources — row 37
	"sapphire":           Vector2i(4, 37),
	"diamond":            Vector2i(5, 37),
	"coin_stack":         Vector2i(6, 37),
	"gold_coin":          Vector2i(7, 37),
	"coin_pouch":         Vector2i(8, 37),
	"gold_ring":          Vector2i(9, 37),
	"sapphire_ring":      Vector2i(10, 37),
	"amethyst_ring":      Vector2i(11, 37),
	"golden_crest":       Vector2i(12, 37),
	"amulet":             Vector2i(13, 37),
	# tools — row 38
	"shovel":             Vector2i(4, 38),
	"pitchfork":          Vector2i(5, 38),
	"scythe":             Vector2i(6, 38),
	"watering_can":       Vector2i(7, 38),
	"tankard":            Vector2i(8, 38),
	"bucket":             Vector2i(9, 38),
	"water_bucket":       Vector2i(10, 38),
	"lava_bucket":        Vector2i(11, 38),
	"compass":            Vector2i(12, 38),
	"brass_spyglass":     Vector2i(13, 38),
	# food — row 39
	"apple":              Vector2i(4, 39),
	"pear":               Vector2i(5, 39),
	"ham":                Vector2i(6, 39),
	"bread":              Vector2i(7, 39),
	"cheese":             Vector2i(8, 39),
	"carrot":             Vector2i(9, 39),
	"watermelon":         Vector2i(10, 39),
	"red_mushroom":       Vector2i(11, 39),
	"green_mushroom":     Vector2i(12, 39),
	"wineskin":           Vector2i(13, 39),

	# ---- mediterranean_fantasy (cols 16..21) ----
	# weapons — row 34
	"javelin":            Vector2i(16, 34),
	"bronze_axe":         Vector2i(17, 34),
	"kopis":              Vector2i(18, 34),
	"hook":               Vector2i(19, 34),
	"blue_torch":         Vector2i(20, 34),
	# apparel — row 35
	"chainmail":          Vector2i(16, 35),
	"pleated_skirt":      Vector2i(17, 35),
	"sandals":            Vector2i(18, 35),
	"corinthian_helm":    Vector2i(19, 35),
	"bronze_shield":      Vector2i(20, 35),
	"sun_shield":         Vector2i(21, 35),
	# items — row 36
	"blue_scroll":        Vector2i(16, 36),
	"blue_scroll_written": Vector2i(17, 36),
	"quill":              Vector2i(18, 36),
	"ink_bottle":         Vector2i(19, 36),
	"olive_branch":       Vector2i(20, 36),
	"golden_laurel":      Vector2i(21, 36),
	# resources — row 37
	"aquamarine":         Vector2i(16, 37),
	"amber":              Vector2i(17, 37),
	"copper_ring":        Vector2i(18, 37),
	"gold_necklace":      Vector2i(19, 37),
	"seashell":           Vector2i(20, 37),
	"spiral_shell":       Vector2i(21, 37),
	# tools — row 38
	"pan_flute":          Vector2i(16, 38),
	"lyre":               Vector2i(17, 38),
	"sundial":            Vector2i(18, 38),
	"abacus":             Vector2i(19, 38),
	# food — row 39
	"pomegranate":        Vector2i(16, 39),
	"wheat":              Vector2i(17, 39),
	"feta":               Vector2i(18, 39),
	"olive_oil_jug":      Vector2i(19, 39),
	"wine_bottle":        Vector2i(20, 39),

	# ---- alien (cols 23..25) ----
	# weapons — row 34
	"laser_pistol":       Vector2i(23, 34),
	"laser_rifle":        Vector2i(24, 34),
	"plasma_grenade":     Vector2i(25, 34),
	# apparel — row 35
	"space_helmet":       Vector2i(23, 35),
	"combat_visor":       Vector2i(24, 35),
	"bubble_helmet":      Vector2i(25, 35),
	# items — row 36
	"datapad":            Vector2i(23, 36),
	"energy_cell":        Vector2i(24, 36),
	"oxygen_tanks":       Vector2i(25, 36),
	# resources — row 37
	"purple_crystal":     Vector2i(23, 37),
	"meteorite":          Vector2i(24, 37),
	"keycard":            Vector2i(25, 37),
	# tools — row 38
	"steel_hammer":       Vector2i(23, 38),
	"control_panel":      Vector2i(24, 38),
	"laser_cutter":       Vector2i(25, 38),
	# food — row 39
	"ration_pack":        Vector2i(23, 39),
	"canned_rations":     Vector2i(24, 39),
	"space_water_bottle": Vector2i(25, 39),

	# ---- post_apocalypse (cols 29..39) ----
	# weapons — row 34
	"brass_knuckles":     Vector2i(29, 34),
	"combat_knife":       Vector2i(30, 34),
	"spiked_club":        Vector2i(31, 34),
	"hatchet":            Vector2i(32, 34),
	"crude_bow":          Vector2i(33, 34),
	"crude_arrow":        Vector2i(34, 34),
	"stun_baton":         Vector2i(35, 34),
	"revolver":           Vector2i(36, 34),
	"hunting_rifle":      Vector2i(37, 34),
	"assault_rifle":      Vector2i(38, 34),
	"frag_grenade":       Vector2i(39, 34),
	# apparel — row 35
	"t_shirt":            Vector2i(29, 35),
	"kevlar_vest":        Vector2i(30, 35),
	"jeans":              Vector2i(31, 35),
	"work_boots":         Vector2i(32, 35),
	"work_gloves":        Vector2i(33, 35),
	"utility_belt":       Vector2i(34, 35),
	"cap":                Vector2i(35, 35),
	"combat_helmet":      Vector2i(36, 35),
	"gas_mask":           Vector2i(37, 35),
	"goggles":            Vector2i(38, 35),
	"backpack":           Vector2i(39, 35),
	# items — row 36
	"first_aid_kit":      Vector2i(29, 36),
	"medkit":             Vector2i(30, 36),
	"syringe":            Vector2i(31, 36),
	"bandage_roll":       Vector2i(32, 36),
	"pill":               Vector2i(33, 36),
	"blue_bottle":        Vector2i(34, 36),
	"ammo":               Vector2i(35, 36),
	"cash":               Vector2i(36, 36),
	"battery":            Vector2i(37, 36),
	"car_key":            Vector2i(38, 36),
	"radio":              Vector2i(39, 36),
	# resources — row 37
	"stick":              Vector2i(29, 37),
	"plank":              Vector2i(30, 37),
	"cloth":              Vector2i(31, 37),
	"brick":              Vector2i(32, 37),
	"nails":              Vector2i(33, 37),
	"circuit_board":      Vector2i(34, 37),
	"paper":              Vector2i(35, 37),
	"hose":               Vector2i(36, 37),
	"wire_spool":         Vector2i(37, 37),
	"duct_tape":          Vector2i(38, 37),
	"fuel_can":           Vector2i(39, 37),
	# tools — row 38
	"crowbar":            Vector2i(29, 38),
	"pliers":             Vector2i(30, 38),
	"hammer":             Vector2i(31, 38),
	"screwdriver":        Vector2i(32, 38),
	"trowel":             Vector2i(33, 38),
	"hand_saw":           Vector2i(34, 38),
	"multitool":          Vector2i(35, 38),
	"steel_compass":      Vector2i(36, 38),
	"binoculars":         Vector2i(37, 38),
	"flashlight":         Vector2i(38, 38),
	"crude_torch":        Vector2i(39, 38),
	# food — row 39
	"green_apple":        Vector2i(29, 39),
	"drumstick":          Vector2i(30, 39),
	"jerky":              Vector2i(31, 39),
	"chips":              Vector2i(32, 39),
	"sandwich":           Vector2i(33, 39),
	"canned_food":        Vector2i(34, 39),
	"rye_bread":          Vector2i(35, 39),
	"cheese_slice":       Vector2i(36, 39),
	"water_bottle":       Vector2i(37, 39),
	"glass_bottle":       Vector2i(38, 39),
	"soda_can":           Vector2i(39, 39),

	# ---- badlands (cols 41..45) ----
	# weapons — row 34
	"sharpened_stick":    Vector2i(41, 34),
	"stone_spear":        Vector2i(42, 34),
	"stone_mace":         Vector2i(43, 34),
	"stone_axe":          Vector2i(44, 34),
	"heavy_club":         Vector2i(45, 34),
	# apparel — row 35
	"fur_tunic":          Vector2i(41, 35),
	"fur_cloak":          Vector2i(42, 35),
	"fur_boots":          Vector2i(43, 35),
	"tooth_necklace":     Vector2i(44, 35),
	# items — row 36
	"smooth_stone":       Vector2i(41, 36),
	"fern":               Vector2i(42, 36),
	# resources — row 37
	"log":                Vector2i(41, 37),
	"sinew":              Vector2i(42, 37),
	"straw_bundle":       Vector2i(43, 37),
	"gold_nugget":        Vector2i(44, 37),
	"hide":               Vector2i(45, 37),
	# tools — row 38
	"flint":              Vector2i(41, 38),
	"bone":               Vector2i(42, 38),
	"stone_knife":        Vector2i(43, 38),
	"stone_sickle":       Vector2i(44, 38),
	# food — row 39
	"raw_meat":           Vector2i(41, 39),
	"raw_steak":          Vector2i(42, 39),
	"blue_fish":          Vector2i(43, 39),
	"red_fish":           Vector2i(44, 39),
	"golden_fish":        Vector2i(45, 39),

	# ---- world_wars (cols 53..63) ----
	# weapons — row 34
	"pistol":             Vector2i(53, 34),
	"service_revolver":   Vector2i(54, 34),
	"bolt_rifle":         Vector2i(55, 34),
	"carbine":            Vector2i(56, 34),
	"sniper_rifle":       Vector2i(57, 34),
	"tommy_gun":          Vector2i(58, 34),
	"machine_gun":        Vector2i(59, 34),
	"bayonet_rifle":      Vector2i(60, 34),
	"long_rifle":         Vector2i(61, 34),
	"gun_tripod":         Vector2i(62, 34),
	"heavy_machine_gun":  Vector2i(63, 34),
	# apparel — row 35
	"field_jacket":       Vector2i(53, 35),
	"officer_jacket":     Vector2i(54, 35),
	"field_trousers":     Vector2i(55, 35),
	"combat_boots":       Vector2i(56, 35),
	"combat_gloves":      Vector2i(57, 35),
	"military_belt":      Vector2i(58, 35),
	"steel_helmet":       Vector2i(59, 35),
	"army_helmet":        Vector2i(60, 35),
	"trench_mask":        Vector2i(61, 35),
	"aviator_goggles":    Vector2i(62, 35),
	"rucksack":           Vector2i(63, 35),
	# items — row 36
	"field_medkit":       Vector2i(53, 36),
	"surgical_kit":       Vector2i(54, 36),
	"morphine_syringe":   Vector2i(55, 36),
	"gauze":              Vector2i(56, 36),
	"antidote":           Vector2i(57, 36),
	"medicine_bottle":    Vector2i(58, 36),
	"poison_vial":        Vector2i(59, 36),
	"tonic":              Vector2i(60, 36),
	"tincture":           Vector2i(61, 36),
	# resources — row 37
	"detonator":          Vector2i(53, 37),
	"supply_box":         Vector2i(54, 37),
	"jerrycan":           Vector2i(55, 37),
	"fire_extinguisher":  Vector2i(56, 37),
	"ammo_box":           Vector2i(57, 37),
	"grenade":            Vector2i(58, 37),
	"gas_canister":       Vector2i(59, 37),
	"stick_grenade":      Vector2i(60, 37),
	"explosive_bundle":   Vector2i(61, 37),
	"landmine":           Vector2i(62, 37),
	# tools — row 38
	"army_flashlight":    Vector2i(53, 38),
	"walkie_talkie":      Vector2i(54, 38),
	"field_radio":        Vector2i(55, 38),
	"radio_set_left":     Vector2i(56, 38),  # one 32x16 sprite split over two cells
	"radio_set_right":    Vector2i(57, 38),
	"telephone":          Vector2i(58, 38),
	"camp_stove":         Vector2i(59, 38),
	# food — row 39
	"ration_sack":        Vector2i(53, 39),
	"tin_cans":           Vector2i(54, 39),
	"tin_can":            Vector2i(55, 39),
	"open_tin":           Vector2i(56, 39),
	"mess_tin":           Vector2i(57, 39),
	"loaf":               Vector2i(58, 39),

	# ---- tropical (cols 65..75) ----
	# weapons — row 34
	"pirate_hook":        Vector2i(65, 34),
	"blade_of_dawn":      Vector2i(66, 34),
	"rapier":             Vector2i(67, 34),
	"cutlass":            Vector2i(68, 34),
	"falchion":           Vector2i(69, 34),
	"flintlock_pistol":   Vector2i(70, 34),
	"musket":             Vector2i(71, 34),
	"cannon":             Vector2i(72, 34),
	"cannonballs":        Vector2i(73, 34),
	"bomb":               Vector2i(74, 34),
	"dynamite":           Vector2i(75, 34),
	# apparel — row 35
	"linen_shirt":        Vector2i(65, 35),
	"captain_coat":       Vector2i(66, 35),
	"trousers":           Vector2i(67, 35),
	"breeches":           Vector2i(68, 35),
	"buckled_boots":      Vector2i(69, 35),
	"shoes":              Vector2i(70, 35),
	"white_gloves":       Vector2i(71, 35),
	"pirate_belt":        Vector2i(72, 35),
	"tricorne":           Vector2i(73, 35),
	"feathered_hat":      Vector2i(74, 35),
	"eyepatch":           Vector2i(75, 35),
	# items — row 36
	"empty_bottle":       Vector2i(65, 36),
	"message_bottle":     Vector2i(66, 36),
	"poison_flask":       Vector2i(67, 36),
	"anchor":             Vector2i(68, 36),
	"ship_wheel":         Vector2i(69, 36),
	"treasure_map":       Vector2i(70, 36),
	"candle":             Vector2i(71, 36),
	"lantern":            Vector2i(72, 36),
	"pipe":               Vector2i(73, 36),
	"fishing_net":        Vector2i(74, 36),
	"skeleton_key":       Vector2i(75, 36),
	# resources — row 37
	"emerald":            Vector2i(65, 37),
	"ruby":               Vector2i(66, 37),
	"blue_gem":           Vector2i(67, 37),
	"gold_pile":          Vector2i(68, 37),
	"doubloon":           Vector2i(69, 37),
	"coin_sack":          Vector2i(70, 37),
	"gold_earring":       Vector2i(71, 37),
	"emerald_ring":       Vector2i(72, 37),
	"crown":              Vector2i(73, 37),
	"gold_pendant":       Vector2i(74, 37),
	"rope":               Vector2i(75, 37),
	# tools — row 38
	"oar":                Vector2i(65, 38),
	"mallet":             Vector2i(66, 38),
	"pickaxe":            Vector2i(67, 38),
	"spyglass":           Vector2i(68, 38),
	"ship_compass":       Vector2i(69, 38),
	"pocket_watch":       Vector2i(70, 38),
	# food — row 39
	"rum":                Vector2i(65, 39),
	"grog":               Vector2i(66, 39),
	"beer":               Vector2i(67, 39),
	"potatoes":           Vector2i(68, 39),
	"bananas":            Vector2i(69, 39),
	"pineapple":          Vector2i(70, 39),
	"coconut":            Vector2i(71, 39),
	"stew":               Vector2i(72, 39),
	"vegetable_soup":     Vector2i(73, 39),
	"shrimp_bowl":        Vector2i(74, 39),
	"chicken_stew":       Vector2i(75, 39),

	# ---- desert_culture (cols 77..86) ----
	# weapons — row 34
	"bronze_dagger":      Vector2i(77, 34),
	"bronze_short_sword": Vector2i(78, 34),
	"bronze_sword":       Vector2i(79, 34),
	"bronze_longsword":   Vector2i(80, 34),
	"khopesh":            Vector2i(81, 34),
	"bronze_spear":       Vector2i(82, 34),
	"sickle_sword":       Vector2i(83, 34),
	"crook":              Vector2i(84, 34),
	"sceptre":            Vector2i(85, 34),
	"serpent_staff":      Vector2i(86, 34),
	# apparel — row 35
	"blue_tunic":         Vector2i(77, 35),
	"striped_tunic":      Vector2i(78, 35),
	"royal_robe":         Vector2i(79, 35),
	"pleated_kilt":       Vector2i(80, 35),
	"gold_sandals":       Vector2i(81, 35),
	"gold_gloves":        Vector2i(82, 35),
	"gold_belt":          Vector2i(83, 35),
	"pharaoh_headdress":  Vector2i(84, 35),
	"hide_shield":        Vector2i(85, 35),
	"desert_round_shield": Vector2i(86, 35),
	# items — row 36
	"ankh":               Vector2i(77, 36),
	"gold_ankh":          Vector2i(78, 36),
	"papyrus":            Vector2i(79, 36),
	"papyrus_scroll":     Vector2i(80, 36),
	"eye_of_horus":       Vector2i(81, 36),
	"falcon_idol":        Vector2i(82, 36),
	"pyramid_amulet":     Vector2i(83, 36),
	"blue_mask":          Vector2i(84, 36),
	# resources — row 37
	"topaz":              Vector2i(77, 37),
	"sun_disc":           Vector2i(78, 37),
	"gold_collar":        Vector2i(79, 37),
	"scarab_pendant":     Vector2i(80, 37),
	"pharaoh_crown":      Vector2i(81, 37),
	"gold_brooch":        Vector2i(82, 37),
	"scarab":             Vector2i(83, 37),
	"crystal_shard":      Vector2i(84, 37),
	"garnet":             Vector2i(85, 37),
	"turquoise":          Vector2i(86, 37),
	# tools — row 38
	"paddle":             Vector2i(77, 38),
	"digging_stick":      Vector2i(78, 38),
	"bone_sickle":        Vector2i(79, 38),
	"bone_hook":          Vector2i(80, 38),
	"stone_hoe":          Vector2i(81, 38),
	"boomerang":          Vector2i(82, 38),
	"adze":               Vector2i(83, 38),
	"set_square":         Vector2i(84, 38),
	"flail":              Vector2i(85, 38),
	# food — row 39
	"barley":             Vector2i(77, 39),
	"flatbread":          Vector2i(78, 39),
	"bread_roll":         Vector2i(79, 39),
	"prickly_pear":       Vector2i(80, 39),
	"dates":              Vector2i(81, 39),
	"cherries":           Vector2i(82, 39),
	"oranges":            Vector2i(83, 39),
	"melons":             Vector2i(84, 39),
	"berries":            Vector2i(85, 39),
	"lentil_bowl":        Vector2i(86, 39),

	# ---- far_east (cols 89..96) ----
	# weapons — row 34
	"jian":               Vector2i(89, 34),
	"wakizashi":          Vector2i(90, 34),
	"katana":             Vector2i(91, 34),
	"dao":                Vector2i(92, 34),
	"sai":                Vector2i(93, 34),
	"shuriken":           Vector2i(94, 34),
	"throwing_star":      Vector2i(95, 34),
	"nunchaku":           Vector2i(96, 34),
	# apparel — row 35
	"samurai_helmet":     Vector2i(89, 35),
	"straw_sandals":      Vector2i(90, 35),
	"kimono":             Vector2i(91, 35),
	"yukata":             Vector2i(92, 35),
	"lamellar_armor":     Vector2i(93, 35),
	"hakama":             Vector2i(94, 35),
	"headband":           Vector2i(95, 35),
	"obi":                Vector2i(96, 35),
	# items — row 36
	"cherry_blossom":     Vector2i(89, 36),
	"paper_lantern":      Vector2i(90, 36),
	"red_lantern":        Vector2i(91, 36),
	"red_fan":            Vector2i(92, 36),
	"white_fan":          Vector2i(93, 36),
	"blue_fan":           Vector2i(94, 36),
	"dark_parasol":       Vector2i(95, 36),
	"pink_parasol":       Vector2i(96, 36),
	# resources — row 37
	"lapis":              Vector2i(89, 37),
	"crystal":            Vector2i(90, 37),
	"golden_orb":         Vector2i(91, 37),
	"bamboo_bracelet":    Vector2i(92, 37),
	"claw_necklace":      Vector2i(93, 37),
	"charm_necklace":     Vector2i(94, 37),
	"tablet_necklace":    Vector2i(95, 37),
	"jade_necklace":      Vector2i(96, 37),
	# tools — row 38
	"chopsticks":         Vector2i(89, 38),
	"chopsticks_crossed": Vector2i(90, 38),
	"rake":               Vector2i(91, 38),
	"hoe":                Vector2i(92, 38),
	# food — row 39
	"sushi":              Vector2i(89, 39),
	"cucumber_roll":      Vector2i(90, 39),
	"sushi_platter":      Vector2i(91, 39),
	"rice_bowl":          Vector2i(92, 39),
	"shrimp":             Vector2i(93, 39),

	# ---- cyberpunk (cols 98..100) — THEME_BANDS flags this band as do-not-use ----
	# weapons — row 34
	"neon_blade":         Vector2i(98, 34),
	"neon_pistol":        Vector2i(99, 34),
	"neon_rifle":         Vector2i(100, 34),
	# resources — row 37
	"neon_chip":          Vector2i(98, 37),
	"credit_chip":        Vector2i(99, 37),
}

## Atlas coord for a named item, or NO_ITEM_TILE when the catalog has no art
## registered for it.
static func item_atlas(item_id: String) -> Vector2i:
	return ITEM_TILES.get(item_id, NO_ITEM_TILE)


static func has_item_tile(item_id: String) -> bool:
	return ITEM_TILES.has(item_id)


## Every id the catalog has art for. Useful for auditing which items still
## need a coord.
static func item_ids() -> Array:
	return ITEM_TILES.keys()

# --- NPC art ---
# Rows 27..33 of the sheet are creatures and people, one 16x16 cell each:
# rows 27..29 animals, 30..32 monsters, 33 people (the far_east band also puts
# people on row 32). Grouped by THEME_BANDS column so a whole theme can be
# pruned at once. A trailing `npc.gd:` note marks coords an NPC profile already
# references — removing one of those orphans that profile's art.
const NO_NPC_TILE := Vector2i(-1, -1)

const NPC_TILES := {
	# ---- medieval_fantasy (cols 4..14) ----
	# animals — row 27
	"chicken":            Vector2i(4, 27),
	"pig":                Vector2i(5, 27),
	"rabbit":             Vector2i(6, 27),
	"crow":               Vector2i(7, 27),
	"bluebird":           Vector2i(8, 27),
	"sparrow":            Vector2i(9, 27),
	"rat":                Vector2i(10, 27),
	"owl":                Vector2i(11, 27),
	"frog":               Vector2i(12, 27),
	"newt":               Vector2i(13, 27),
	# animals — row 28
	"stag":               Vector2i(4, 28),
	"turtle":             Vector2i(5, 28),
	"beetle":             Vector2i(6, 28),
	"grey_spider":        Vector2i(7, 28),
	"crab":               Vector2i(8, 28),
	"worm":               Vector2i(9, 28),
	"snake":              Vector2i(10, 28),
	"red_spider":         Vector2i(11, 28),
	"green_spider":       Vector2i(12, 28),
	"scorpion":           Vector2i(13, 28),
	# animals — row 29
	"boar":               Vector2i(4, 29),
	"unicorn":            Vector2i(5, 29),
	"giant_bee":          Vector2i(6, 29),
	"bat":                Vector2i(7, 29),
	"octopus":            Vector2i(8, 29),
	"bear":               Vector2i(9, 29),
	"crayfish":           Vector2i(10, 29),
	"lizard":             Vector2i(11, 29),
	"moth":               Vector2i(12, 29),
	"fire_drake":         Vector2i(13, 29),
	# monsters — row 30
	"slime":              Vector2i(4, 30),
	"goblin":             Vector2i(5, 30),
	"carnivorous_plant":  Vector2i(6, 30),
	"zombie":             Vector2i(7, 30),
	"mermaid":            Vector2i(8, 30),
	"ghost":              Vector2i(9, 30),
	"mimic":              Vector2i(10, 30),
	"treant":             Vector2i(11, 30),
	"reaper":             Vector2i(12, 30),
	"hellhound":          Vector2i(13, 30),
	# monsters — row 31
	"green_dragon":       Vector2i(4, 31),
	"red_dragon":         Vector2i(5, 31),
	"blue_dragon":        Vector2i(6, 31),
	"skeleton":           Vector2i(7, 31),
	"armored_beetle":     Vector2i(8, 31),
	"water_elemental":    Vector2i(9, 31),
	"beholder":           Vector2i(10, 31),
	"floating_eye":       Vector2i(11, 31),
	"siren":              Vector2i(12, 31),
	"imp":                Vector2i(13, 31),
	# monsters — row 32
	"centaur":            Vector2i(4, 32),
	"orc":                Vector2i(5, 32),   # npc.gd: MONSTER/default
	"minotaur":           Vector2i(6, 32),
	"shadow":             Vector2i(7, 32),
	"frost_troll":        Vector2i(8, 32),
	"ice_elemental":      Vector2i(9, 32),
	"cultist":            Vector2i(10, 32),
	"golem":              Vector2i(11, 32),
	"flaming_skull":      Vector2i(12, 32),
	"fire_elemental":     Vector2i(13, 32),
	# people — row 33
	"archer":             Vector2i(4, 33),   # npc.gd: SOLDIER/archer
	"swordsman":          Vector2i(5, 33),
	"witch":              Vector2i(6, 33),   # npc.gd: MAGE/witch
	"knight":             Vector2i(7, 33),   # npc.gd: SOLDIER/knight
	"blacksmith":         Vector2i(8, 33),   # npc.gd: PEASANT/blacksmith
	"adventurer":         Vector2i(9, 33),
	"white_wizard":       Vector2i(10, 33),  # npc.gd: MAGE/druid
	"battlemage":         Vector2i(11, 33),  # npc.gd: SOLDIER/battlemage
	"trident_warrior":    Vector2i(12, 33),
	"halberdier":         Vector2i(13, 33),
	"rogue":              Vector2i(14, 33),  # sits in the gutter column past the band

	# ---- mediterranean_fantasy (cols 16..19) ----
	# animals — row 27
	"wolf":               Vector2i(16, 27),
	"fox":                Vector2i(17, 27),
	"dog":                Vector2i(18, 27),
	"white_cat":          Vector2i(19, 27),
	# animals — row 28
	"sheep":              Vector2i(16, 28),
	"ram":                Vector2i(17, 28),
	"ladybug":            Vector2i(18, 28),
	"donkey":             Vector2i(19, 28),
	# animals — row 29
	"orange_butterfly":   Vector2i(16, 29),
	"blue_butterfly":     Vector2i(17, 29),
	"red_butterfly":      Vector2i(18, 29),
	# monsters — row 30
	"python":             Vector2i(16, 30),
	"sea_serpent":        Vector2i(17, 30),
	# monsters — row 31
	"wyrm":               Vector2i(16, 31),
	"sea_nymph":          Vector2i(17, 31),
	"harpy":              Vector2i(18, 31),
	# monsters — row 32
	"white_centaur":      Vector2i(16, 32),
	"cyclops":            Vector2i(17, 32),
	"satyr":              Vector2i(18, 32),
	# people — row 33
	"hoplite":            Vector2i(16, 33),  # npc.gd: SOLDIER/default
	"philosopher":        Vector2i(17, 33),  # npc.gd: NOBLE/scholar, CLERGY/priest
	"oracle":             Vector2i(18, 33),
	"priestess":          Vector2i(19, 33),  # npc.gd: CLERGY/priestess

	# ---- alien (cols 23..25) ----
	# animals — row 27
	"alien_horse":        Vector2i(23, 27),
	"alien_beetle":       Vector2i(24, 27),
	"alien_slug":         Vector2i(25, 27),
	# animals — row 28
	"alien_ox":           Vector2i(23, 28),
	"alien_cat":          Vector2i(24, 28),
	"alien_moth":         Vector2i(25, 28),
	# animals — row 29
	"alien_butterfly":    Vector2i(23, 29),
	"alien_jellyfish":    Vector2i(24, 29),
	"alien_worm":         Vector2i(25, 29),
	# monsters — row 30
	"alien_portal":       Vector2i(23, 30),
	"alien_octopus":      Vector2i(24, 30),
	"alien_spider":       Vector2i(25, 30),
	# monsters — row 31
	"grey_alien":         Vector2i(23, 31),
	"green_alien":        Vector2i(24, 31),
	"alien_serpent":      Vector2i(25, 31),
	# monsters — row 32
	"alien_eye":          Vector2i(23, 32),
	"energy_being":       Vector2i(24, 32),
	"alien_brute":        Vector2i(25, 32),
	# people — row 33
	"astronaut":          Vector2i(23, 33),
	"astronaut_striped":  Vector2i(24, 33),
	"astronaut_purple":   Vector2i(25, 33),

	# ---- post_apocalypse (cols 29..32) ----
	# animals — row 27
	"mutant_hound":       Vector2i(29, 27),
	"mutant_bull":        Vector2i(30, 27),
	"mutant_bison":       Vector2i(31, 27),
	"mutant_horse":       Vector2i(32, 27),
	# animals — row 28
	"mutant_snake":       Vector2i(29, 28),
	"mutant_frog":        Vector2i(30, 28),
	"mutant_moth":        Vector2i(31, 28),
	"mutant_wasp":        Vector2i(32, 28),
	# animals — row 29
	"mutant_butterfly":   Vector2i(29, 29),
	"mutant_lizard":      Vector2i(30, 29),
	"mutant_spider":      Vector2i(31, 29),
	"mutant_scorpion":    Vector2i(32, 29),
	# monsters — row 30
	"mutant_drake":       Vector2i(29, 30),
	"radiation_anomaly":  Vector2i(30, 30),
	# monsters — row 31
	"zombie_rotting":     Vector2i(29, 31),
	"zombie_shambler":    Vector2i(30, 31),
	"feral_ghoul":        Vector2i(31, 31),
	# monsters — row 32
	"mutant_brute":       Vector2i(29, 32),
	"mutant_stalker":     Vector2i(30, 32),
	"wasteland_ranger":   Vector2i(31, 32),
	# people — row 33
	"survivor":           Vector2i(29, 33),
	"survivor_woman":     Vector2i(30, 33),
	"scavenger":          Vector2i(31, 33),
	"officer":            Vector2i(32, 33),

	# ---- badlands (cols 41..45) ----
	# animals — row 27
	"armadillo":          Vector2i(41, 27),
	"dodo":               Vector2i(42, 27),
	"mammoth":            Vector2i(43, 27),
	# animals — row 28
	"pink_moth":          Vector2i(41, 28),
	"dragonfly":          Vector2i(42, 28),
	"centipede":          Vector2i(43, 28),
	# animals — row 29
	"sauropod_blue":      Vector2i(41, 29),
	"sauropod_grey":      Vector2i(42, 29),
	"stegosaurus":        Vector2i(43, 29),
	"stegosaurus_blue":   Vector2i(44, 29),
	"triceratops":        Vector2i(45, 29),
	# monsters — row 30
	"crocodile":          Vector2i(41, 30),
	"sabretooth":         Vector2i(42, 30),
	# monsters — row 31
	"raptor_grey":        Vector2i(41, 31),
	"raptor_purple":      Vector2i(42, 31),
	"raptor_blue":        Vector2i(43, 31),
	"raptor_brown":       Vector2i(44, 31),
	"raptor_teal":        Vector2i(45, 31),
	# monsters — row 32
	"pterodactyl_brown":  Vector2i(41, 32),
	"pterodactyl_blue":   Vector2i(42, 32),
	"pterodactyl_purple": Vector2i(43, 32),
	# people — row 33
	"caveman":            Vector2i(41, 33),
	"cavewoman":          Vector2i(42, 33),
	"cave_hunter":        Vector2i(43, 33),
	"cave_gatherer":      Vector2i(44, 33),
	"cave_elder":         Vector2i(45, 33),  # npc.gd: PEASANT/crone

	# ---- world_wars (cols 53..63) ----
	# animals — row 27
	"goose":              Vector2i(53, 27),
	"rooster":            Vector2i(54, 27),
	"mallard":            Vector2i(55, 27),
	# animals — row 28
	"shepherd_dog":       Vector2i(53, 28),
	"saddled_horse":      Vector2i(54, 28),
	# animals — row 29
	"cow":                Vector2i(53, 29),
	"bull":               Vector2i(54, 29),
	# people — row 33
	"rifleman_green":     Vector2i(53, 33),
	"infantry_green":     Vector2i(54, 33),
	"officer_green":      Vector2i(55, 33),
	"rifleman_blue":      Vector2i(56, 33),
	"infantry_blue":      Vector2i(57, 33),
	"officer_blue":       Vector2i(58, 33),
	"dress_uniform":      Vector2i(59, 33),
	"infantry_brown":     Vector2i(60, 33),
	"nurse":              Vector2i(61, 33),  # npc.gd: PEASANT/baker
	"farmer":             Vector2i(62, 33),  # npc.gd: PEASANT/farmer, PEASANT/forester
	"farmer_woman":       Vector2i(63, 33),

	# ---- tropical (cols 65..74) ----
	# animals — row 27
	"parrot_green":       Vector2i(65, 27),
	"parrot_red":         Vector2i(66, 27),
	"iguana":             Vector2i(67, 27),
	"monkey":             Vector2i(68, 27),
	# animals — row 29
	"shark":              Vector2i(65, 29),
	"great_white":        Vector2i(66, 29),
	"hammerhead":         Vector2i(67, 29),
	"shark_fin":          Vector2i(68, 29),
	# monsters — row 30
	"blue_octopus":       Vector2i(65, 30),
	"grey_octopus":       Vector2i(66, 30),
	"moray_eel":          Vector2i(67, 30),
	"mermaid_red":        Vector2i(68, 30),
	# monsters — row 31
	"ghost_jellyfish":    Vector2i(65, 31),
	"ghost_squid":        Vector2i(66, 31),
	"jellyfish":          Vector2i(67, 31),
	"small_jellyfish":    Vector2i(68, 31),
	# monsters — row 32
	"flame_pirate":       Vector2i(65, 32),
	"undead_captain":     Vector2i(66, 32),
	"cursed_sailor":      Vector2i(67, 32),
	"sea_devil":          Vector2i(68, 32),
	# people — row 33
	"pirate_captain":     Vector2i(65, 33),
	"hook_pirate":        Vector2i(66, 33),
	"sailor":             Vector2i(67, 33),
	"deckhand":           Vector2i(68, 33),
	"boatswain":          Vector2i(69, 33),
	"marauder":           Vector2i(70, 33),
	"pirate":             Vector2i(71, 33),  # npc.gd: BANDIT/default
	"buccaneer":          Vector2i(72, 33),
	"naval_officer":      Vector2i(73, 33),
	"corsair":            Vector2i(74, 33),

	# ---- desert_culture (cols 77..82) ----
	# animals — row 27
	"temple_cat":         Vector2i(77, 27),
	"temple_cat_2":       Vector2i(78, 27),
	"black_cat":          Vector2i(79, 27),
	"asp":                Vector2i(80, 27),
	"giant_scarab":       Vector2i(81, 27),
	"gecko":              Vector2i(82, 27),
	# animals — row 28
	"camel":              Vector2i(77, 28),
	"sand_snake":         Vector2i(78, 28),
	"desert_crocodile":   Vector2i(79, 28),
	"cobra":              Vector2i(80, 28),
	# animals — row 29
	"panther":            Vector2i(77, 29),
	"cheetah":            Vector2i(78, 29),
	"lion":               Vector2i(79, 29),
	"hyena":              Vector2i(80, 29),
	# monsters — row 31
	"jackal_god":         Vector2i(77, 31),
	"crocodile_god":      Vector2i(78, 31),
	"ibis_god":           Vector2i(79, 31),
	"falcon_god":         Vector2i(80, 31),
	# monsters — row 32
	"mummy":              Vector2i(77, 32),
	"bee_eater":          Vector2i(78, 32),
	# people — row 33
	"desert_farmer":      Vector2i(77, 33),
	"blue_wizard":        Vector2i(78, 33),  # npc.gd: MAGE/wizard
	"pharaoh":            Vector2i(79, 33),
	"desert_spearman":    Vector2i(80, 33),
	"royal_guard":        Vector2i(81, 33),
	"desert_warrior":     Vector2i(82, 33),

	# ---- far_east (cols 89..96) ----
	# animals — row 27
	"macaque":            Vector2i(89, 27),
	"white_pig":          Vector2i(90, 27),
	"black_rooster":      Vector2i(91, 27),
	# animals — row 28
	"goat":               Vector2i(89, 28),
	"serpent_spirit":     Vector2i(90, 28),
	"pale_cat":           Vector2i(91, 28),
	"orange_cat":         Vector2i(92, 28),  # npc.gd: ANIMAL/default
	# animals — row 29
	"spotted_deer":       Vector2i(89, 29),
	"ox":                 Vector2i(90, 29),
	# monsters — row 30
	"eastern_dragon":     Vector2i(89, 30),
	# people — row 32
	"ninja_black":        Vector2i(89, 32),
	"ninja_white":        Vector2i(90, 32),
	"ninja_red":          Vector2i(91, 32),
	"ninja_blue":         Vector2i(92, 32),
	"samurai_black":      Vector2i(93, 32),
	"samurai_white":      Vector2i(94, 32),
	"samurai_red":        Vector2i(95, 32),
	"samurai_blue":       Vector2i(96, 32),
	# people — row 33
	"geisha":             Vector2i(89, 33),  # npc.gd: MERCHANT/default
	"shrine_maiden":      Vector2i(90, 33),
	"eastern_noble":      Vector2i(91, 33),  # npc.gd: NOBLE/default
	"rice_farmer":        Vector2i(92, 33),  # npc.gd: PEASANT/default, innkeeper, shopkeeper
	"rice_farmer_woman":  Vector2i(93, 33),
	"pilgrim":            Vector2i(94, 33),
	"pilgrim_woman":      Vector2i(95, 33),
	"ronin":              Vector2i(96, 33),

	# ---- cyberpunk (cols 98..108) — THEME_BANDS flags this band as do-not-use ----
	# monsters — row 30
	"spider_drone":       Vector2i(98, 30),
}

## Atlas coord for a named creature or person, or NO_NPC_TILE when the catalog
## has no art registered for it.
static func npc_atlas(npc_id: String) -> Vector2i:
	return NPC_TILES.get(npc_id, NO_NPC_TILE)

# --- prop selection weights ---
# The generator picks props by weight, so "which props show up most" is data
# here rather than logic in map_generator.gd. COMMON marks the small set of
# props that should read as the everyday furniture of a settlement; every other
# prop keeps DEFAULT and therefore shows up as an occasional accent.
const DEFAULT_PROP_WEIGHT := 1.0
const COMMON_PROP_WEIGHT := 8.0

# --- container props ---
# A prop whose override carries a `container` role is not just scenery: the
# generator records the cell it was painted on and ContainerSpawner stands a
# lootable ItemContainer there. The tile itself is painted exactly as any other
# prop, so the container's art and collision keep coming from the tileset.
#   container     : role name, shown to the player and used to pick a loot table
#                   ("chest", "shelf", "barrel", …). Absent or "" = plain scenery.
#   loot_table    : fills it from the "container.<loot_table>" spawn table in
#                   resources/spawn_tables/. Defaults to the role.
#   open_atlas    : coord to repaint the cell with once it has been opened.
#                   Omit for props that have no "open" sprite.
#   locked_chance : 0–1 odds the container starts locked. Defaults to 0.
const NO_CONTAINER := ""

# --- prop roles ---
# What a prop IS ("table", "chair", "shelf", "chest", …), independent of where
# it may stand. Building interiors are furnished by role — see
# MapGenerator.BUILDING_INTERIORS — so a tavern can ask for tables and chairs
# without this file knowing what a tavern is. A prop with no role is only ever
# placed in interiors that take anything.
const NO_ROLE := ""

# --- per-tile overrides (win over the band defaults) ---
# Key is "col,row" (atlas coords). Any subset of keys may be supplied.
# Use `placement` for prop tiles that should only appear in a specific context:
#   "interior" | "exterior" | "both" | "none"
# Props default to "none" (never placed), so listing a tile here is what opts it
# into generation.
# Use `weight` to bias how often a prop is chosen within its pool.
# Use `role` to make a prop eligible for building types that furnish by role.
#   { Vector2i(x, y): {"category": "...", "theme": "...", "walkable": bool, "is_map_tile": bool, "placement": "exterior", "weight": 8.0} }
const OVERRIDES := {
	# TODO: get more granular with placement for props, so the local scene generator can avoid putting a tree in a house.
	# Firepits + water well: the common exterior props.
	Vector2i(4, 22): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(5, 22): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(6, 22): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},

	# Bookshelf → empty pot: the common interior props.
	Vector2i(4, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"role": "shelf",
		"container": "shelf", 
		"loot_table": "household"
		},
	Vector2i(5, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"role": "shelf",
		"container": "cupboard", 
		"loot_table": "household"
		},	
	Vector2i(6, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "chair"},
	Vector2i(7, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "table"},
	Vector2i(8, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"role": "chest",
		"container": "chest", 
		"loot_table": "household"
		},
	Vector2i(9, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "chest"},
	Vector2i(10, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"role": "chest",
		"container": "chest", 
		"loot_table": "household"
		},
	Vector2i(11, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "chest"},
	Vector2i(12, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "plant"},
	Vector2i(13, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT, "role": "pot"},

	# Signposts: common exterior props.
	Vector2i(9, 25): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(10, 25): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(11, 25): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},

	# Graves: common exterior props.
	Vector2i(10, 26): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(11, 26): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(12, 26): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(13, 26): {"placement": "exterior", "weight": COMMON_PROP_WEIGHT},
	# Add tile coords here as you classify each prop.
}

# ---------------------------------------------------------------------------
# lookup helpers (used by the stamper and, later, the map generator)
# ---------------------------------------------------------------------------

static func theme_for_col(col: int) -> String:
	for band in THEME_BANDS:
		if col >= band.cols[0] and col <= band.cols[1]:
			return band.theme
	return ""

static func category_band_for_row(row: int) -> Dictionary:
	for band in CATEGORY_BANDS:
		if row >= band.rows[0] and row <= band.rows[1]:
			return band
	return {}

## Full resolved metadata for an atlas coord, or {} if the cell is skipped
## (label strip, banner, gutter row/col, or an unmapped area).
static func resolve(coord: Vector2i) -> Dictionary:
	var theme := theme_for_col(coord.x)
	var band := category_band_for_row(coord.y)
	if theme.is_empty() or band.is_empty():
		return {}
	var data := {
		"category": band.category,
		"theme": theme,
		"biome": biome_for(coord, theme, band.category),
		"walkable": band.walkable,
		"is_map_tile": band.is_map_tile,
		"local_gen": band.local_gen,
		"use_alpha": band.get("use_alpha", false),
		"placement": band.get("placement", "both"),
		"weight": band.get("weight", DEFAULT_PROP_WEIGHT),
		"role": band.get("role", NO_ROLE),
		# Container fields are declared here (rather than only in OVERRIDES) so
		# every resolved tile has the same shape and callers can read them without
		# guarding. A role of "" means the prop is scenery.
		"container": band.get("container", NO_CONTAINER),
		"loot_table": band.get("loot_table", ""),
		"locked_chance": band.get("locked_chance", 0.0),
	}
	if OVERRIDES.has(coord):
		data.merge(OVERRIDES[coord], true)
	return data


## True when the tile at `coord` should carry a lootable container.
static func is_container(coord: Vector2i) -> bool:
	var meta := resolve(coord)
	return String(meta.get("container", NO_CONTAINER)) != NO_CONTAINER
