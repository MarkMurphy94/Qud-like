@tool
extends EditorScript

## Stamps custom-data-layer metadata onto the Backterria master tileset from the
## declarative bands in resources/tileset_layout.gd -- instead of hand-clicking
## thousands of tiles in the TileSet inspector.
##
## HOW TO RUN
##   1. Open this file in the Godot script editor.
##   2. File > Run  (Ctrl+Shift+X).
##   3. Read the report in the Output panel.
##
## WORKFLOW
##   - Leave DRY_RUN = true first. Nothing is written; you get an annotated
##     occupancy map + per-row assignment so you can check the row bands against
##     the sheet. Tune CATEGORY_BANDS in tileset_layout.gd and re-run until the
##     labels line up.
##   - Set DRY_RUN = false to write the four custom-data layers and save the tres.
##
## It is idempotent: re-running re-stamps from the current table, so you can
## iterate freely (and re-stamp after any future tileset image update).

const Layout := preload("res://resources/tileset_layout.gd")
const TILESET_PATH := "res://resources/the_roguelike.tres"

# Flip to false to actually write + save.
const DRY_RUN := false

# custom-data layers this tool manages: name -> Variant.Type
const LAYERS := {
	"category":    TYPE_STRING,
	"theme":       TYPE_STRING,
	"walkable":    TYPE_BOOL,
	"is_map_tile": TYPE_BOOL,
	"local_gen":   TYPE_BOOL,
}

func _run() -> void:
	var ts: TileSet = load(TILESET_PATH)
	if ts == null:
		push_error("[stamp] could not load %s" % TILESET_PATH)
		return

	var source := _find_source(ts)
	if source == null:
		push_error("[stamp] no atlas source whose texture is '%s'" % Layout.TEXTURE_BASENAME)
		return

	if not DRY_RUN:
		_ensure_layers(ts)

	# assignment tallies
	var per_category := {}   # category -> count
	var per_theme := {}      # theme -> count
	var stamped := 0
	var skipped := 0

	var tile_count := source.get_tiles_count()
	for i in tile_count:
		var coord := source.get_tile_id(i)
		var meta := Layout.resolve(coord)
		if meta.is_empty():
			skipped += 1
			continue
		per_category[meta.category] = per_category.get(meta.category, 0) + 1
		per_theme[meta.theme] = per_theme.get(meta.theme, 0) + 1
		if not DRY_RUN:
			var td := source.get_tile_data(coord, 0)
			td.set_custom_data("category", meta.category)
			td.set_custom_data("theme", meta.theme)
			td.set_custom_data("walkable", meta.walkable)
			td.set_custom_data("is_map_tile", meta.is_map_tile)
			td.set_custom_data("local_gen", meta.local_gen)
		stamped += 1

	_print_report(per_category, per_theme, stamped, skipped, tile_count)

	if DRY_RUN:
		print("\n[stamp] DRY_RUN -- nothing written. Set DRY_RUN = false to apply.")
		return

	var err := ResourceSaver.save(ts, TILESET_PATH)
	if err != OK:
		push_error("[stamp] save failed: %d" % err)
	else:
		print("\n[stamp] wrote metadata to %s" % TILESET_PATH)

# --- tileset plumbing -------------------------------------------------------

func _find_source(ts: TileSet) -> TileSetAtlasSource:
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		if src is TileSetAtlasSource and src.texture != null:
			if src.texture.resource_path.get_file() == Layout.TEXTURE_BASENAME:
				return src
	return null

func _ensure_layers(ts: TileSet) -> void:
	for name in LAYERS:
		var idx := ts.get_custom_data_layer_by_name(name)
		if idx == -1:
			idx = ts.get_custom_data_layers_count()
			ts.add_custom_data_layer()
			ts.set_custom_data_layer_name(idx, name)
		ts.set_custom_data_layer_type(idx, LAYERS[name])

# --- reporting --------------------------------------------------------------

func _print_report(per_category: Dictionary, per_theme: Dictionary, stamped: int, skipped: int, total: int) -> void:
	print("=== stamp_roguelike_metadata  (DRY_RUN=%s) ===" % DRY_RUN)
	print("tiles: %d total  |  %d stamped  |  %d skipped (label/banner/gutter)" % [total, stamped, skipped])

	print("\n-- row -> category assignment (verify against the sheet) --")
	for row in range(Layout.GRID_ROWS):
		var band: Dictionary = Layout.category_band_for_row(row)
		if band.is_empty():
			continue
		if band.rows[0] == row:
			var tag := ""
			if not band.is_map_tile:
				tag = "   (entity/item sprite -- excluded from map catalog)"
			elif not band.local_gen:
				tag = "   (world art -- not for local scene gen)"
			print("  rows %2d-%2d : %-14s walkable=%s%s" % [band.rows[0], band.rows[1], band.category, band.walkable, tag])

	print("\n-- tiles per category --")
	for cat in per_category:
		print("  %-14s %d" % [cat, per_category[cat]])

	print("\n-- tiles per theme --")
	for theme in per_theme:
		print("  %-16s %d" % [theme, per_theme[theme]])
