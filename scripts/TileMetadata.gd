extends Resource
class_name TileMetadata

@export var coords: Vector2i
@export var seed: int
@export var terrain: int
@export var biome: String = ""
@export var climate: String = ""
@export var elevation: float = 0.0
@export var region_id: String = ""

@export var water_features := {
	"river": false,
	"lake": false,
	"spring": false,
	"marsh": false
}

@export var ground_cover := {
	"grass": 0.0,
	"flowers": 0.0,
	"shrubs": 0.0,
	"rock": 0.0,
	"sand": 0.0
}

@export var vegetation := {
	"canopy_density": 0.0,
	"species_mix": [],
	"rare_plants": []
}

@export var resources := {
	"wood": 0,
	"stone": 0,
	"ore": [],
	"forageables": []
}

@export var wildlife := {
	"common": [],
	"rare": [],
	"aggression": 0.0
}

@export var hazards := {
	"landslide": 0.0,
	"quicksand": 0.0,
	"sinkhole": 0.0,
	"toxic_spores": 0.0
}

@export var territorial_claims: Array = []
@export var boundary_markers: Array = []
@export var routes: Array = []
@export var shrines_sites: Array = []
@export var hidden_sites: Array = []
@export var forbidden_zones := {"cultural_taboo": false, "reason": "", "enforcement": 0.0}

@export var encounter_tables := {"day": "", "night": "", "weather_overrides": []}
@export var event_hooks: Array = []
@export var ruins := {"exists": false, "era": "", "integrity": 0.0, "loot_tier": 0}
@export var dungeon_entrance := {"exists": false, "depth_hint": 0, "theme": ""}
@export var camp := {"exists": false, "owner": "", "size": "", "permanence": 0.0}
@export var farm_plot := {"exists": false, "crop": "", "size": 0, "owner": ""}

@export var weather_bias := {"rain": 0.0, "fog": 0.0, "wind": 0.0, "storm": 0.0}
@export var seasonal_variation := {"winter_snow": 0.0, "spring_bloom": 0.0, "autumn_colors": 0.0}
@export var travel_cost := {"foot": 1, "mount": 1, "wagon": 1}
@export var visibility := {"day": 0.0, "night": 0.0, "foliage_occlusion": 0.0}
@export var soundscape := {"birds": 0.0, "insects": 0.0, "water": 0.0, "wind": 0.0}

@export var generated_at: int = 1
@export var discovered: bool = false
@export var last_visited: int = 0
@export var dynamic_state := {"fires_burned": 0, "poached_wildlife": 0, "structures_built": []}
@export var loot_instances: Array = []
@export var npc_presence: Array = []
@export var flags := {"cleared_bandits": false, "found_shrine": false, "mapped_cave": false}

@export var feature_weights := {"lake": 0.0, "river": 0.0, "meadow": 0.0, "boulder_field": 0.0}
@export var foliage_profile := {"tree_density": 0.0, "bush_density": 0.0, "rock_density": 0.0}
@export var encounter_difficulty: int = 1

static func from_dict(d: Dictionary) -> TileMetadata:
	var t := TileMetadata.new()
	t.coords = d.get("coords", Vector2i.ZERO)
	t.seed = d.get("seed", 0)
	t.terrain = d.get("terrain", 0)
	t.biome = d.get("biome", "")
	t.climate = d.get("climate", "")
	t.elevation = d.get("elevation", 0.0)
	t.region_id = d.get("region_id", "")
	# Shallow copy for maps/arrays; adjust as needed
	t.water_features = d.get("water_features", t.water_features)
	t.ground_cover = d.get("ground_cover", t.ground_cover)
	t.vegetation = d.get("vegetation", t.vegetation)
	t.resources = d.get("resources", t.resources)
	t.wildlife = d.get("wildlife", t.wildlife)
	t.hazards = d.get("hazards", t.hazards)
	t.territorial_claims = d.get("territorial_claims", [])
	t.boundary_markers = d.get("boundary_markers", [])
	t.routes = d.get("routes", [])
	t.shrines_sites = d.get("shrines_sites", [])
	t.hidden_sites = d.get("hidden_sites", [])
	t.forbidden_zones = d.get("forbidden_zones", t.forbidden_zones)
	t.encounter_tables = d.get("encounter_tables", t.encounter_tables)
	t.event_hooks = d.get("event_hooks", [])
	t.ruins = d.get("ruins", t.ruins)
	t.dungeon_entrance = d.get("dungeon_entrance", t.dungeon_entrance)
	t.camp = d.get("camp", t.camp)
	t.farm_plot = d.get("farm_plot", t.farm_plot)
	t.weather_bias = d.get("weather_bias", t.weather_bias)
	t.seasonal_variation = d.get("seasonal_variation", t.seasonal_variation)
	t.travel_cost = d.get("travel_cost", t.travel_cost)
	t.visibility = d.get("visibility", t.visibility)
	t.soundscape = d.get("soundscape", t.soundscape)
	t.generated_at = d.get("generated_at", t.generated_at)
	t.discovered = d.get("discovered", t.discovered)
	t.last_visited = d.get("last_visited", t.last_visited)
	t.dynamic_state = d.get("dynamic_state", t.dynamic_state)
	t.loot_instances = d.get("loot_instances", [])
	t.npc_presence = d.get("npc_presence", [])
	t.flags = d.get("flags", t.flags)
	t.feature_weights = d.get("feature_weights", t.feature_weights)
	t.foliage_profile = d.get("foliage_profile", t.foliage_profile)
	t.encounter_difficulty = d.get("encounter_difficulty", t.encounter_difficulty)
	return t

func to_dict() -> Dictionary:
	return {
		"coords": coords,
		"seed": seed,
		"terrain": terrain,
		"biome": biome,
		"climate": climate,
		"elevation": elevation,
		"region_id": region_id,
		"water_features": water_features,
		"ground_cover": ground_cover,
		"vegetation": vegetation,
		"resources": resources,
		"wildlife": wildlife,
		"hazards": hazards,
		"territorial_claims": territorial_claims,
		"boundary_markers": boundary_markers,
		"routes": routes,
		"shrines_sites": shrines_sites,
		"hidden_sites": hidden_sites,
		"forbidden_zones": forbidden_zones,
		"encounter_tables": encounter_tables,
		"event_hooks": event_hooks,
		"ruins": ruins,
		"dungeon_entrance": dungeon_entrance,
		"camp": camp,
		"farm_plot": farm_plot,
		"weather_bias": weather_bias,
		"seasonal_variation": seasonal_variation,
		"travel_cost": travel_cost,
		"visibility": visibility,
		"soundscape": soundscape,
		"generated_at": generated_at,
		"discovered": discovered,
		"last_visited": last_visited,
		"dynamic_state": dynamic_state,
		"loot_instances": loot_instances,
		"npc_presence": npc_presence,
		"flags": flags,
		"feature_weights": feature_weights,
		"foliage_profile": foliage_profile,
		"encounter_difficulty": encounter_difficulty
	}