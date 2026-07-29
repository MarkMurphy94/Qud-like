@tool
extends RefCounted
class_name RoguelikeTileCatalog

## Builds MapGenerator's tile_catalog from the declarative bands in
## resources/tileset_layout.gd, so the Backterria roguelike master sheet can
## drive local-map generation without every tile being hand-stamped in the
## TileSet inspector.
##
## MapGenerator indexes tiles as tile_catalog[category][type]. The band table
## only knows one category per atlas row, so CATEGORY_ROUTING translates a band
## category into the (category, type) pair the generator asks for. Anything not
## routed here is invisible to the generator.
##
## Every entry carries its `theme` ("medieval_fantasy", "far_east", …) so one catalog
## covers the whole sheet and callers filter down at pick time.

const Layout := preload("res://resources/tileset_layout.gd")

## Band category → where MapGenerator looks for it.
const CATEGORY_ROUTING := {
	"tree":     {"category": "foliage",          "type": "tree"},
	"bush":     {"category": "foliage",          "type": "bush"},
	"plant":    {"category": "foliage",          "type": "plant"},
	"grass":    {"category": "terrain_features", "type": "grass"},
	"rock":     {"category": "terrain_features", "type": "rock"},
	"farm":     {"category": "terrain_features", "type": "farm"},
	"ground":   {"category": "surface",          "type": "ground"},
	# Row 10's coarse ground cut is never a base surface — it is scattered over
	# one by add_terrain_features, so it routes to the feature layer instead.
	"ground_detail": {"category": "terrain_features", "type": "ground_detail"},
	"road":     {"category": "road",          "type": "road"},
	"liquid":   {"category": "surface",          "type": "water"},
	"mountain": {"category": "surface",          "type": "mountain"},
	"wall":     {"category": "structure",        "type": "wall"},
	"door":     {"category": "structure",        "type": "door"},
	"building": {"category": "structure",        "type": "building"},
	"prop":     {"category": "decor_exterior",   "type": "prop"},
}

## MapGenerator's ground-surface names → the catalog (category, type) they
## paint from.
##
## The old tileset autotiled these through terrain sets; the roguelike sheet has
## no terrain sets, so surfaces are painted cell by cell from these pools. The
## pair must match CATEGORY_ROUTING above — a surface is not always routed into
## the "surface" category (the coarse ground cut and farm rows land in
## "terrain_features"), and naming only the type silently yields an empty pool.
## NOTE: "grass" and "dirt" both resolve to the `ground` band because the band
## table has no column sub-bands yet — until tileset_layout.gd grows them (see
## its climate/biome TODO) the two surfaces are visually identical.
const TERRAIN_SURFACES := {
	"grass":       {"category": "surface",          "type": "ground"},
	"dirt":        {"category": "surface",          "type": "ground"},
	"stone":       {"category": "terrain_features", "type": "ground_detail"},
	"water":       {"category": "surface",          "type": "water"},
	"wheat_field": {"category": "terrain_features", "type": "farm"},
}

## Catalog (category, type) a named ground surface paints from. Unknown names
## fall back to plain ground so a typo paints something rather than nothing.
static func surface_route(surface: String) -> Dictionary:
	return TERRAIN_SURFACES.get(surface, {"category": "surface", "type": "ground"})

## Themes are laid out in columns; this is the one this game paints with.
const DEFAULT_THEME := "medieval_fantasy"

## Default building shell. Generated buildings draw their wall ring from this
## directional set of medieval_fantasy wall tiles, and pave their interior
## with DEFAULT_FLOOR_ATLAS.
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
const DEFAULT_FLOOR_ATLAS := Vector2i(66, 10)


## Build the full catalog for every atlas source in `ts` whose texture the band
## table describes. Returns tile_catalog[category][type] = Array[entry], where
## an entry matches the shape MapGenerator's paint code already expects.
##
## The sheet is present twice — an opaque cut and a transparent one — at
## identical atlas coordinates. A band's `use_alpha` decides which cut it is
## drawn from, and each coordinate is emitted exactly once so a pool never
## contains both versions of the same tile.
static func build(ts: TileSet) -> Dictionary:
	var catalog: Dictionary = {}
	if ts == null:
		return catalog

	var opaque_id := opaque_source_id(ts)
	var alpha_id := alpha_source_id(ts)

	for i in ts.get_source_count():
		var source_id := ts.get_source_id(i)
		var source := ts.get_source(source_id)
		if not source is TileSetAtlasSource:
			continue
		var atlas := source as TileSetAtlasSource

		for t in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(t)
			var meta := Layout.resolve(coords)
			if meta.is_empty():
				continue
			# Entity/item sprites are spawned as scenes, never painted; world-only
			# art (mountains, whole-building glyphs) must not land in a local map.
			if not meta.get("is_map_tile", false) or not meta.get("local_gen", false):
				continue
			var route: Dictionary = CATEGORY_ROUTING.get(meta.category, {})
			if route.is_empty():
				continue

			# Let the preferred cut claim this coordinate. Skipping only when it
			# actually holds the tile means a gap in one sheet falls back to the
			# other rather than dropping the tile from the catalog entirely.
			var preferred := alpha_id if meta.get("use_alpha", false) else opaque_id
			if source_id != preferred and _source_has(ts, preferred, coords):
				continue

			var category: String = route.category
			var tile_type: String = route.type
			if not catalog.has(category):
				catalog[category] = {}
			if not catalog[category].has(tile_type):
				catalog[category][tile_type] = []
			catalog[category][tile_type].append({
				"source_id": source_id,
				"atlas": coords,
				"size": atlas.get_tile_size_in_atlas(coords),
				"theme": meta.theme,
				# "" for tiles that look the same in every environment.
				"biome": meta.get("biome", ""),
				"walkable": meta.walkable,
				"placement": meta.get("placement", "both"),
				# How strongly this tile is favoured when a prop pool is sampled.
				"weight": meta.get("weight", Layout.DEFAULT_PROP_WEIGHT),
				# Kept so entries stay shape-compatible with the custom-data
				# catalog MapGenerator builds for the older tilesets.
				"subtype": "",
				"building_id": "",
				"tags": [],
				"interior": false,
				"associated_buildings": [],
				"affiliations": [],
				"classes": [],
				"cultures": [],
				"climates": [],
				"biomes": [],
			})
	return catalog


