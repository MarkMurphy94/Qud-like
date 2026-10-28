extends Resource
class_name ItemSpawnEntry

## One weighted option in an ItemSpawnTable. Names exactly one source: a
## specific item, a tag query, or a nested table (ItemDatabase validates this
## on load and drops entries that break it).

@export var item_id: String = ""            ## A specific item or template, OR
@export var item_tags: Array[String] = []   ## any item carrying all of these tags, OR
@export var table_id: String = ""           ## a nested ItemSpawnTable.
@export var weight: float = 1.0
@export var count: Vector2i = Vector2i(1, 1)
## SpawnContext tags this entry needs / must not see ("biome.desert", "role.guard").
@export var context_require: Array[String] = []
@export var context_exclude: Array[String] = []
@export var tier_range: Vector2i = Vector2i(0, 99)
@export var era_range: Vector2i = Vector2i(-1, -1)  ## -1 = unbounded
@export var chronicle_condition: String = ""        ## See ChronicleQuery; stubbed.
## Shifts the rarity roll upward. An item_id entry only rolls rarity at all
## when this is positive; otherwise it spawns at the template's rarity.
@export var rarity_bias: float = 0.0


## How many of item_id / item_tags / table_id are set. Valid entries have one.
func source_count() -> int:
	var n := 0
	if not item_id.is_empty():
		n += 1
	if not item_tags.is_empty():
		n += 1
	if not table_id.is_empty():
		n += 1
	return n
