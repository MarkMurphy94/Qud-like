@tool
extends Resource
class_name Place

## A local map as the rest of the game addresses it: one stable id, the tags
## that describe it, and the slots things can be spawned into.
##
## Built by MapGenerator.build_place() after every generation, so it is never
## saved — the same seed rebuilds the same Place, and only what was rolled into
## its slots needs persisting (keyed by place_id + slot_id).

@export var place_id: String = ""
@export var coords: Vector2i = Vector2i.ZERO
## The overworld tile's permanent local-map seed (MainGame.get_tile_seed).
@export var tile_seed: int = 0
@export var tags: Array[String] = []
@export var slots: Array[PlaceSlot] = []


func get_slot(slot_id: String) -> PlaceSlot:
	for slot in slots:
		if slot.slot_id == slot_id:
			return slot
	return null


func slots_of_kind(kind: String) -> Array[PlaceSlot]:
	var out: Array[PlaceSlot] = []
	for slot in slots:
		if slot.kind == kind:
			out.append(slot)
	return out


func has_tag(tag: String) -> bool:
	return tag in tags


func describe() -> String:
	var lines: PackedStringArray = ["%s  tags=%s" % [place_id, tags]]
	for slot in slots:
		lines.append("  %-22s %-9s %s" % [slot.slot_id, slot.kind, slot.tags])
	return "\n".join(lines)
