# Creating Settlement / Location Scenes

The canonical generator is `scripts/map_generator.gd` (`MapGenerator`, a `@tool`
script). Authoring happens in a generator scene (e.g.
`scenes/new_tileset_test_town.tscn`), and one click bakes the result into a
standalone static scene.

## Authoring workflow

1. Open a generator scene (`new_tileset_test_town.tscn`, or duplicate it for a
   new location). Select the root node.
2. In the inspector, configure the **Map Template** (MapConfig):
   - `map_name` — becomes the baked scene's filename (snake_cased)
   - `map_type` (SETTLEMENT etc.), `building_density`, densities, `road_exits`
   - `overworld_tile` — the overworld Vector2i this location will occupy.
     **Required** for runtime layout persistence (it keys the
     MainGameState.settlements entry). Find coords by opening the OverworldMap
     scene and hovering the tilemap (coords show bottom-left).
   - `SEED` — 0 rolls a new seed per Generate click; non-zero reproduces.
3. Click **Generate** (inspector button under *Editor Tools*). Repeat until you
   like the layout; hand-edit tiles/buildings freely afterwards.
4. Click **Bake To Scene**. The scene is written to
   `bake_dir/<map_name>.tscn` (default `res://scenes/generated/`) with
   `generate_on_ready = false`, its own deep-copied MapConfig, and all painted
   layers + building instances intact. Baked scenes keep the MapGenerator
   script, so they automatically satisfy the loader contract
   (`tilemaps["GROUND"]`, `is_walkable()`, `map_template` for the NPC spawner)
   — no snippet script needed.

## Wiring the baked scene into the game

5. In `game.tscn`, under a category node (`town_tiles`, `city_tiles`, …), add a
   `local_map_tile.tscn` instance positioned on the overworld tile. Set:
   - `scene_path` — the baked scene's `res://` path
   - `tile_metadata` — a new TileMetadata whose `coords` **match the
     MapConfig's `overworld_tile`** (this drives the player's return position)
6. Optionally add the same coords → scene path entry to the OverworldMap's
   Settlements List (used as a fallback when the player isn't standing on a
   LocalMapTile).

## Runtime behavior notes

- **Wilderness** (tiles with no LocalMapTile/settlement): `AreaContainer`
  instantiates `scenes/wilderness_area.tscn` and calls
  `generate_local_map(metadata)`. The tile's seed is rolled once on first
  visit (`main_game.prepare_tile_visit`) and persisted with the save, so
  revisits reproduce the same map.
- **Generated settlements** (MapConfig with empty `buildings`): the layout is
  generated once, stored in `MainGameState.settlements` (saved with the game),
  and rebuilt identically on every revisit via `build_settlement_from_dataset()`.
- **Baked scenes** never regenerate (`generate_on_ready = false`); their tiles
  load exactly as saved.
