extends Node2D

@export var config: AreaConfig

@onready var tilemaps = {
	"GROUND": $ground,
	"INTERIOR_FLOOR": $interior_floor,
	"WALLS": $walls,
	"FURNITURE": $furniture,
	"ITEMS": $items,
	"DOORS": $doors,
	"ROOF": $roof
}
