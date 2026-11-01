extends Resource
class_name EncounterEntry

## One kind of encounter the wilderness can produce: who, how many, where, and
## under which conditions. Loaded from resources/spawning/encounters/ by
## EncounterDatabase; the id defaults to the file name.

@export var id: String = ""
@export_enum("ambient", "anchor") var kind: String = "ambient"
## Anchor only: the camp keys this entry can fill ("camp.bandit", "camp.wolf_den").
@export var anchor_match: Array[String] = []
@export var condition: EncounterCondition
@export var base_weight: float = 10.0
## Budget spent per individual spawned.
@export var budget_cost: int = 1
## Population pool this entry draws from; empty = not pool-limited.
@export var pool_id: String = ""
## A key of NPCSpawner.ENCOUNTER_NPC_TYPES.
@export var npc_type: String = "animal"
## Empty = the spawner rolls any variant of the type.
@export var variants: Array[String] = []
@export var group_min: int = 1
@export var group_max: int = 1
@export_enum("scatter", "cluster", "edge", "anchor_point") var placement: String = "scatter"
## Per tile, after this entry spawns.
@export var cooldown_hours: float = 0.0
## What spawn modifiers can target ("predator", "prey", "outlaw").
@export var weight_tags: Array[String] = []
