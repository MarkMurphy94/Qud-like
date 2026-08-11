extends Node2D
class_name FactionMap

# region NOTES:
## The organisations on the overworld — who leans on what land, and who
## actually holds it.
##
## Factions grow the way provinces and cultures do, through the shared flood in
## region_growth.gd, seeded from hand-authored seats. That flood produces the
## area of INFLUENCE: everywhere a faction's money, priests, cousins or threats
## reach, borders be damned.
##
## Ruled land is not grown at all. A faction rules a province when that
## province's `ruling_faction` matches its `faction_id`, so the two maps stay in
## step by construction and only ProvinceMap has to be saved. Because of that
## this node has to build after ProvinceMap, and has to be told when ownership
## changes in play — call refresh_rule().
##
## The overlay draws both at once: ruled land solid, influence as a pale haze
## around it, so a faction reads as a bright core in a wide fog.
##
## USAGE
##   1. Make a .tres of resources/faction.gd, set `display_name`, `seat_tile`
##      and `faction_type`, optionally `starting_provinces` and `liege`.
##   2. Add it to this node's `faction_defs` array. Array order assigns ids.
##   3. faction_at(tile) / ruler_at(tile) / influence_at(tile)
##      top_liege(key) / vassals_of(key) / realm_of(key)
##      toggle_overlay()  — faction map on/off, bound to "toggle_factions"
# endregion

const FactionDef := preload("res://resources/faction.gd")
const Growth = preload("res://scripts/alternate_mode/region_growth.gd")

const NO_FACTION := Growth.NO_REGION

## Above provinces and cultures — this is the overlay with the most to say.
const OVERLAY_Z := 101

## Province.ruling_faction's default, and so the value that means "up for grabs".
const UNCLAIMED := "unclaimed"

@export_group("Overlay")
## Land a faction merely influences. Deliberately faint — this is a rumour of
## power, not a border.
@export_range(0.0, 1.0) var overlay_alpha: float = 0.16
## Land a faction actually rules.
@export_range(0.0, 1.0) var rule_alpha: float = 0.45
@export_range(0.0, 1.0) var border_alpha: float = 0.85
@export var overlay_visible_on_start: bool = false

@export_group("Authoring")
@export var faction_defs: Array[Faction] = []
## Give a legitimate faction that lists no `starting_provinces` the province its
## seat stands in. Without this the political map opens entirely unclaimed,
## which is only what you want if provinces are meant to be won from scratch.
@export var seat_claims_province: bool = true

## Working copies of the authored .tres files, indexed by id, so build-time
## fields never write back to disk.
var factions: Array[FactionDef] = []

## Untyped so the calls below resolve against the real APIs rather than Node2D's.
var _world_map = null
var _provinces = null
var _overlay: Sprite2D = null

var _origin: Vector2i = Vector2i.ZERO
var _w: int = 0
var _h: int = 0
## Faction id per cell from the influence flood.
var _influence := PackedInt32Array()
## Faction id per cell derived from province ownership.
var _ruled := PackedInt32Array()
## faction_id → index, so the per-tile rule lookup is not a linear scan.
var _by_key: Dictionary = {}


func _ready() -> void:
	_overlay = Growth.make_overlay_sprite(OVERLAY_Z, overlay_visible_on_start)
	add_child(_overlay)


# ═══════════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════════

## Called from qud_like_world_map._ready(), after provinces — ruled territory is
## read straight off them.
func build(map) -> void:
	_world_map = map
	_provinces = map.get_node_or_null("provinces")
	factions.clear()
	_by_key.clear()
	_influence = PackedInt32Array()
	_ruled = PackedInt32Array()

	var bounds: Rect2i = map.bounds
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_warning("[Factions] World map has no painted extent — nothing to claim.")
		return
	_origin = bounds.position
	_w = bounds.size.x
	_h = bounds.size.y

	var started := Time.get_ticks_msec()
	var seats := _collect_seats()
	if seats.is_empty():
		print("[Factions] No factions defined — faction map is empty.")
		return

	var reach := PackedInt32Array()
	for faction in factions:
		reach.append(faction.effective_influence())

	var cost := Growth.build_cost_field(map, _origin, _w, _h)
	_influence = Growth.grow(seats, reach, cost, _origin, _w, _h)
	_resolve_vassalage()
	_claim_provinces()
	refresh_rule()

	print("[Factions] %d factions influencing %d land tiles, ruling %d, in %d ms"
		% [factions.size(), _total(false), _total(true), Time.get_ticks_msec() - started])


