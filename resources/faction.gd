extends Resource
class_name Faction

# region FACTION GAME NOTES:
# - A faction is an organisation with an agenda. Provinces are places and
#   cultures are peoples; factions are whoever is doing things to both
# - Two different footprints, and the gap between them is the point. A faction
#   RULES provinces — hard, recognised, taxable — and it has an area of
#   INFLUENCE, which is wherever its money, priests, cousins or threats reach.
#   Influence spills well past any border, so most trouble happens on land one
#   faction rules and another leans on
# - Only noble families, religious orders and merchant guilds rule well. A
#   province held by a gang or a rebellion is a failed state (see province.gd)
# - Noble families are the only ones that swear fealty. A vassal rules its own
#   provinces and answers to a liege, so the top of a chain commands far more
#   land than it holds in its own name
# endregion

# region TECHNICAL NOTES:
## One organisation on the overworld.
##
## Like Culture and unlike Province, factions are authored rather than found:
## you make a .tres of this type, give it a `seat_tile`, and drop it into
## FactionMap's `faction_defs`. FactionMap (scripts/alternate_mode/
## faction_map.gd) then floods outward from every seat using the same
## travel-cost rules that grow provinces and cultures, and that flood is the
## area of influence.
##
## Ruled land is a separate thing entirely and is not grown: a faction rules a
## province when that province's `ruling_faction` matches this `faction_id`.
## `starting_provinces` is only the opening position — after that, ownership is
## play state and lives in the save file.
# endregion

enum FactionType {
	NOBLE_FAMILY,
	RELIGIOUS_ORDER,
	MERCHANT_GUILD,
	BANDIT_GANG,
	REBEL_GROUP,
}

## Default reach per type, as a percentage (see RegionGrowth.NORMAL_REACH).
## Guilds and orders keep houses and chapters far from home; a gang's reach ends
## where the next valley's gang begins.
const TYPE_INFLUENCE := {
	FactionType.NOBLE_FAMILY: 100,
	FactionType.RELIGIOUS_ORDER: 150,
	FactionType.MERCHANT_GUILD: 175,
	FactionType.BANDIT_GANG: 55,
	FactionType.REBEL_GROUP: 70,
}

const TYPE_NAMES := {
	FactionType.NOBLE_FAMILY: "noble family",
	FactionType.RELIGIOUS_ORDER: "religious order",
	FactionType.MERCHANT_GUILD: "merchant guild",
	FactionType.BANDIT_GANG: "bandit gang",
	FactionType.REBEL_GROUP: "rebel group",
}

## Index into FactionMap.factions. Assigned at build time — whatever a .tres
## sets here is ignored.
@export var id: int = -1

@export var display_name: String = ""

## Stable string key, and the value Province.ruling_faction is matched against.
## Falls back to a slug of `display_name`.
@export var faction_id: String = ""

@export var faction_type: FactionType = FactionType.NOBLE_FAMILY

## Where this faction is run from — a seat, a mother house, a counting hall or a
## camp. Must be on land.
@export var seat_tile: Vector2i = Vector2i.ZERO

## Reach as a percentage of normal, same scale as Culture.spread. Leave at 0 to
## take the default for this faction type.
@export_range(0, 400, 5) var influence: int = 0

## Banner on the map and livery on the sprites — FactionPalette hue-swaps NPC
## cloth to this. Leave it white and FactionMap generates one from the id.
@export var color: Color = Color.WHITE

## One tile inside each province this faction starts out ruling — the province's
## capital is the obvious choice. Opening position only; after that, ownership
## is play state owned by ProvinceMap.
@export var starting_provinces: Array[Vector2i] = []

@export_group("Vassalage")
## `faction_id` of the noble family this one is sworn to, or "" for a free
## house. Noble families only — FactionMap clears it on anyone else.
@export var liege: String = ""

@export_group("Flavour")
## `culture_id` these people belong to. Drives names, dress and who they read as
## foreign; it is not a border, so a faction can happily rule land whose culture
## it is not.
@export var home_culture: String = ""
@export_multiline var description: String = ""
@export var motto: String = ""
## Standing opinion of other factions, keyed by `faction_id`, −100 to 100.
## Matches the convention in npc.gd.
@export var relations: Dictionary = {}
## A dictionary rather than fixed fields so new hooks cost nothing.
@export var traits: Dictionary = {}

var influence_tiles: int = 0
var ruled_tiles: int = 0


func effective_influence() -> int:
	return influence if influence > 0 else int(TYPE_INFLUENCE.get(faction_type, 100))


## Can this faction hold a province without the place falling apart?
func rules_legitimately() -> bool:
	return faction_type in [
		FactionType.NOBLE_FAMILY, FactionType.RELIGIOUS_ORDER, FactionType.MERCHANT_GUILD
	]


## A province these people end up holding should read as a failed state:
## violence, no output, peasants leaving.
func causes_failed_state() -> bool:
	return not rules_legitimately()


## Fealty runs between noble families and nowhere else — a guild does not swear
## to a house, it lends to one.
func is_feudal() -> bool:
	return faction_type == FactionType.NOBLE_FAMILY


func type_name() -> String:
	return str(TYPE_NAMES.get(faction_type, "faction"))
