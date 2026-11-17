extends PlaceProvider
class_name BespokePlaceProvider

## A Place for a location authored as a MapConfig .tres. Identity comes from
## the config — its overworld_tile, SEED and map_name — so an authored town has
## the same kind of id as a generated one ("settlement_17_18") and the rest of
## the game can't tell them apart. Any world tags the overworld resolved for
## the tile (culture, ruler) are kept; the config fills in what they lack.

var config: MapConfig


func _init(authored: MapConfig) -> void:
	config = authored


func _fill_identity(place: Place, gen: MapGenerator) -> void:
	var map_type := int(config.map_type)
	place.coords = config.overworld_tile
	place.tile_seed = int(config.SEED) if config.SEED != 0 else int(gen.current_map_seed)
	place.display_name = config.map_name
	place.place_id = PlaceProvider.place_id_for(map_type, place.coords)

	var tags := ProceduralPlaceProvider.world_tags(gen, map_type)
	if not _has_prefix(tags, "biome."):
		tags.append("biome.%s" % _enum_tag(MapConfig.Biome, config.get("biome")))
	if not _has_prefix(tags, "culture."):
		var culture := _enum_tag(MapConfig.Culture, config.get("culture"))
		if not culture.is_empty():
			tags.append("culture.%s" % culture)
	tags.append("place.authored")
	place.tags = tags


static func _has_prefix(tags: Array[String], prefix: String) -> bool:
	for t in tags:
		if t.begins_with(prefix):
			return true
	return false


## Lower-cased enum key for an int value; a String (some older .tres files
## store one) passes through. Empty when there is nothing usable.
static func _enum_tag(enum_dict: Dictionary, value) -> String:
	if value is String:
		return (value as String).to_lower()
	if value is int:
		for key in enum_dict:
			if enum_dict[key] == value:
				return String(key).to_lower()
	return ""
