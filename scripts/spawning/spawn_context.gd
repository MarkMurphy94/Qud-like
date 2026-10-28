extends RefCounted
class_name SpawnContext

## Everything one spawn roll may depend on. Built per slot so that each slot
## rolls from its own RNG and never from another slot's leftovers.

## biome.*, place.*, faction.*, culture.*, role.*, law.* — matched against
## ItemSpawnEntry.context_require / context_exclude.
var tags: Array[String] = []
var tier: int = 0
var era: int = 0
var place_id: String = ""
var slot_id: String = ""
var rng: RandomNumberGenerator
var chronicle: ChronicleQuery


## Context for `slot_id` in `place`: the place's tags, the slot's own tags if
## it is one of the place's slots (owner slots such as "npc.<id>" are not), and
## `extra_tags` from the owner. The seed depends only on the tile seed, the
## place and the slot, so the same slot always rolls the same.
static func for_slot(place: Place, slot_id: String, extra_tags: Array[String] = []) -> SpawnContext:
	var ctx := SpawnContext.new()
	ctx.place_id = place.place_id
	ctx.slot_id = slot_id
	ctx.tags = place.tags.duplicate()
	var slot := place.get_slot(slot_id)
	if slot:
		ctx._add_tags(slot.tags)
	ctx._add_tags(extra_tags)
	ctx.tier = SpawnTier.for_place(place)
	ctx.era = 0
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = hash([place.tile_seed, place.place_id, slot_id])
	ctx.chronicle = ChronicleQuery.new()
	return ctx


func has_tag(tag: String) -> bool:
	return tag in tags


func _add_tags(more: Array[String]) -> void:
	for tag in more:
		if not tag in tags:
			tags.append(tag)
