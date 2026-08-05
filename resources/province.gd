extends Resource
class_name Province

## One political division of the overworld — the unit factions own territory in.
##
## Provinces are generated: ProvinceMap (scripts/alternate_mode/
## province_map.gd) takes every settlement icon on the world map's `locations`
## layer as a capital and floods outward, so a province is whatever land is
## closest to its capital in travel effort. Nothing here has to be authored for
## that to work — id, name and colour are all derived from `capital_tile`.
##
## Authoring is the exception rather than the rule. Drop a .tres of this type
## into ProvinceMap's `province_defs` with `capital_tile` set to a settlement's
## overworld coords and its name / faction / colour override the generated ones,
## leaving every other province alone.

## Index into ProvinceMap.provinces. Assigned at build time — a .tres used as an
## override does not need to set it, and any value it does set is ignored.
@export var id: int = -1

## Shown to the player ("You enter Varmark").
@export var display_name: String = ""

## The settlement this province grew from. For an override .tres this is the
## *key*: it is how the definition finds the province it belongs to.
@export var capital_tile: Vector2i = Vector2i.ZERO

## Who holds it. A plain string rather than an enum so new factions are content,
## not a script change. This is the one field that changes during play, and so
## the only one the save file carries.
@export var faction: String = "unclaimed"

## Overlay colour. Alpha is ignored — ProvinceMap supplies it, using a stronger
## value on border tiles so provinces read as outlined regions.
@export var color: Color = Color.WHITE

## Tiles the province ended up with. Filled in at build time; useful for area
## checks and for anything that wants to scatter something across a territory.
var tile_count: int = 0
