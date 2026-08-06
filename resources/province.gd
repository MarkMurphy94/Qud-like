extends Resource
class_name Province

# region PROVINCE GAME NOTES:
# - Provinces are defined areas of land with borders recognized by all or most factions
# - A territory can be disputed if a faction claims all or part of it as part of one of their territories
# - A territory will have a ruling faction, possibly several cultures, and maybe a dominant culture
# - Territories are ruled by factions but multiple factions may have a presence in one territory
#     - Noble families might be an exception to this? Don’t know yet…maybe they could have diplomats/attaches/trade reps/etc.
# - Territories are far more likely to be ruled by noble families, Religious orders or Merchant Guilds. 
# - If a territory is somehow ruled by a bandit gang or rebel group, it should have some kind of “failed state” status, \
#   with rampant violence, no economic output, and waves of peasants migrating away from it.
# endregion

# region TECHNICAL NOTES:
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
# endregion

## Index into ProvinceMap.provinces. Assigned at build time — a .tres used as an
## override does not need to set it, and any value it does set is ignored.
@export var id: int = -1

## Shown to the player ("You enter Varmark").
@export var display_name: String = ""

@export var capital_tile: Vector2i = Vector2i.ZERO

@export var ruling_faction: String = "unclaimed"

@export var color: Color = Color.WHITE

var tile_count: int = 0
