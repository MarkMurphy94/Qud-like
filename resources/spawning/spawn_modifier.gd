extends Resource
class_name SpawnModifier

## A decaying change to what spawns where: history leaving marks on the world.
## Authored once as a template under resources/spawning/modifiers/ and
## instanced by EncounterState.add_modifier(), which fills the runtime fields.

@export var id: String = ""
@export_enum("region", "tile", "world") var scope: String = "region"
## Injected into EncounterContext while live ("state.war").
@export var context_tags: Array[String] = []
## EncounterEntry weight tag -> multiplier at full strength ("outlaw": 1.5).
@export var weight_mults: Dictionary = {}
## pool_id -> int, applied once on emission.
@export var pool_deltas: Dictionary = {}
@export var duration_days: float = 30.0
@export_enum("linear", "step", "exponential") var decay: String = "linear"

# Runtime fields, set by EncounterState.add_modifier() and saved in spawn_state.
## region_id, "x,y" tile key, or "" for world scope.
var target: String = ""
var start_day: float = 0.0
var source_event_id: String = ""


## 1.0 at emission, falling to 0.0 at duration_days.
func strength(now_day: float) -> float:
	var t := (now_day - start_day) / maxf(duration_days, 0.001)
	if t >= 1.0:
		return 0.0
	if t < 0.0:
		return 1.0
	match decay:
		"step":
			return 1.0
		"exponential":
			return pow(0.05, t)
		_:
			return 1.0 - t


func covers(tile_key: String, region_id: String) -> bool:
	match scope:
		"world":
			return true
		"tile":
			return target == tile_key
		_:
			return target == region_id


## The multiplier this modifier puts on an entry with `entry_tags`, fading
## toward 1.0 with strength. Every matching tag applies.
func weight_multiplier(entry_tags: Array[String], now_day: float) -> float:
	var mult := 1.0
	var s := strength(now_day)
	for tag in entry_tags:
		if weight_mults.has(tag):
			mult *= lerpf(1.0, float(weight_mults[tag]), s)
	return mult