## Rebuild everything that follows from province ownership. Call this after a
## province changes hands, or after loading a save.
func refresh_rule() -> void:
	_build_rule_map()
	_count_tiles()
	refresh_overlay()


## Fills `factions` with validated working copies and returns their seats, so
## ids, seats and reach all stay in the same order.
func _collect_seats() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for def: Resource in faction_defs:
		if def == null:
			continue
		if not (def is FactionDef):
			push_warning("[Factions] '%s' is not a Faction resource — skipped." % def.resource_path)
			continue
		var faction := (def as FactionDef).duplicate() as FactionDef
		# A seat in the sea would seed nothing and shift every later id, so it is
		# dropped here rather than quietly producing a faction with no reach.
		if not _world_map.is_land(faction.seat_tile):
			push_warning("[Factions] '%s' has its seat_tile %s on water or off the map — skipped."
				% [faction.display_name, faction.seat_tile])
			continue
		faction.id = factions.size()
		if faction.display_name == "":
			faction.display_name = "Faction %d" % faction.id
		if faction.faction_id == "":
			faction.faction_id = _slug(faction.display_name)
		# Duplicate keys would make province ownership ambiguous, since that is
		# matched on the key rather than the id.
		if _by_key.has(faction.faction_id):
			push_warning("[Factions] '%s' reuses faction_id '%s' — skipped."
				% [faction.display_name, faction.faction_id])
			continue
		if faction.color == Color.WHITE:
			faction.color = Growth.generated_color(faction.id, 0.70, 0.90)
		_by_key[faction.faction_id] = faction.id
		factions.append(faction)
		out.append(faction.seat_tile)
	return out


## "House Auberne" → "house_auberne".
func _slug(text: String) -> String:
	var slug := ""
	for character in text.to_lower():
		if (character >= "a" and character <= "z") or character.is_valid_int():
			slug += character
		elif slug != "" and not slug.ends_with("_"):
			slug += "_"
	return slug.trim_suffix("_")


## Drop fealty that cannot be honoured, so every later walk up a liege chain is
## guaranteed to reach a top.
func _resolve_vassalage() -> void:
	for faction in factions:
		if faction.liege == "":
			continue
		if not faction.is_feudal():
			push_warning("[Factions] '%s' is a %s and cannot swear fealty — liege cleared."
				% [faction.display_name, faction.type_name()])
			faction.liege = ""
			continue
		var liege := find_by_key(faction.liege)
		if liege == null:
			push_warning("[Factions] '%s' is sworn to '%s', which does not exist — liege cleared."
				% [faction.display_name, faction.liege])
			faction.liege = ""
		elif liege == faction:
			push_warning("[Factions] '%s' is sworn to itself — liege cleared." % faction.display_name)
			faction.liege = ""
		elif not liege.is_feudal():
			push_warning("[Factions] '%s' is sworn to '%s', which is a %s and takes no vassals — liege cleared."
				% [faction.display_name, liege.display_name, liege.type_name()])
			faction.liege = ""
	# A ring of fealty would make top_liege() walk forever, so break it at
	# whichever faction is found able to reach itself.
	for faction in factions:
		if _in_liege_cycle(faction):
			push_warning("[Factions] '%s' sits in a circle of fealty — liege cleared."
				% faction.display_name)
			faction.liege = ""


func _in_liege_cycle(faction: FactionDef) -> bool:
	var seen: Dictionary = {faction.faction_id: true}
	var current := liege_of(faction.faction_id)
	while current != null:
		if seen.has(current.faction_id):
			return true
		seen[current.faction_id] = true
		current = liege_of(current.faction_id)
	return false


## Hand out the opening political position. Ownership after this belongs to
## ProvinceMap and the save file.
func _claim_provinces() -> void:
	if _provinces == null:
		return
	for faction in factions:
		for tile: Vector2i in faction.starting_provinces:
			var province = _provinces.province_for_tile(tile)
			if province == null:
				push_warning("[Factions] '%s' claims a province at %s, where there is none."
					% [faction.display_name, tile])
				continue
			province.ruling_faction = faction.faction_id
	if not seat_claims_province:
		return
	for faction in factions:
		if not faction.starting_provinces.is_empty() or not faction.rules_legitimately():
			continue
		var province = _provinces.province_for_tile(faction.seat_tile)
		if province and province.ruling_faction == UNCLAIMED:
			province.ruling_faction = faction.faction_id


