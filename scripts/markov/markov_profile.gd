@tool
extends Resource
class_name MarkovProfile

# ==========
# One use of a Markov chain: which corpus, how long the result may be, how it
# is capitalised, whether it is a template with slots.
#
# Everything domain-specific lives here, so a new naming style or a new flavour
# of book prose is two .tres files rather than a script change.
#
# The profile's `id` is what callers pass to TextGenerator.generate().
# ==========

enum Casing {NONE, CAPITALIZE, TITLE_CASE, SENTENCE_CASE}

@export var id: String = ""
## Trained on demand and cached for the session if `model` is unset.
@export var corpus: MarkovCorpus
## Optional pre-baked model; wins over `corpus` when present.
@export var model: MarkovModel

## When non-empty the chain is not run at all: the text is this string with
## every {slot} replaced. A slot resolves to a caller-supplied override first,
## then to the profile of the same id. Repeated slots share one value.
@export_multiline var template: String = ""

@export_group("Shape")
## Lengths are in tokens — characters for a CHAR model, words for a WORD one.
@export var min_length: int = 4
@export var max_length: int = 12
@export var casing: Casing = Casing.CAPITALIZE
## Short char-level chains reproduce their own training data surprisingly
## often; this throws those draws away.
@export var reject_source_forms: bool = true
@export var max_attempts: int = 24

@export_group("Affixes")
@export var prefixes := PackedStringArray()
@export var suffixes := PackedStringArray()
@export_range(0.0, 1.0) var affix_chance: float = 0.0
