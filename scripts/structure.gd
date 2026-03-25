extends Resource

class_name Structure

enum StructureType {
	HOUSE,
	TAVERN,
	SHOP,
	CHURCH,
	WALL,
	MANOR,
	BARRACKS,
	CASTLE_KEEP
}

@export var TYPE: StructureType
@export var BUILDING_NAME: String
@export var DESCRIPTION: String
@export var POSITION: Vector2i
@export var INTERIOR_SIZE: Vector2i
@export var ZONES: Array[Vector2i]
@export var INTERIOR_FEATURES: Array[String]
@export var SCRIPTED_CONTENT = null
