extends RefCounted
class_name ChronicleQuery

## How spawn entries ask the world's history whether they apply
## (ItemSpawnEntry.chronicle_condition). A stub until WorldChronicle exists:
## unconditional entries pass, and any entry that names a condition is held
## back rather than guessed at.

func matches(condition: String, _ctx: SpawnContext) -> bool:
	return condition.is_empty()