## Paint province ownership down to tiles, so a ruler can be looked up the same
## way influence is.
func _build_rule_map() -> void:
	_ruled = PackedInt32Array()
	if _provinces == null or _w <= 0 or _h <= 0:
		return
	_ruled.resize(_w * _h)
	_ruled.fill(NO_FACTION)
	# Resolved once per province rather than once per tile — the key behind a
	# province does not change across its territory.
	var holder: Dictionary = {}
	for y in _h:
		for x in _w:
			var province_id := int(_provinces.province_at(_origin + Vector2i(x, y)))
			if province_id < 0:
				continue
			if not holder.has(province_id):
				var province = _provinces.get_province(province_id)
				holder[province_id] = index_of(province.ruling_faction) if province else NO_FACTION
			_ruled[y * _w + x] = int(holder[province_id])


func _count_tiles() -> void:
	var influenced := Growth.count_tiles(_influence, factions.size())
	var ruled := Growth.count_tiles(_ruled, factions.size())
	for i in factions.size():
		factions[i].influence_tiles = influenced[i]
		factions[i].ruled_tiles = ruled[i]


func _total(ruled: bool) -> int:
	var sum := 0
	for faction in factions:
		sum += faction.ruled_tiles if ruled else faction.influence_tiles
	return sum


# ═══════════════════════════════════════════════════════════════════════
#  QUERIES
# ═══════════════════════════════════════════════════════════════════════

func _index(tile: Vector2i) -> int:
	return (tile.y - _origin.y) * _w + (tile.x - _origin.x)


func _in_grid(tile: Vector2i) -> bool:
	var x := tile.x - _origin.x
	var y := tile.y - _origin.y
	return x >= 0 and y >= 0 and x < _w and y < _h


## Whose reach covers this tile, ruled or not.
func influence_at(tile: Vector2i) -> int:
	if _influence.is_empty() or not _in_grid(tile):
		return NO_FACTION
	return _influence[_index(tile)]


## Who actually holds this tile, or NO_FACTION on unclaimed land, sea and void.
func ruler_at(tile: Vector2i) -> int:
	if _ruled.is_empty() or not _in_grid(tile):
		return NO_FACTION
	return _ruled[_index(tile)]


## The faction that matters here: whoever rules it, or failing that whoever's
## shadow it sits in.
func faction_at(tile: Vector2i) -> int:
	var ruler := ruler_at(tile)
	return ruler if ruler != NO_FACTION else influence_at(tile)


func get_faction(id: int) -> FactionDef:
	return factions[id] if id >= 0 and id < factions.size() else null


func faction_for_tile(tile: Vector2i) -> FactionDef:
	return get_faction(faction_at(tile))


func ruler_for_tile(tile: Vector2i) -> FactionDef:
	return get_faction(ruler_at(tile))


func faction_id_at(tile: Vector2i) -> String:
	var faction := faction_for_tile(tile)
	return faction.faction_id if faction else ""


func find_by_key(key: String) -> FactionDef:
	return get_faction(index_of(key))


func index_of(key: String) -> int:
	return int(_by_key.get(key, NO_FACTION))


func factions_of_type(type: int) -> Array[FactionDef]:
	var out: Array[FactionDef] = []
	for faction in factions:
		if faction.faction_type == type:
			out.append(faction)
	return out


## True where a gang or a rebellion is the one holding the province — violence,
## no output, peasants leaving.
func is_failed_state(tile: Vector2i) -> bool:
	var ruler := ruler_for_tile(tile)
	return ruler != null and ruler.causes_failed_state()


# ═══════════════════════════════════════════════════════════════════════
#  VASSALAGE  (noble families only)
# ═══════════════════════════════════════════════════════════════════════

func liege_of(key: String) -> FactionDef:
	var faction := find_by_key(key)
	if faction == null or faction.liege == "":
		return null
	return find_by_key(faction.liege)


