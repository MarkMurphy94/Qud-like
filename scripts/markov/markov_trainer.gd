@tool
extends RefCounted
class_name MarkovTrainer

# ==========
# Turns a MarkovCorpus into a MarkovModel, and owns the tokenizer that both
# ends of the pipeline have to agree on.
#
# Two things here decide output quality:
#
#  - Padding. Every sample gets `order` START tokens in front and one END
#    token behind. Without them the chain has no notion of how a name begins
#    or when a sentence is finished, and output starts mid-word.
#  - Every order. n-grams are recorded at each length from 0 to `order` in one
#    table, so the generator can fall back to a shorter context rather than
#    dead-ending on a context the corpus never contained.
# ==========

## Words (including hyphenated compounds and apostrophes) or a lone punctuation
## mark. Deliberately ASCII: PCRE2's \p{L} depends on UTF mode being enabled.
const WORD_PATTERN := "[A-Za-z0-9'\u2019]+(?:-[A-Za-z0-9'\u2019]+)*|[^\\sA-Za-z0-9]"

const NO_SPACE_BEFORE := [",", ".", "!", "?", ";", ":", ")", "]", "}", "%"]
const NO_SPACE_AFTER := ["(", "[", "{"]

static var _word_regex: RegEx = null


static func train(corpus: MarkovCorpus) -> MarkovModel:
	var model := MarkovModel.new()
	if corpus == null:
		return model
	model.id = corpus.id
	model.order = maxi(1, corpus.order)
	model.mode = corpus.mode

	var table: Dictionary = {} # context -> {token: count}
	var sources: Dictionary = {}
	var accepted := 0

	for raw in corpus.collect_samples():
		var text: String = raw.strip_edges()
		if text.is_empty():
			continue
		if corpus.lowercase_input:
			text = text.to_lower()
		var toks := tokenize(text, corpus.mode)
		if toks.is_empty():
			continue
		accepted += 1
		sources[join(toks, corpus.mode)] = true

		var padded := PackedStringArray()
		for _i in model.order:
			padded.append(MarkovModel.START)
		padded.append_array(toks)
		padded.append(MarkovModel.END)

		for i in range(model.order, padded.size()):
			var next := padded[i]
			for n in range(0, model.order + 1):
				var ctx := MarkovModel.make_context(padded, i - n, n)
				var succ: Dictionary = table.get(ctx, {})
				succ[next] = int(succ.get(next, 0)) + 1
				table[ctx] = succ

	model.sample_count = accepted
	model.source_forms = PackedStringArray(sources.keys())
	_compile(model, table)
	return model


static func tokenize(text: String, mode: int) -> PackedStringArray:
	var out := PackedStringArray()
	if mode == MarkovModel.TokenMode.CHAR:
		for i in text.length():
			out.append(text[i])
		return out
	if _word_regex == null:
		_word_regex = RegEx.new()
		_word_regex.compile(WORD_PATTERN)
	for m in _word_regex.search_all(text):
		out.append(m.get_string())
	return out


## Inverse of tokenize(), close enough to compare against source samples.
static func join(tokens: PackedStringArray, mode: int) -> String:
	if mode == MarkovModel.TokenMode.CHAR:
		return "".join(tokens)
	var out := ""
	var glue_next := false
	for tok in tokens:
		if out.is_empty() or glue_next or tok in NO_SPACE_BEFORE:
			out += tok
		else:
			out += " " + tok
		glue_next = tok in NO_SPACE_AFTER
	return out


static func _compile(model: MarkovModel, table: Dictionary) -> void:
	var contexts := PackedStringArray()
	var row_start := PackedInt32Array()
	var tokens := PackedStringArray()
	var counts := PackedInt32Array()
	var totals := PackedInt32Array()
	var cursor := 0
	for ctx in table:
		var succ: Dictionary = table[ctx]
		contexts.append(ctx)
		row_start.append(cursor)
		var total := 0
		for tok in succ:
			var n: int = succ[tok]
			tokens.append(tok)
			counts.append(n)
			total += n
			cursor += 1
		totals.append(total)
	row_start.append(cursor)

	model.contexts = contexts
	model.row_start = row_start
	model.tokens = tokens
	model.counts = counts
	model.totals = totals
