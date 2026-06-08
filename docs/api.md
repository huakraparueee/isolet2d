# isolet2d API

LÖVE 11.x library for stacked isometric maps (terrain, structures, NPCs).

**Entry module:** `require("isolet2d")`

**Typical loop:** `Iso.init(cfg)` → `Iso.load_map(src)` → each frame `Iso.tick(dt)` and `Iso.draw_map()`.

---

## Install

Copy all `.lua` files into your game (e.g. `lib/isolet2d/`) and extend `package.path`:

```lua
package.path = package.path .. ";lib/isolet2d/?.lua"
local Iso = require("isolet2d")
```

Internal modules use flat names (`stack`, `terrain`, …) and must live on the same path.

---

## Facade (`isolet2d.lua`)

### `Iso.init(raw)`

Build config from `raw`, load terrain/structure/NPC assets. Call once before any map work.

Must be called before `load_map`, `create_map`, or `layout_for`.

Optional: `raw.grid_point_per_tile` — positive integer sub-divisions per tile for the placement walk grid (default `2`). Higher values give finer movement but more nodes.

### `Iso.load_map(src)`

Replace the active map: `create_map(src)`, preload NPC sheets, set camera pan bounds from map geometry.

### `Iso.create_map(src)` → `map`

Build a map object without making it active. Use for multiple maps or custom lifecycle.

### `Iso.bind_grid(map, src)`

Attach helpers on `map` (height/walkability caches, `map.grid`, terrain color lookups, placement rebuild hooks). Called automatically by `create_map`.

### `Iso.layout_for(src)` → `layout`

Isometric layout table for a source (uses current config). `create_map` stores this on `map.layout`.

### `Iso.draw_map()`

Draw the active map in **design space**. Applies `Iso.camera` translate internally (`love.graphics.push` / `pop`).

Clears to `src.background` when set. Culls to the current camera viewport (`design_width` × `design_height` from config, offset by `Camera.pan_x` / `pan_y`).

