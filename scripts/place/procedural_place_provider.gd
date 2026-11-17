extends PlaceProvider
class_name ProceduralPlaceProvider

## A Place for a tile generated from its metadata (MainGame._build_local_map_metadata):
## identity comes from the overworld — coords, the tile's permanent seed, and
## the biome, culture and ruler resolved for that tile.


func _fill_identity(place: Place, gen: MapGenerator) -> void:
	var meta: Dictionary = gen.current_metadata
	place.coords = meta.get("coords", Vector2i.ZERO)
	place.tile_seed = int(meta.get("seed", gen.current_map_seed))
	place.display_name = str(meta.get("name", ""))
	var map_type := _map_type(gen)
	place.place_id = PlaceProvider.place_id_for(map_type, place.coords)
	place.tags = world_tags(gen, map_type)


func _map_type(gen: MapGenerator) -> int:
	return int(gen.map_template.map_type) if gen.map_template else MapConfig.MapType.NON_SETTLEMENT


## Tags the overworld knows about this tile. Shared with BespokePlaceProvider,
## so an authored town still says whose land it stands on.
static func world_tags(gen: MapGenerator, map_type: int) -> Array[String]:
	var tags: Array[String] = []
	var meta: Dictionary = gen.current_metadata
	var overworld := gen._merged_overworld_metadata()
	var biome := str(meta.get("biome", overworld.get("biome", ""))).to_lower()
	if not biome.is_empty():
		tags.append("biome.%s" % biome)
	var culture := str(meta.get("culture_id", ""))
	if not culture.is_empty():
		tags.append("culture.%s" % culture)
	var faction := str(meta.get("ruling_faction", ""))
	if not faction.is_empty():
		tags.append("faction.%s" % faction)
	tags.append("place.settlement" if map_type == MapConfig.MapType.SETTLEMENT else "place.wilderness")
	if bool(overworld.get("is_forest", false)):
		tags.append("place.forest")
	var ruins = meta.get("ruins", {})
	if ruins is Dictionary and bool(ruins.get("exists", false)):
		tags.append("place.ruin")
	return tags
