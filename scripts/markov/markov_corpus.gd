@tool
extends Resource
class_name MarkovCorpus

# ==========
# Training input for a Markov model: the raw samples plus how to cut them up.
# Kept separate from the trained MarkovModel so the source text stays editable
# and the model stays a derived artefact.
# ==========

@export var id: String = ""
@export var mode: MarkovModel.TokenMode = MarkovModel.TokenMode.CHAR
@export_range(1, 6) var order: int = 3
## Folding case collapses "T" and "t" onto one state, which is what makes a
## small name corpus usable. Leave it off for prose, where proper nouns matter.
@export var lowercase_input: bool = true
## One sample per entry: a name, a sentence, a paragraph.
@export var samples := PackedStringArray()
## Optional res:// plain-text files, one sample per line. Plain text is not a
## Godot resource, so such files must be listed in the export preset's
## non-resource filter to survive an export — inline `samples` always do.
@export var source_files := PackedStringArray()
## Prose files are paragraphs, not samples; split them on sentence enders
## instead of feeding the chain one enormous line.
@export var split_sentences: bool = false


func collect_samples() -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(samples)
	for path in source_files:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_warning("[Markov] Corpus '%s' could not read %s" % [id, path])
			continue
		out.append_array(_split(text))
	return out


func _split(text: String) -> PackedStringArray:
	if not split_sentences:
		return text.split("\n", false)
	var out := PackedStringArray()
	var buffer := ""
	for i in text.length():
		var c := text[i]
		buffer += c
		if c == "." or c == "!" or c == "?":
			out.append(buffer.strip_edges())
			buffer = ""
	if not buffer.strip_edges().is_empty():
		out.append(buffer.strip_edges())
	return out
