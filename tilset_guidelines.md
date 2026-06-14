Looking at the tileset's existing structure (it already uses `category`, `type`, `tag_1`, `tag_2` string layers and has a few tiles partially tagged like `"decor_exterior" / "armor rack" / "military"`), here's a coherent taxonomy that fits the catalog system your proc gen already uses:

---

### Layer 0 — `category` (what the proc gen selects)

| Value | Used for |
|---|---|
| `"building_exterior"` | Large multi-tile exterior sprites (houses, tavern, manor) |
| `"building_interior"` | Interior floor/room sprites |
| `"structure"` | Walls, fences, gates, towers, palisades |
| `"prop_exterior"` | Props scattered outside buildings (barrels, crates, ballistas) |
| `"prop_interior"` | Furniture/props placed inside buildings |
| `"vehicle"` | Carts, wagons |

---

### Layer 1 — `type` (specific sprite within category)

- **building_exterior / interior**: `"house"`, `"shop"`, `"tavern"`, `"manor"`, `"tower"`, `"tent"`, `"large_tent"`, `"farmhouse"`
- **structure**: `"stone_wall"`, `"wooden_fence"`, `"palisade"`, `"gate"`, `"battlement"`, `"crenellation"`
- **prop_exterior**: `"barrel"`, `"crate"`, `"well"`, `"market_stall"`, `"ballista"`, `"armor_rack"`, `"weapon_rack"`, `"empty_rack"`, `"notice_board"`
- **prop_interior**: `"barrel"`, `"crate"`, `"chest"`, `"bed"`, `"table"`, `"chair"`, `"shelf"`, `"counter"`, `"forge"`, `"bookshelf"`, `"fireplace"`

---

### Layer 2 — `tag_1` (affiliation — filters props by building purpose)

`"civilian"`, `"military"`, `"merchant"`, `"religious"`, `"arcane"`

This lets `generate_settlement()` do things like: *"for a tavern interior, pick `prop_interior` tiles where `tag_1 == "civilian"`"*.

---

### Layer 3 — `tag_2` (placement hint — used by layout logic)

| Value | Meaning |
|---|---|
| `"blocking"` | Impassable — update `is_walkable()` to check prop layer |
| `"passable"` | Decorative, player can walk through |
| `"wall_adjacent"` | Should be placed flush against a wall |
| `"corner"` | Intended for corners (racks, forges) |
| `"rare"` | Low spawn weight in random placement |

---

### Why this fits your existing code

- `_build_tile_catalog()` already indexes by `category → type`, so `tile_catalog["prop_exterior"]["ballista"]` works immediately
- `tag_1` affiliation maps cleanly to `Structure.StructureType` — a `SHOP` interior would draw from `tag_1 == "merchant"`, a guard barracks from `"military"`
- `tag_2 == "blocking"` gives you a clean hook to extend `is_walkable()` to check the interior/prop layers without hardcoding atlas coordinates
- The existing partial tags (`"decor_exterior"` / `"armor rack"` / `"military"`) just need `category` renamed to `"prop_exterior"` and `tag_2` added to match the new schema