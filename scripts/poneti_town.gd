extends Node2D

@onready var ground: TileMapLayer = $base_terrain
@onready var road: TileMapLayer = $road
@onready var terrain_features: TileMapLayer = $terrain_features
@onready var structures_exterior: TileMapLayer = $structures_exterior
@onready var structures_interior: TileMapLayer = $structures_interior
@onready var foliage: TileMapLayer = $foliage
@onready var structures: Node2D = $structures
@onready var decor_exterior: TileMapLayer = $decor_exterior
@onready var tilemaps = {
	"GROUND": ground,
	"INTERIOR_FLOOR": structures_interior,
	"WALLS": structures_interior,
	"FURNITURE": structures_interior,
	"ITEMS": structures_interior,
	"DOORS": structures_interior,
	"ROOF": structures_interior
}
