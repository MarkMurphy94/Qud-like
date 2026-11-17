extends Resource

class_name Structure

enum StructureType {
	HOUSE,
	TAVERN,
	SHOP,
	CHURCH,
	BLACKSMITH,
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


## The shape a placed building is saved in (MainGameState.settlements entries'
## "buildings"): {type, pos, size}. The only conversion between a Structure and
## a record — the generator's map_buildings use the same keys, plus "door".
func to_record() -> Dictionary:
	return {"type": int(TYPE), "pos": POSITION, "size": INTERIOR_SIZE}


static func from_record(record: Dictionary) -> Structure:
	var s := Structure.new()
	s.TYPE = int(record.get("type", StructureType.HOUSE)) as StructureType
	s.POSITION = record.get("pos", Vector2i.ZERO)
	s.INTERIOR_SIZE = record.get("size", Vector2i.ZERO)
	return s
