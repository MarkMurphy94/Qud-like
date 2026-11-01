extends Resource
class_name EncounterCondition

## A tag predicate over an EncounterContext. Every world fact a rule can test is
## a context tag, so a new rule dimension means emitting a new tag — never a new
## field here.

@export var require_all: Array[String] = []
@export var require_any: Array[String] = []   ## Empty = no constraint.
@export var forbid: Array[String] = []
@export var min_difficulty: int = 0
@export var max_difficulty: int = 99


func matches(ctx: EncounterContext) -> bool:
	if ctx.difficulty < min_difficulty or ctx.difficulty > max_difficulty:
		return false
	for tag in require_all:
		if not ctx.has_tag(tag):
			return false
	for tag in forbid:
		if ctx.has_tag(tag):
			return false
	if require_any.is_empty():
		return true
	for tag in require_any:
		if ctx.has_tag(tag):
			return true
	return false
