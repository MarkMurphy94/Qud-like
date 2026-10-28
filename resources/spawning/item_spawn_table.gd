extends Resource
class_name ItemSpawnTable

## A weighted list of what can turn up somewhere. Authored as .tres under
## res://resources/spawn_tables/ and loaded by ItemDatabase; resolved by
## ItemSpawnResolver against a SpawnContext.

## Blank falls back to the file's basename ("owned.role.merchant").
@export var id: String = ""
## "owned" (an NPC's, merchant's or container's) or "ambient" (scatter).
@export var tier: String = "ambient"
## How many entries are drawn per resolve.
@export var rolls: Vector2i = Vector2i(1, 1)
## When false, an entry can be drawn at most once per resolve.
@export var allow_repeats: bool = true
@export var entries: Array[ItemSpawnEntry] = []
