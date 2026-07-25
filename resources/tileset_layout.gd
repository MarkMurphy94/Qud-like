@tool
extends RefCounted
class_name RoguelikeTilesetLayout

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

# --- alpha variant ---
# The sheet also ships with a transparent-background cut. Tiles that sit on top
# of something else (foliage, props, walls) must come from that source or their
# opaque background punches a hole in the ground beneath them; flat ground tiles
# want the opaque cut. Which cut a band uses is the "use_alpha" key below.
## Matched against an atlas source's texture file name to find that cut.
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

# --- BIOME column sub-bands --- CONFIRMED
# Inside the medieval_fantasy block each of the ten columns is one biome: the
# same tile role (a tree, a patch of ground) drawn for ten environments. That is
# a finer split than THEME_BANDS, which treats the whole block as one theme.
#
# Only the categories in BIOME_CATEGORIES vary this way. A wall, door or prop is
# biome-neutral — it looks the same in a swamp as on a steppe — and resolves to
# an empty biome, as does every theme outside the fantasy block.
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
const BIOME_CATEGORIES: Array[String] = ["tree", "grass", "plant", "bush", "rock", "ground"]

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
	{"category": "ground",   "rows": [9, 10],  "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": false},
	{"category": "road",     "rows": [11, 11], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "rail",     "rows": [12, 12], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "liquid",   "rows": [13, 13], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "mountain", "rows": [14, 14], "walkable": false, "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "farm",     "rows": [15, 16], "walkable": true,  "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "building", "rows": [17, 18], "walkable": false, "is_map_tile": true,  "local_gen": false, "world_map": true, "use_alpha": true},
	{"category": "wall",     "rows": [19, 20], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "door",     "rows": [21, 21], "walkable": true,  "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	{"category": "prop",     "rows": [22, 26], "walkable": false, "is_map_tile": true,  "local_gen": true, "world_map": true, "use_alpha": true},
	# --- TODO rows 27+ : animals, monsters, heroes, and inventory sprites. Excluded from
	# the map tile catalog (spawned as entities / held as items, not painted). Sub-split
	# into animal/monster/hero bands later if themed entity selection is wanted.
	{"category": "entity_sprite", "rows": [27, 43], "walkable": true, "is_map_tile": false, "local_gen": false},
]

# --- per-tile overrides (win over the band defaults) ---
# Key is "col,row" (atlas coords). Any subset of keys may be supplied.
#   { Vector2i(x, y): {"category": "...", "theme": "...", "walkable": bool, "is_map_tile": bool} }
const OVERRIDES := {
	# e.g. Vector2i(37, 21): {"walkable": true},   # a bridge tile over water
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
	}
	if OVERRIDES.has(coord):
		data.merge(OVERRIDES[coord], true)
	return data
