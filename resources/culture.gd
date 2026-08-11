extends Resource
class_name Culture

# region CULTURE GAME NOTES:
# - A culture is a people: shared language, dress, architecture, food, faith and grudges
# - Cultures are NOT political. A province is ruled; a culture is simply lived in.
#   One province can hold several cultures, and one culture can spill across a
#   dozen borders — that mismatch is where most interesting trouble comes from
# - A settlement's culture should decide what its buildings look like, what its
#   people are named, what they will trade for and how they treat outsiders
# - Cultures spread from a homeland outward. Highlanders stop at the foot of the
#   mountains because that is where being a highlander stops meaning anything
# endregion

# region TECHNICAL NOTES:
## One people of the overworld — the unit settlements and NPCs inherit flavour
## from.
##
## Unlike Province, cultures are NOT generated. Every one of them is authored:
## you make a .tres of this type, give it a name and an `origin_tile`, and drop
## it into CultureMap's `culture_defs`. CultureMap (scripts/alternate_mode/
## culture_map.gd) then floods outward from those origins using exactly the same
## travel-cost rules that grow provinces, so a culture ends up covering whatever
## land is closest to its homeland in travel effort — mountains and forests hold
## it back, open ground lets it run.
##
## The two knobs that matter are `origin_tile` (where these people come from)
## and `spread` (how hard they push). Everything else is flavour the rest of the
## game reads off the tile the player is standing on.
# endregion

# To add a new culture:
# 1. Select the cultures node in qud_like_world_map.tscn.
# 2. In the Inspector under Authoring → Culture Defs, click Add Element, then the <empty> dropdown → scroll to find the Culture object.
# 3. Click the resulting resource to expand and edit it. Right-click it → Save As… to write it to cultures 
#    (otherwise it gets embedded in the scene file, which you don't want).

## Index into CultureMap.cultures. Assigned at build time — whatever a .tres
## sets here is ignored.
@export var id: int = -1

@export var display_name: String = ""

@export var culture_id: String = ""

@export var origin_tile: Vector2i = Vector2i.ZERO

## How far this people push, as a percentage of normal reach. 200 means they
## cross ground at half the usual cost and so claim roughly twice as far;
## 50 means they are hemmed in near their homeland. Use it to make a sprawling
## empire-culture and a stubborn little mountain-culture out of the same rules.
@export_range(25, 400, 5) var spread: int = 100

@export var color: Color = Color.WHITE

@export_group("Flavour")
@export_multiline var description: String = ""

## A dictionary rather than fixed fields so new hooks cost nothing.
@export var traits: Dictionary = {}

@export_group("Naming")
## TextGenerator profile ids — the id a MarkovProfile .tres in
## resources/markov/profiles/ declares, not a path to it, since TextGenerator
## already discovers and indexes every profile in that folder at startup.
## Leave one empty and this people are named from the generic profile, so a
## culture with no corpus of its own still gets sensible names.
@export var place_name_profile: String = ""
@export var npc_name_profile: String = ""

## Profiles used by cultures that name no profile of their own, and by land no
## culture reached. Keyed by role so callers ask for "a npc name" rather than
## knowing which profile that means.
const DEFAULT_NAME_PROFILES := {
	"place": "place_name",
	"npc": "npc_name",
}

var tile_count: int = 0


## The TextGenerator profile that writes `role` ("place" or "npc") names for
## this people.
func name_profile(role: String) -> String:
	var chosen := ""
	match role:
		"place":
			chosen = place_name_profile
		"npc":
			chosen = npc_name_profile
	if chosen != "":
		return chosen
	return DEFAULT_NAME_PROFILES.get(role, "")


## Null-safe form for callers holding the result of CultureMap.culture_for_tile(),
## which is null over sea, void, and land no culture reached.
static func profile_for(culture: Culture, role: String) -> String:
	if culture:
		return culture.name_profile(role)
	return DEFAULT_NAME_PROFILES.get(role, "")
