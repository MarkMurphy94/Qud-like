| File | Role |
|---|---|
| markov_model.gd | Trained chain, stored as flat CSR packed arrays |
| markov_corpus.gd | Training input + tokenizer settings |
| markov_profile.gd | One *use* of a chain — length, casing, affixes, template |
| markov_trainer.gd | Corpus → model, plus the shared tokenizer |
| text_generator.gd | `TextGenerator` autoload — the only thing callers touch |
| bake_markov_models.gd | Optional EditorScript baker |

Plus corpora (173 place names, 122 given names) and profiles (`place_name`, `npc_given_name`, `npc_full_name`). `TextGenerator` is registered in project.godot, and province_map.gd now names provinces through it, keeping the old head/tail table as a fallback.

---

# How to use it

## 1. Generating text

```gdscript
TextGenerator.generate("place_name")                  # random each call
TextGenerator.generate("npc_given_name")
TextGenerator.generate("npc_full_name")               # "Wystan of Oakenhollow"
```

**Reproducible output** — pass a seed derived from whatever identifies the thing:

```gdscript
TextGenerator.generate("place_name", TextGenerator.seed_from(tile))     # Vector2i
TextGenerator.generate("npc_given_name", TextGenerator.seed_from(npc_id))  # String
```

`seed_from()` accepts `int`, `Vector2i`, or anything stringable. Same key → same text, every run. That's why generated names don't need saving.

**Batches** (one seeded stream, entries differ but the whole batch repeats):

```gdscript
var roster := TextGenerator.generate_many("npc_given_name", 12, TextGenerator.seed_from(town_key))
```

**Template slots** — override any slot with live game state:

```gdscript
TextGenerator.generate("tavern_bark", -1, {"place_name": province.display_name})
```

## 2. Adding a new naming style (no code)

1. Copy place_names.tres → e.g. `dwarven_names.tres`. Set `id` to `"dwarven_names"` and replace `samples`. **~100+ samples minimum** — below ~60 the chain mostly regurgitates its input.
2. Copy place_name.tres → `dwarven_place_name.tres`. Set `id` to `"dwarven_place_name"` and point `corpus` at the new corpus.
3. Call `TextGenerator.generate("dwarven_place_name")`. Nothing else. Profiles are auto-discovered from the folder at startup.

Profile knobs worth knowing:
- `min_length` / `max_length` — in **tokens** (characters for CHAR mode, words for WORD). A draw outside the range is thrown away and redrawn, up to `max_attempts`.
- `reject_source_forms` — discards output identical to a training sample. Leave on.
- `casing` — `CAPITALIZE` for names, `SENTENCE_CASE` for prose, `NONE` for templates.
- `prefixes` / `suffixes` + `affix_chance` — `place_name` uses this at 0.12, so roughly one settlement in eight comes out as *"Upper Cinderholt"*.

Corpus knobs: `order` (3 is the sweet spot for names — 4 is cleaner but noticeably repetitive; I tested both), `lowercase_input` (on for names, **off** for prose so proper nouns survive).

## 3. Books and dialogue (word mode)

Same pipeline, one setting different. On the corpus set `mode = WORD`, `order = 2`, `lowercase_input = false`, `split_sentences = true`, and put the text in `source_files` as `res://` paths to `.txt`. On the profile use `min_length`/`max_length` in *words* (e.g. 20/80) and `casing = SENTENCE_CASE`.

Two caveats:
- **Free-running word chains are atmospheric nonsense.** Great for a mad hermit's grimoire or drunk tavern chatter; useless for anything the player must act on. For meaningful lines use a template profile and let Markov fill only the flavour slots.
- `.txt` files aren't Godot resources. Add `*.txt` to the export preset's *"Filters to export non-resource files"* or they'll be missing from a build. Inline `samples` always ship.

## 4. Baking (optional, later)

Models are trained on demand the first time a profile is used and cached for the session — you don't need to do anything for the name corpora. Once a prose corpus gets big enough for that to hitch at startup:

1. Open bake_markov_models.gd in the script editor.
2. **File → Run** (Ctrl+Shift+X).
3. Models land in `resources/markov/models/<corpus_id>.tres` and are picked up automatically — no rewiring. Delete a model file to go back to on-demand training.

Re-run after editing a corpus, or the stale baked model wins. (In a running editor session, `TextGenerator.clear_cache()` forces a retrain.)

## 5. Verifying it works

Run the game and check the Output panel for `[TextGenerator] Loaded 3 profiles`, then open the political map (`toggle_provinces`) — province names should now read like *Sanderfell* / *Thrushmerdale* rather than the old `Thramark` head/tail combinations.

---

Next up when you want it: NPC names wired into npc_spawner.gd keyed off `npc_id`, then word-mode prose into `ItemBook.full_text`.

Made changes.