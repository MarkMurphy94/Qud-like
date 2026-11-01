extends Resource
class_name PopulationPoolDef

## One population type (wolves, deer, bandits) as EncounterState simulates it
## per region. Loaded from resources/spawning/pools/ by EncounterDatabase; the
## id defaults to the file name and is what EncounterEntry.pool_id names.

@export var id: String = ""
@export var tags: Array[String] = []
## Biomes this population lives in; empty = every biome.
@export var biomes: Array[String] = []
@export var default_capacity: int = 20
## biome -> capacity, overriding default_capacity.
@export var capacity_by_biome: Dictionary = {}
## Fraction of capacity a region starts with.
@export var initial_fill: float = 0.75
## Per-capita growth per day; growth is logistic, so an empty pool stays empty
## until something migrates in.
@export var regrowth_per_day: float = 0.05
## prey pool_id -> ratio. Capacity is capped at the summed prey count × ratio.
@export var prey: Dictionary = {}
## Fraction of the overflow above capacity pushed to a neighbour each day.
@export var migration_rate: float = 0.0
## Below this fill, the survivors abandon the region for a neighbour.
@export var migrate_when_depleted_below: float = 0.0


func lives_in(biome: String) -> bool:
	return biomes.is_empty() or biome in biomes


func base_capacity(biome: String) -> float:
	return float(capacity_by_biome.get(biome, default_capacity))
