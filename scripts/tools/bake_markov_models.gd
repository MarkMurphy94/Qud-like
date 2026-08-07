@tool
extends EditorScript

## Bakes every MarkovCorpus in resources/markov/corpora/ into a MarkovModel in
## resources/markov/models/, named after the corpus id.
##
## HOW TO RUN
##   1. Open this file in the Godot script editor.
##   2. File > Run  (Ctrl+Shift+X).
##   3. Read the report in the Output panel.
##
## Baking is optional. TextGenerator trains any corpus it needs on demand, so
## this is only worth running once a corpus is large enough (word-level prose,
## mostly) for that training pass to be a visible hitch at startup. A baked
## model is picked up automatically — nothing needs rewiring.
##
## It is idempotent: re-run after editing a corpus. Delete a model file to go
## back to on-demand training.

const CORPUS_DIR := "res://resources/markov/corpora/"
const MODEL_DIR := "res://resources/markov/models/"

func _run() -> void:
	var dir := DirAccess.open(CORPUS_DIR)
	if dir == null:
		push_error("[Markov] No corpus folder at %s" % CORPUS_DIR)
		return
	DirAccess.make_dir_recursive_absolute(MODEL_DIR)

	var baked := 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var corpus := load(CORPUS_DIR + file_name) as MarkovCorpus
			if corpus == null:
				push_warning("[Markov] %s is not a MarkovCorpus — skipping" % file_name)
			elif corpus.id.is_empty():
				push_warning("[Markov] %s has no id — skipping" % file_name)
			else:
				var started := Time.get_ticks_msec()
				var model := MarkovTrainer.train(corpus)
				var path := "%s%s.tres" % [MODEL_DIR, corpus.id]
				var err := ResourceSaver.save(model, path)
				if err != OK:
					push_error("[Markov] Could not write %s (error %d)" % [path, err])
				else:
					baked += 1
					print("[Markov] %-20s %4d samples -> %5d contexts, %5d transitions (%d ms)"
						% [corpus.id, model.sample_count, model.contexts.size(),
							model.tokens.size(), Time.get_ticks_msec() - started])
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[Markov] Baked %d model(s) into %s" % [baked, MODEL_DIR])
	EditorInterface.get_resource_filesystem().scan()
