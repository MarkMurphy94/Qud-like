extends RefCounted
class_name AuthoredPlaces

## Every hand-authored location, found by scanning PLACES_DIR for MapConfig
## .tres files (the ItemDatabase pattern: drop a file in, no registry to edit).
## A config claims the overworld tile in its overworld_tile field; when the
## player enters that tile, MapGenerator builds the authored layout instead of
## generating one, and BespokePlaceProvider describes it as a Place.

const PLACES_DIR := "res://resources/places/"

static var _by_tile: Dictionary = {}  # Vector2i -> MapConfig
static var _loaded := false


static func for_tile(tile: Vector2i) -> MapConfig:
	_ensure_loaded()
	return _by_tile.get(tile)


static func all() -> Array:
	_ensure_loaded()
	return _by_tile.values()


## Claim a tile without a file on disk — for tests and debug tools. Undone by
## reload().
static func register(config: MapConfig) -> void:
	_ensure_loaded()
	_by_tile[config.overworld_tile] = config


static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_tile.clear()
	var dir := DirAccess.open(PLACES_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		# Exported builds list "x.tres.remap"; load() resolves the remap itself.
		var res_name := file_name.trim_suffix(".remap")
		if not res_name.ends_with(".tres"):
			continue
		var path := PLACES_DIR + res_name
		var config := load(path) as MapConfig
		if config == null:
			push_warning("[AuthoredPlaces] %s is not a MapConfig — skipping" % path)
			continue
		if config.overworld_tile == Vector2i.ZERO:
			push_warning("[AuthoredPlaces] %s has no overworld_tile — skipping" % path)
			continue
		if _by_tile.has(config.overworld_tile):
			push_warning("[AuthoredPlaces] %s and %s both claim tile %s — keeping the first" % [
				(_by_tile[config.overworld_tile] as MapConfig).resource_path, path, config.overworld_tile])
			continue
		_by_tile[config.overworld_tile] = config
