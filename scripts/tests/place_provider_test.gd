extends Node

## Place unification checks. Open scenes/tests/place_provider_test.tscn and
## press F6; results go to the Output panel.

const LOCAL_SCENE := preload("res://scenes/local_scene.tscn")
const AUTHORED_TILE := Vector2i(41, 37)

var _failures: int = 0
var _gen: MapGenerator


func _ready() -> void:
	_gen = LOCAL_SCENE.instantiate()
	_gen.generate_on_ready = false
	add_child(_gen)

	_check_procedural_place()
	_check_bespoke_place()
	_check_bespoke_is_deterministic()
	_check_settlement_rekey()
	AuthoredPlaces.reload()
	print("[PlaceTest] Done — %d failure(s)" % _failures)
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failures > 0 else 0)


func _meta(tile: Vector2i, seed_value: int) -> Dictionary:
	return {
		"coords": tile, "seed": seed_value, "terrain": 0, "biome": "temperate",
		"culture_id": "", "ruling_faction": "house_test",
		"overworld": {"settlement_density": -1, "has_settlement": false, "is_forest": false},
		"settlement_density": -1,
	}


func _check_procedural_place() -> void:
	_gen.generate_local_map(_meta(Vector2i(5, 6), 1234))
	var place := _gen.build_place()
	_expect(_gen.place_provider() is ProceduralPlaceProvider, "untagged tile uses the procedural provider")
	_expect(place.place_id == "area_5_6", "procedural place id is area_5_6 (got %s)" % place.place_id)
	_expect(place.tile_seed == 1234, "procedural place keeps the tile seed")
	_expect(place.has_tag("place.wilderness"), "procedural wilderness is tagged place.wilderness")
	_expect(place.has_tag("faction.house_test"), "procedural place carries the ruler tag")
	_expect(not place.has_tag("place.authored"), "procedural place is not tagged place.authored")


func _authored_config() -> MapConfig:
	var config := MapConfig.new()
	config.map_name = "Test Hold"
	config.map_type = MapConfig.MapType.SETTLEMENT
	config.building_density = MapConfig.BuildingDensity.SMALL_VILLAGE
	config.overworld_tile = AUTHORED_TILE
	config.SEED = 4242
	var house := Structure.new()
	house.TYPE = Structure.StructureType.HOUSE
	house.POSITION = Vector2i(20, 20)
	config.buildings.append(house)
	var tavern := Structure.new()
	tavern.TYPE = Structure.StructureType.HOUSE
	tavern.POSITION = Vector2i(40, 30)
	config.buildings.append(tavern)
	return config


func _check_bespoke_place() -> void:
	AuthoredPlaces.register(_authored_config())
	# The tile's own metadata says wilderness; the authored config must win.
	_gen.generate_local_map(_meta(AUTHORED_TILE, 999))
	var place := _gen.build_place()
	_expect(_gen.place_provider() is BespokePlaceProvider, "authored tile uses the bespoke provider")
	_expect(place.place_id == "settlement_%d_%d" % [AUTHORED_TILE.x, AUTHORED_TILE.y],
		"bespoke place id uses the same scheme (got %s)" % place.place_id)
	_expect(place.display_name == "Test Hold", "bespoke place takes the authored name")
	_expect(place.tile_seed == 4242, "bespoke place takes the authored seed")
	_expect(place.has_tag("place.authored"), "bespoke place is tagged place.authored")
	_expect(place.has_tag("place.settlement"), "bespoke settlement is tagged place.settlement")
	_expect(place.has_tag("faction.house_test"), "bespoke place keeps the overworld ruler tag")
	_expect(place.has_tag("biome.temperate"), "bespoke place has a biome tag")
	_expect(place.slots_of_kind("building").size() == 2,
		"both authored buildings become slots (got %d)" % place.slots_of_kind("building").size())
	_expect(place.get_slot("ambient") != null, "bespoke place has an ambient slot")


func _check_bespoke_is_deterministic() -> void:
	_gen.generate_local_map(_meta(AUTHORED_TILE, 999))
	var first := _slot_ids(_gen.build_place())
	_gen.generate_local_map(_meta(Vector2i(5, 6), 1234))  # visit elsewhere in between
	_gen.generate_local_map(_meta(AUTHORED_TILE, 999))
	var second := _slot_ids(_gen.build_place())
	_expect(first == second, "revisiting an authored tile rebuilds the same slots")


func _slot_ids(place: Place) -> Array[String]:
	var out: Array[String] = []
	for slot in place.slots:
		out.append(slot.slot_id)
	return out


func _check_settlement_rekey() -> void:
	var saved_state: Dictionary = MainGameState.settlements.duplicate(true)
	MainGameState.load_settlements({
		"town_1": {"map_type": MapConfig.MapType.SETTLEMENT, "pos": Vector2i(17, 18), "seed": 7},
		"legacy_without_pos": {"seed": 8},
	})
	_expect(MainGameState.settlements.has("settlement_17_18"), "name-keyed entry is re-keyed to its place id")
	_expect(not MainGameState.settlements.has("town_1"), "old name key is gone after re-keying")
	_expect(MainGameState.find_settlement_by_name("town_1").get("seed") == 7, "re-keyed entry is still found by name")
	_expect(MainGameState.settlements.has("legacy_without_pos"), "entry without map_type/pos keeps its key")
	MainGameState.settlements = saved_state


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PlaceTest] ok    %s" % label)
	else:
		_failures += 1
		push_error("[PlaceTest] FAIL  %s" % label)
		print("[PlaceTest] FAIL  %s" % label)
