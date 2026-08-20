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

## Flooring laid inside a generated building, and the named materials a
## BUILDING_SPRITES entry can ask for instead.
const DEFAULT_FLOOR_ATLAS := Vector2i(66, 10)

const FLOOR_TILES := {
	"dark_wood": Vector2i(66, 10),
	"stone_floor": Vector2i(5, 10),
	"dirt": Vector2i(5, 9),
}

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
#   loot_table    : ItemGenerator loot table that fills it. Defaults to the role.
#   open_atlas    : coord to repaint the cell with once it has been opened.
#                   Omit for props that have no "open" sprite.
#   locked_chance : 0–1 odds the container starts locked. Defaults to 0.
const NO_CONTAINER := ""

# --- per-tile overrides (win over the band defaults) ---
# Key is "col,row" (atlas coords). Any subset of keys may be supplied.
# Use `placement` for prop tiles that should only appear in a specific context:
#   "interior" | "exterior" | "both" | "none"
# Props default to "none" (never placed), so listing a tile here is what opts it
# into generation.
# Use `weight` to bias how often a prop is chosen within its pool.
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
		"container": "shelf", 
		"loot_table": "household"
		},
	Vector2i(5, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"container": "cupboard", 
		"loot_table": "household"
		},	
	Vector2i(6, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(7, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(8, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"container": "chest", 
		"loot_table": "household"
		},
	Vector2i(9, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(10, 24): {
		"placement": "interior", 
		"weight": COMMON_PROP_WEIGHT,
		"container": "chest", 
		"loot_table": "household"
		},
	Vector2i(11, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(12, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},
	Vector2i(13, 24): {"placement": "interior", "weight": COMMON_PROP_WEIGHT},

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