func vassals_of(key: String) -> Array[FactionDef]:
	var out: Array[FactionDef] = []
	for faction in factions:
		if faction.liege == key:
			out.append(faction)
	return out


## Everyone above this faction, immediate liege first. Empty for a free house.
func liege_chain(key: String) -> Array[FactionDef]:
	var out: Array[FactionDef] = []
	var current := liege_of(key)
	while current != null and out.size() < factions.size():
		out.append(current)
		current = liege_of(current.faction_id)
	return out


## The faction at the top of this one's chain — itself, if it answers to nobody.
func top_liege(key: String) -> FactionDef:
	var chain := liege_chain(key)
	return chain[-1] if not chain.is_empty() else find_by_key(key)


func is_vassal_of(key: String, liege_key: String, direct_only: bool = false) -> bool:
	if direct_only:
		var faction := find_by_key(key)
		return faction != null and faction.liege == liege_key
	for liege in liege_chain(key):
		if liege.faction_id == liege_key:
			return true
	return false


## This faction plus every vassal beneath it, however deep — the real extent of
## what someone at the top can call on.
func realm_of(key: String) -> Array[FactionDef]:
	var out: Array[FactionDef] = []
	var head := find_by_key(key)
	if head == null:
		return out
	var pending: Array[FactionDef] = [head]
	var seen: Dictionary = {}
	while not pending.is_empty():
		var faction: FactionDef = pending.pop_front()
		if seen.has(faction.faction_id):
			continue
		seen[faction.faction_id] = true
		out.append(faction)
		pending.append_array(vassals_of(faction.faction_id))
	return out


## Who this land answers to once fealty is followed all the way up — usually not
## the name on the province.
func ultimate_ruler_at(tile: Vector2i) -> FactionDef:
	var ruler := ruler_for_tile(tile)
	return top_liege(ruler.faction_id) if ruler else null


# ═══════════════════════════════════════════════════════════════════════
#  FEALTY CHANGES  (play state, and so the only part saved here)
# ═══════════════════════════════════════════════════════════════════════

## Swear `key` to `liege_key`, or pass "" to free it. Refuses anything that
## would break the guarantees liege_chain() relies on.
func set_liege(key: String, liege_key: String) -> bool:
	var faction := find_by_key(key)
	if faction == null or not faction.is_feudal():
		return false
	if liege_key == "":
		faction.liege = ""
		return true
	var liege := find_by_key(liege_key)
	if liege == null or liege == faction or not liege.is_feudal():
		return false
	# Swearing to your own vassal is how a ring of fealty gets made.
	if is_vassal_of(liege_key, key):
		return false
	faction.liege = liege_key
	return true


func vassalage_dict() -> Dictionary:
	var out: Dictionary = {}
	for faction in factions:
		if faction.liege != "":
			out[faction.faction_id] = faction.liege
	return out


func apply_vassalage(data: Dictionary) -> void:
	for faction in factions:
		faction.liege = ""
	for key: String in data:
		set_liege(key, str(data[key]))


# ══════════════════════════════════════════════════════════════════════
#  FACTION MAP OVERLAY
# ══════════════════════════════════════════════════════════════════════

func refresh_overlay() -> void:
	if _overlay == null or _influence.is_empty():
		return
	var colors := PackedColorArray()
	for faction in factions:
		colors.append(faction.color)
	# Ruled land takes the colour and is drawn solid over the influence fill, so
	# a faction reads as a bright core sitting in its own haze.
	var ids := _influence.duplicate()
	var ruled_mask := PackedInt32Array()
	ruled_mask.resize(ids.size())
	if _ruled.size() == ids.size():
		for i in ids.size():
			if _ruled[i] != NO_FACTION:
				ids[i] = _ruled[i]
				ruled_mask[i] = 1
	Growth.paint_overlay(_overlay, ids, _w, _h, colors, _world_map.bounds_px(),
		overlay_alpha, border_alpha, ruled_mask, rule_alpha)


func is_overlay_visible() -> bool:
	return _overlay != null and _overlay.visible


func set_overlay_visible(value: bool) -> void:
	if _overlay:
		_overlay.visible = value


## Flip the faction map and report the new state, so the caller can say so.
func toggle_overlay() -> bool:
	set_overlay_visible(not is_overlay_visible())
	return is_overlay_visible()