Your game should set up window → design scaling **before** calling this (letterbox, canvas, etc.). See [Optional viewport helper](#optional-viewport-helper-viewlua).

### `Iso.tick(dt)`

Updates terrain animation jobs, event removals/updates, structure mode animations, and NPC movement. Flushes deferred NPC/structure ops after events.

### `Iso.update(dt)`

Events/terrain jobs only (no structure/NPC movement). Rare; prefer `tick`.

### `Iso.run(ev)` / `Iso.run_many(evs)`

Apply one event or a list. NPC and structure ops queued by events are flushed immediately after.

Pass an **array without** `type` on the outer table to run a sequence in one call.

### `Iso.is_busy()` → `boolean`

`true` while terrain add/update/remove animations or pending NPC spawn ops are in progress.

### `Iso.is_blocked()` → `boolean`

`true` when `is_busy()` or any NPC is walking / playing a one-shot mode.

Use before accepting player input during scripted sequences.

### `Iso.is_npc_anim_busy(id?)` → `boolean`

`true` while a matching NPC is playing a non-looping mode (`mode_busy`). Optional `id` filters by `npc_id` (string or array of ids). Walking does not count.

### `Iso.find_by_id(id)` → `piece | nil`

Find an NPC piece by `npc_id`.

### `Iso.each_npc_piece(fn)`

Call `fn(piece)` for each live NPC on the active map.

### `Iso.preload_npcs(_src)`

Load all NPC kind sheets from config. Called from `load_map`; safe to call after `init`.

### Movement helpers

These operate on the active map's `placement` graph (sub-tile walk nodes). NPC `walk_to` events use the same graph internally.

| Function                                                    | Returns       | Description                                                                 |
| ----------------------------------------------------------- | ------------- | --------------------------------------------------------------------------- |
| `Iso.pos_step()`                                            | `number`      | World distance between adjacent placement cells (`1 / grid_point_per_tile`) |
| `Iso.can_step_pos(from_px, from_py, to_px, to_py)`          | `boolean`     | Whether a direct step between world positions is allowed                    |
| `Iso.try_step_neighbor(from_px, from_py, cell_dx, cell_dy)` | `node \| nil` | Step to a neighboring placement cell if the edge is valid                   |
| `Iso.pick_placement_near(px, py, radius?)`                  | `node \| nil` | Random reachable node within `radius` (default `1`) of `(px, py)`           |
| `Iso.on_walkable_cell(piece)`                               | `boolean`     | Whether the piece's `pos_x` / `pos_y` sits on a live placement node         |

Placement nodes expose `ix`, `iy`, `px`, `py`, `z`, `tile_x`, `tile_y`, `sx`, `sy`.

### Debug

| Function                              | Description                                                              |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `Iso.set_debug_draw_walkable(enable)` | Toggle overlay of placement nodes (green) and NPC anchor positions (red) |
| `Iso.debug_draw_walkable()`           | Current debug-draw flag                                                  |

Can also set `debug_draw_walkable = true` in the init config.

### `Iso.camera`

Submodule for panning in design space (see [Camera](#camera-module)).

---

## Configuration (`Iso.init`)

| Field                 | Type     | Description                                     |
| --------------------- | -------- | ----------------------------------------------- |
| `design_width`        | number   | Design resolution width (viewport + camera)     |
| `design_height`       | number   | Design resolution height                        |
| `grid_origin_x`       | number   | World tile X of stack column 0                  |
| `grid_origin_y`       | number   | World tile Y of stack row 0                     |
| `tile_size`           | number   | Base tile size in pixels                        |
| `iso_x_ratio`         | number   | Half-width factor (default-style: `0.5`)        |
| `iso_y_ratio`         | number   | Depth factor (e.g. `0.25`)                      |
| `iso_eh_ratio`        | number   | Block height factor (e.g. `0.5`)                |
| `terrain_mats`        | table    | Material id → spec (see below)                  |
| `structures`          | table    | Structure kind → spec                           |
| `npcs`                | table    | NPC kind → spec                                 |
| `terrain_stack_top`   | string?  | Material id for top stack layer sprite fallback |
| `terrain_stack_fill`  | string?  | Material id for lower stack layers fallback     |
| `grid_point_per_tile` | number?  | Sub-tile walk grid density (default `2`)        |
| `debug_draw_walkable` | boolean? | Enable placement debug overlay                  |

### `terrain_mats[id]`

| Field      | Description                                                                                            |
| ---------- | ------------------------------------------------------------------------------------------------------ |
| `color`    | `{ r, g, b }` for solid cubes (0–1)                                                                    |
| `walkable` | `false` to block pathfinding on that mat                                                               |
| `alpha`    | Default piece alpha                                                                                    |
| `path`     | Image path (square sprite, variant list, or sheet)                                                     |
| `w`, `h`   | Frame size for animated sheet                                                                          |
| `cols`     | Grid spec for anim8 (e.g. `"1-4"` or number)                                                           |
| `row`      | Sheet row for `cols` (default `1`)                                                                     |
| `interval` | Animation step time (default `0.15`)                                                                   |
| `modes`    | Mode name → `{ cols, interval, loop?, count?, pause?, after_mode?, row? }` for animated terrain sheets |
| `autotile` | `true` to pick variant by neighbor mask                                                                |
| `variants` | Variant name → path string or array of paths (random pick when array)                                  |

Solid color blocks need `color`. Simple sprites need `path`. Animated sheets need `path`, `w`, `h`, and `modes` (or legacy single-frame `cols`). Autotile materials need `autotile = true` and a `variants` table.

Autotile variant names: `solo`, `n`, `e`, `s`, `w`, `n_e`, `e_s`, `n_s`, `w_s`, `w_e`, `n_e_s`, `n_w_s`, `w_e_s`, `w_n_e`, `full` (from N/E/S/W neighbor bitmask).

### `structures[kind]`

| Field                           | Description                                                                                         |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| `path`                          | Sprite path                                                                                         |
| `w`, `h`                        | Frame size in pixels                                                                                |
| `sheet_w`, `sheet_h`            | Optional full sheet size check                                                                      |
| `tiles_w`, `tiles_d`, `tiles_h` | Footprint (default `1`)                                                                             |
| `modes`                         | Mode name → `{ cols, interval, loop?, count?, pause?, after_mode?, row? }`. Omit for static frame 1 |

### `npcs[kind]`

| Field                            | Description                                         |
| -------------------------------- | --------------------------------------------------- |
| `path`                           | Sprite sheet path                                   |
| `sheet_w`, `sheet_h`             | Full sheet size                                     |
| `w`, `h`                         | Frame size                                          |
| `tiles_w`, `tiles_d`, `tiles_h`  | Footprint (default `1`)                             |
| `draw_offset_x`, `draw_offset_y` | Screen offset from feet anchor                      |
| `facing`                         | Default facing (`"left"`, `"right"`, or 8-dir name) |
| `modes`                          | Mode name → clip spec (see below)                   |

**Mode spec** — either a flat clip or directional:

```lua
-- Left/right flip from one clip
stand = { cols = "1", interval = 0.2, pause = true }

-- Per-direction clips (dir names: e, se, s, sw, w, nw, n, ne)
walk = {
    cols = "1-4",
    interval = 0.1,
    loop = true,
    dirs = {
        e  = { cols = "1-4" },
        se = { cols = "5-8", flip = "h" },  -- flip: "h", "v", or "hv"
    },
}
```

NPC `facing` on spawn: `"left"`, `"right"`, or any 8-dir name. Walking updates facing from path segments (8-dir when the active mode has `dirs`).

---

## Map source (`load_map` / `create_map`)

| Field                | Description                                                               |
| -------------------- | ------------------------------------------------------------------------- |
| `stacks`             | 2D array of strings: each cell is bottom→top stack; `"."` or `""` = empty |
| `stack_chars`        | Maps stack character → material id in `terrain_mats`                      |
| `tiles_w`, `tiles_d` | Optional; inferred from `stacks` if omitted                               |
| `background`         | Optional `{ R, G, B }` used as clear color in `draw_map`                  |

`Stack.height(src, row, col)` (internal) counts non-empty layers in a cell.

Example:

```lua
local map_src = {
    stacks = {
        { "g.", "gg", "g.." },
        { ".g", "ggg", "g" },
    },
    stack_chars = {
        g = "grass",
        ["."] = "air",
    },
    background = { R = 0.15, G = 0.2, B = 0.25 },
}
```

---

## Events

Handled by `events.lua`. Terrain jobs run during `tick`; NPC and structure ops are queued then flushed.

### Event types

#### `terrain.add`

| Field              | Required | Description                                  |
| ------------------ | -------- | -------------------------------------------- |
| `tile_x`, `tile_y` | yes      | Tile coordinates                             |
| `tile_z`           | no       | Layer index; default = current height        |
| `mat`              | no       | Material id                                  |
| `color`            | no       | Override RGB table; else from `terrain_mats` |
| `alpha`            | no       | Override alpha                               |

#### `terrain.update`

| Field                   | Required | Description                                 |
| ----------------------- | -------- | ------------------------------------------- |
| `tile_x`, `tile_y`      | yes      | Target cell                                 |
| `tile_z`                | no       | Specific layer; default top terrain at cell |
| `mat`, `color`, `alpha` | no       | Target state                                |
| `duration`              | no       | Fade seconds; `0` or omit = instant         |

#### `terrain.remove`

| Field              | Required | Description                   |
| ------------------ | -------- | ----------------------------- |
| `tile_x`, `tile_y` | yes      | Target cell                   |
| `tile_z`           | no       | Specific layer                |
| `duration`         | no       | Fade out time (default `0.3`) |

#### `structure.add`

| Field                                 | Required | Description                |
| ------------------------------------- | -------- | -------------------------- |
| `kind` or `structure`                 | yes      | Structure kind from config |
| `id` or `structure_id`                | yes      | Unique id                  |
| `tile_x`, `tile_y`                    | yes      | Anchor tile                |
| `mode`, `loop`, `count`, `after_mode` | no       | Initial animation playback |

Fails silently if out of bounds, unknown kind, id exists, or footprint blocked.

#### `structure.remove`

| Field                  | Description          |
| ---------------------- | -------------------- |
| `id` or `structure_id` | Remove by id         |
| `tile_x`, `tile_y`     | Or remove at tile    |
| `duration`             | Fade (default `0.3`) |

#### `structure.set_mode`

| Field                         | Required | Description                   |
| ----------------------------- | -------- | ----------------------------- |
| `mode`                        | yes      | Mode name                     |
| `id` or `structure_id`        | no       | Filter; omit = all structures |
| `loop`, `count`, `after_mode` | no       | Playback options              |

#### `npc.add`

| Field                           | Required | Description                          |
| ------------------------------- | -------- | ------------------------------------ |
| `id`                            | yes      | NPC id                               |
| `kind`                          | yes      | Kind from `npcs` config              |
| `tile_x`, `tile_y`              | yes      | Spawn tile                           |
| `facing`                        | no       | `"left"`, `"right"`, or 8-dir name   |
| `mode`                          | no       | Initial mode (default catalog stand) |
| `loop`, `count`, `after_mode`   | no       | Initial animation playback           |
| `tiles_w`, `tiles_d`, `tiles_h` | no       | Footprint overrides                  |

#### `npc.set_mode`

| Field                         | Required | Description             |
| ----------------------------- | -------- | ----------------------- |
| `mode`                        | yes      | Mode name               |
| `id` or `npc_id`              | no       | Filter; omit = all NPCs |
| `loop`, `count`, `after_mode` | no       | Playback options        |

#### `npc.walk_to`

| Field                                      | Required | Description                                           |
| ------------------------------------------ | -------- | ----------------------------------------------------- |
| `tile_x`, `tile_y` **or** `pos_x`, `pos_y` | yes      | Destination (tile anchor or placement world position) |
| `id` or `npc_id`                           | no       | Filter; omit = all NPCs                               |

Pathfinding uses `map.placement` nodes and height rules via `map.grid`.

### Examples

```lua
Iso.run({ type = "terrain.add", tile_x = 2, tile_y = 1, mat = "dirt" })

Iso.run_many({
    { type = "npc.add", id = "hero", kind = "player", tile_x = 1, tile_y = 1 },
    { type = "npc.walk_to", id = "hero", tile_x = 5, tile_y = 3 },
})

-- Walk to sub-tile position
Iso.run({ type = "npc.walk_to", id = "hero", pos_x = 2.25, pos_y = 1.75 })

-- Sequence in one call (array without .type)
Iso.run({
    { type = "terrain.add", tile_x = 0, tile_y = 0, mat = "grass" },
    { type = "npc.add", id = "a", kind = "player", tile_x = 0, tile_y = 0 },
})
```

---

## Placement graph

Built on `create_map` and stored as `map.placement`. Rebuilt per tile when terrain or structures change occupancy.

Each **node** is a walkable sub-tile position:

| Field              | Description                                   |
| ------------------ | --------------------------------------------- |
| `ix`, `iy`         | Integer placement cell indices                |
| `px`, `py`         | World position in tile units (center of cell) |
| `z`                | Surface height at backing tile                |
| `tile_x`, `tile_y` | Backing map tile                              |
| `sx`, `sy`         | Screen feet position (from layout)            |

A tile with `grid_point_per_tile = 2` has up to four nodes per walkable cell (when not blocked by structures).

`map.rebuild_placement_tile(tile_x, tile_y)` refreshes nodes for one tile after custom edits.

---

## Camera module

`Iso.camera` — pan in design coordinates.

| Member / function  | Description                                                                |
| ------------------ | -------------------------------------------------------------------------- |
| `pan_x`, `pan_y`   | Current pan offset                                                         |
| `apply()`          | `love.graphics.translate(pan_x, pan_y)` (used by `draw_map`)               |
| `pan(dx, dy)`      | Move pan, clamped to bounds                                                |
| `reset()`          | Pan to origin                                                              |
| `set_bounds(opts)` | `min_x`, `min_y`, `max_x`, `max_y`, `view_w`, `view_h` — set by `load_map` |
| `clear_bounds()`   | Remove clamping                                                            |
| `clamp()`          | Re-clamp after manual `pan_x` / `pan_y` changes                            |

---

## Map object (`create_map`)

Returned table (selected fields):

| Field                                  | Description                                  |
| -------------------------------------- | -------------------------------------------- |
| `source`                               | Map source table                             |
| `pieces`                               | All pieces (terrain, structures, NPCs)       |
| `structure_pieces`, `npc_pieces`       | Cached lists for drawing                     |
| `layout`                               | Ground layout from `layout_for`              |
| `placement`                            | Walk-node graph (`nodes`, `by_cell`)         |
| `grid`                                 | See below                                    |
| `height_at_cache`, `walkable_at_cache` | Per-tile caches                              |
| `terrain_bake_max_z`                   | Highest baked terrain Z (internal draw hint) |

### `map.grid`

| Function               | Returns                               |
| ---------------------- | ------------------------------------- |
| `height_at(tx, ty)`    | Stack height at tile                  |
| `walkable_at(tx, ty)`  | Walkable from top surface material    |
| `surface_z(tx, ty)`    | Top occupied Z (`height - 1`, or `0`) |
| `in_bounds(tx, ty)`    | Inside map                            |
| `structure_span(kind)` | `tiles_w, tiles_d, tiles_h`           |

### Other `map` helpers (from `bind_grid`)

- `refresh_height_at(tx, ty)` — update height/walkable caches and rebuild placement for that tile
- `rebuild_placement_tile(tx, ty)` — refresh placement nodes only
- `sync_structure_pieces()` / `sync_npc_pieces()` — rebuild cached draw lists
- `terrain_mat_color(mat)` → `r, g, b`
- `terrain_mat_alpha(mat)`
- `apply_terrain_mat(piece, mat)`
- `has_structure_kind(kind)`

---

## Module files (internal)

| File            | Role                           |
| --------------- | ------------------------------ |
| `isolet2d.lua`  | Public facade                  |
| `setup.lua`     | Config get/set                 |
| `stack.lua`     | Stack grid parsing             |
| `tile.lua`      | Tile ↔ screen projection       |
| `ground.lua`    | Isometric math, placement grid |
| `terrain.lua`   | Terrain draw, baking, autotile |
| `structure.lua` | Structure sprites and modes    |
| `npc.lua`       | NPC animation and walking      |
| `placement.lua` | Walk-node graph                |
| `walk.lua`      | Pathfinding on placement graph |
| `events.lua`    | Event dispatch                 |
| `occupancy.lua` | Tile occupancy                 |
| `footprint.lua` | Screen anchors                 |
| `pieces.lua`    | Piece queries                  |
| `lookup.lua`    | Config lookups                 |
| `camera.lua`    | Pan                            |
| `anim8.lua`     | Vendored anim8 v2.3.1          |

Prefer the facade API; require submodules only for advanced integration.
