@tool
extends Resource
class_name PlaceSlot

## One addressable spot inside a Place: a building, a container, the ambient
## scatter pool. `slot_id` is structural ("b2", "b2.container.0", "ambient") and
## is the only identity anything persists against — `cells` say where the slot
## sits on the current map and exist for placement alone.

@export var slot_id: String = ""
## "building", "container" or "ambient".
@export var kind: String = ""
@export var tags: Array[String] = []
## The building a container stands in; empty for outdoor slots.
@export var parent_slot_id: String = ""
@export var cells: Array[Vector2i] = []
## Raw generator record (building rect and type, container record).
@export var data: Dictionary = {}
