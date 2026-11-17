extends RefCounted
class_name PlaceProvider

## Turns one source of truth about a location into a Place. Subclasses decide
## the Place's identity — id, coords, seed, name, tags — and nothing else. The
## slot layout is shared: both pipelines end in the same MapGenerator record of
## what was painted (map_buildings, container_cells), so a building or chest
## gets the same kind of slot whichever pipeline put it there.
##
## ProceduralPlaceProvider — a tile generated from TileMetadata.
## BespokePlaceProvider    — a location authored as a MapConfig .tres.


func build(gen: MapGenerator) -> Place:
	var place := Place.new()
	_fill_identity(place, gen)
	_add_slots(place, gen)
	return place


## Set place_id, coords, tile_seed, display_name and tags.
func _fill_identity(_place: Place, _gen: MapGenerator) -> void:
	pass


## Slot ids are ordinal — buildings in placement order, containers sorted by
## cell within their building — so they depend on the seed and the layout,
## never on pixel positions.
func _add_slots(place: Place, gen: MapGenerator) -> void:
	var building_slots: Array[PlaceSlot] = []
	var type_names: Array = Structure.StructureType.keys()
	for i in gen.map_buildings.size():
		var b: Dictionary = gen.map_buildings[i]
		var slot := PlaceSlot.new()
		slot.slot_id = "b%d" % i
		slot.kind = "building"
		var type_index := int(b.get("type", -1))
		if type_index >= 0 and type_index < type_names.size():
			slot.tags.append("building.%s" % String(type_names[type_index]).to_lower())
		slot.data = {"type": type_index, "rect": Rect2i(b["pos"], b["size"]), "door": b.get("door", MapGenerator.NO_DOOR)}
		building_slots.append(slot)
		place.slots.append(slot)

	# Group container cells by the building whose footprint holds them.
	var groups: Dictionary = {}  # parent slot id ("" = outdoors) -> Array[Vector2i]
	for cell: Vector2i in gen.container_cells:
		var parent := ""
		for slot in building_slots:
			if (slot.data["rect"] as Rect2i).has_point(cell):
				parent = slot.slot_id
				break
		if not groups.has(parent):
			groups[parent] = []
		groups[parent].append(cell)

	for parent: String in groups:
		var cells: Array = groups[parent]
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var prefix: String = parent if not parent.is_empty() else "yard"
		var parent_slot := place.get_slot(parent)
		for k in cells.size():
			var cell: Vector2i = cells[k]
			var record: Dictionary = gen.container_cells[cell]
			var slot := PlaceSlot.new()
			slot.slot_id = "%s.container.%d" % [prefix, k]
			slot.kind = "container"
			slot.parent_slot_id = parent
			slot.cells = [cell]
			slot.tags.append("container.%s" % String(record.get("role", "chest")))
			if parent_slot:
				slot.tags.append_array(parent_slot.tags)
			slot.data = record
			place.slots.append(slot)

	var ambient := PlaceSlot.new()
	ambient.slot_id = "ambient"
	ambient.kind = "ambient"
	place.slots.append(ambient)


## The one place id scheme: map type + overworld tile, e.g. "settlement_13_21".
static func place_id_for(map_type: int, coords: Vector2i) -> String:
	return MainGameState.make_settlement_key(map_type, coords)
