extends Node2D

const INTERIOR_LAYER := "structures_interior"

@export var building_id: String = "tavern_1"

@onready var structure_interior: TileMapLayer = $structure_interior
@onready var interior_props: TileMapLayer = $interior_props
@onready var floor_layer: TileMapLayer = $floor


func _ready() -> void:
	structure_interior.clear()
	interior_props.clear()
	floor_layer.clear()
	spawn_interior(building_id)


# exterior_building_id is the value of the "building id" custom data layer on the
# exterior building tile (e.g. "tavern_1"). Finds the matching interior sprite
# (custom data "layers" == "structures_interior", "building id" == exterior_building_id)
# and places it at the origin.
func spawn_interior(exterior_building_id: String) -> void:
	var ts: TileSet = structure_interior.tile_set
	if not ts:
		push_warning("building_interior: structure_interior has no TileSet")
		return

	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		if not src is TileSetAtlasSource:
			continue
		var atlas_src := src as TileSetAtlasSource
		for t in atlas_src.get_tiles_count():
			var coords := atlas_src.get_tile_id(t)
			var td := atlas_src.get_tile_data(coords, 0)
			if not td:
				continue
			if td.get_custom_data("layers") != INTERIOR_LAYER:
				continue
			if td.get_custom_data("building id") != exterior_building_id:
				continue
			structure_interior.set_cell(Vector2i.ZERO, sid, coords)
			return

	push_warning("building_interior: no interior found for building id '%s'" % exterior_building_id)
