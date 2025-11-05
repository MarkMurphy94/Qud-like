extends Resource

class_name Structure

enum StructureType {
	HOUSE,
	TAVERN,
	SHOP,
	WALL,
	MANOR,
	BARRACKS,
	CASTLE_KEEP
}

@export var TYPE: StructureType
@export var POSITION: Vector2i
@export var INTERIOR_SIZE: Vector2i
@export var ZONES: Array[Vector2i]
@export var INTERIOR_FEATURES: Array[String]
@export var SCRIPTED_CONTENT = null