## Atlas source drawing the transparent cut of the sheet, or -1 if the tileset
## has no such source.
static func alpha_source_id(ts: TileSet) -> int:
	return _find_source(ts, true)


## Atlas source drawing the opaque cut of the sheet, or -1 if there is none.
static func opaque_source_id(ts: TileSet) -> int:
	return _find_source(ts, false)


static func _find_source(ts: TileSet, want_alpha: bool) -> int:
	if ts == null:
		return -1
	for i in ts.get_source_count():
		var source_id := ts.get_source_id(i)
		var source := ts.get_source(source_id)
		if not source is TileSetAtlasSource:
			continue
		var texture: Texture2D = (source as TileSetAtlasSource).texture
		if texture == null:
			continue
		if Layout.is_alpha_texture(texture.resource_path.get_file()) == want_alpha:
			return source_id
	return -1


## Does atlas source `source_id` actually define a tile at `coords`?
static func _source_has(ts: TileSet, source_id: int, coords: Vector2i) -> bool:
	if source_id == -1:
		return false
	var source := ts.get_source(source_id)
	if not source is TileSetAtlasSource:
		return false
	return (source as TileSetAtlasSource).has_tile(coords)


## Narrow a pool to one theme. Falls back to the unfiltered pool when the theme
## has no art for that tile type, so a missing column never leaves a map blank.
static func of_theme(entries: Array, theme: String = DEFAULT_THEME) -> Array:
	var matched: Array = []
	for entry in entries:
		if entry.get("theme", "") == theme:
			matched.append(entry)
	return matched if not matched.is_empty() else entries


## Narrow a pool to one biome, keeping biome-neutral tiles (walls, doors, props)
## since those are correct everywhere. Falls back to the unfiltered pool when the
## biome has no art for that tile type. An empty `biome` disables the filter.
static func of_biome(entries: Array, biome: String) -> Array:
	if biome.is_empty():
		return entries
	var matched: Array = []
	for entry in entries:
		var entry_biome: String = entry.get("biome", "")
		if entry_biome == biome or entry_biome.is_empty():
			matched.append(entry)
	return matched if not matched.is_empty() else entries


## Resolve DEFAULT_WALL_TILES against a wall pool: role ("nw", "n", …) →
## catalog entry. A role whose atlas coord is missing from the pool falls back
## to the pool's first entry so a wall ring is never left with holes; returns
## {} only when the pool itself is empty.
static func default_wall_entries(entries: Array) -> Dictionary:
	if entries.is_empty():
		return {}
	var out: Dictionary = {}
	for role in DEFAULT_WALL_TILES:
		var entry := entry_at(entries, DEFAULT_WALL_TILES[role])
		if entry.is_empty():
			push_warning("RoguelikeTileCatalog: default wall tile %s for '%s' not in catalog"
				% [DEFAULT_WALL_TILES[role], role])
			entry = entries[0]
		out[role] = entry
	return out


## The entry in `entries` at atlas coordinate `coords`, or {} if absent.
static func entry_at(entries: Array, coords: Vector2i) -> Dictionary:
	for entry in entries:
		if entry.get("atlas", Vector2i(-1, -1)) == coords:
			return entry
	return {}


## True when `ts` describes the roguelike master sheet, i.e. when at least one
## atlas source uses a texture the band table was written against. This is what
## MapGenerator switches on to pick a catalog strategy.
static func describes(ts: TileSet) -> bool:
	if ts == null:
		return false
	for i in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(i))
		if not source is TileSetAtlasSource:
			continue
		var texture: Texture2D = (source as TileSetAtlasSource).texture
		if texture == null:
			continue
		# Every cut of the sheet — opaque, alpha, edited, or the merged overworld
		# version with extra rows appended — shares the same 109-column band
		# layout, so any of them means the band table applies.
		if "roguelike" in texture.resource_path.get_file().to_lower():
			return true
	return false
