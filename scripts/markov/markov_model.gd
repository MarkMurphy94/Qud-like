@tool
extends Resource
class_name MarkovModel

# ==========
# A trained Markov chain.
#
# The transition table is stored flat (compressed sparse row) rather than as
# nested dictionaries: it serialises to .tres as a handful of packed arrays,
# loads without allocating a Dictionary per context, and keeps a deterministic
# row order.
#
# The table holds every context length from 0 (the unigram row, keyed by "")
# up to `order`. That redundancy is what lets the generator back off to a
# shorter context instead of dead-ending on an n-gram the corpus never had.
#
# Written by MarkovTrainer, read by TextGenerator. Nothing else should touch it.
# ==========

enum TokenMode {
	CHAR, ## One token per character — names.
	WORD, ## One token per word or punctuation mark — prose.
}

## Control codes, so a sentinel can never collide with corpus text.
const SEP := "\u0001"
const START := "\u0002"
const END := "\u0003"

@export var id: String = ""
@export var order: int = 3
@export var mode: TokenMode = TokenMode.CHAR
@export var sample_count: int = 0

## Every training sample, rendered the way generation renders output, so
## verbatim regurgitation can be rejected.
@export var source_forms := PackedStringArray()

@export_group("Baked table")
@export var contexts := PackedStringArray()
## Row i owns tokens/counts in [row_start[i], row_start[i + 1]).
@export var row_start := PackedInt32Array()
@export var tokens := PackedStringArray()
@export var counts := PackedInt32Array()
@export var totals := PackedInt32Array()

var _rows: Dictionary = {}
var _sources: Dictionary = {}


## Key for `count` tokens of `window` starting at `from`. count == 0 is the
## unigram row.
static func make_context(window: PackedStringArray, from: int, count: int) -> String:
	if count <= 0:
		return ""
	var parts := PackedStringArray()
	for i in range(from, from + count):
		parts.append(window[i])
	return SEP.join(parts)


func is_empty() -> bool:
	return contexts.is_empty()


func has_context(context: String) -> bool:
	_ensure_index()
	return _rows.has(context)


## One weighted draw from `context`; empty string if the context is unknown.
func sample(context: String, rng: RandomNumberGenerator) -> String:
	_ensure_index()
	if not _rows.has(context):
		return ""
	var row: int = _rows[context]
	var total: int = totals[row]
	if total <= 0:
		return ""
	var pick := rng.randi_range(1, total)
	var acc := 0
	for i in range(row_start[row], row_start[row + 1]):
		acc += counts[i]
		if pick <= acc:
			return tokens[i]
	return tokens[row_start[row + 1] - 1]


func is_source_form(text: String) -> bool:
	_ensure_index()
	return _sources.has(text)


# The packed arrays are the serialised truth; these lookups are rebuilt from
# them on first use (and after a retrain replaces the table in place).
func _ensure_index() -> void:
	if _rows.size() == contexts.size() and _sources.size() == source_forms.size():
		return
	_rows.clear()
	for i in contexts.size():
		_rows[contexts[i]] = i
	_sources.clear()
	for form in source_forms:
		_sources[form] = true
