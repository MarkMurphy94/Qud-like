extends RefCounted
class_name SpawnTier

## The one place a Place's danger/quality tier is decided. Spawn tables gate
## entries on it (ItemSpawnEntry.tier_range) and it nudges rarity rolls.
## A constant for now; encounters are meant to share this once
## TileMetadata.encounter_difficulty is actually computed.

const DEFAULT_TIER := 1


static func for_place(place: Place) -> int:
	var tier := DEFAULT_TIER
	if place.has_tag("place.ruin"):
		tier += 1
	return tier
