# isolet2d API

LÖVE 11.x library for stacked isometric maps (terrain, structures, NPCs).

**Entry module:** `require("isolet2d")`

**Typical loop:** `Iso.init(cfg)` → `Iso.load_map(src)` → each frame `Iso.tick(dt)` and `Iso.draw_map()`.

**Example game:** [bullet2d](https://github.com/huakraparueee/bullet2d) — wave-based bullet-hell demo with pre-spawned stages, enemy scaling, player upgrades, `npc.shoot` / `projectile.spawn`, `on_hit` callbacks, and placement-graph player movement.

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

Your game should set up window → design scaling **before** calling this (letterbox, canvas, etc.).

### `Iso.tick(dt)`

Runs terrain animation jobs and removals, updates in-flight projectiles, flushes deferred NPC/structure/projectile ops, then updates structure mode animations and NPC movement.

### `Iso.update(dt)`

Events/terrain jobs only (no structure/NPC movement). Rare; prefer `tick`.

### `Iso.run(ev)` / `Iso.run_many(evs)`

Apply one event or a list. NPC and structure ops queued by events are flushed immediately after.

Pass an **array without** `type` on the outer table to run a sequence in one call.

### `Iso.is_busy()` → `boolean`

`true` while terrain add/update/remove animations or pending NPC spawn ops are in progress.

### `Iso.is_blocked()` → `boolean`

`true` when `is_busy()`, any NPC is walking / playing a one-shot mode, or any projectile is in flight (including delayed spawns).

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

### Coordinate helpers

| Function                                   | Returns        | Description                                                        |
| ------------------------------------------ | -------------- | ------------------------------------------------------------------ |
| `Iso.placement_pos(ix, iy)`                | `px, py \| nil` | World position of a placement cell, or `nil` if missing             |
| `Iso.placement_to_design(px, py, tile_z?)` | `x, y`         | Screen position in design space (includes current camera pan)      |

### Picking (design space)

Pass **design-space** coordinates (after your window→design transform, **before** camera pan — the functions subtract pan internally).

| Function                                | Returns   | Description                                                                 |
| --------------------------------------- | --------- | --------------------------------------------------------------------------- |
| `Iso.query_at_design(design_x, design_y)` | `table \| nil` | Full hit query (see below)                                            |
| `Iso.pick_at_design(design_x, design_y)`  | `table \| nil` | Tile under the cursor only (lighter)                                    |
| `Iso.set_pick_marker(wx, wy)`             | —         | Set or clear (`nil`) the debug pick marker in map-local coordinates         |

`query_at_design` return value (when not `nil`):

| Field         | Description                                                                 |
| ------------- | --------------------------------------------------------------------------- |
| `wx`, `wy`    | Map-local coordinates (camera pan subtracted)                               |
| `tile`        | `{ x, y, z, walkable, in_bounds, mat? }` — top terrain tile at pointer      |
| `placement`   | `{ x, y, z }` — nearest placement cell (`ix`, `iy`, surface `z`), if any    |
| `structure`   | `{ structure_id, kind }` — structure on tile or under sprite hit            |
| `npc`         | `{ npc_id, kind }` — NPC under sprite hit, if any                           |
| `target`      | `"npc"`, `"structure"`, `"ground"`, or omitted                              |

Sprite hits use an axis-aligned box anchored at the entity feet. Optional `hit = { w, h }` on NPC/structure config overrides the default (`w`/`h` from the sprite frame).

`pick_at_design` returns `{ tile_x, tile_y, z, in_bounds, walkable, sx, sy, wx, wy }`.

Successful `query_at_design` calls also update the pick marker when `debug_draw_map` is enabled.

### Projectile helpers

| Function                    | Description                                      |
| --------------------------- | ------------------------------------------------ |
| `Iso.clear_projectiles()`   | Remove all in-flight projectiles on the active map |
| `Iso.projectile_count()`    | Number of live projectiles                       |
| `Iso.each_projectile(fn)`   | Call `fn(projectile)` for each live projectile   |

### Pause controls

Pause flags stop **updates** for that layer during `tick`; drawing still runs. `is_blocked()` is unchanged (walking NPCs and in-flight projectiles still block input unless cleared).

| Function / alias                              | Description                          |
| --------------------------------------------- | ------------------------------------ |
| `Iso.set_npc_paused(paused)` / `pause_npc()` / `play_npc()` | Freeze or resume NPC movement and mode animation |
| `Iso.is_npc_paused()`                         | Current NPC pause flag               |
| `Iso.set_structure_paused(paused)` / `pause_structure()` / `play_structure()` | Freeze or resume structure mode animation |
| `Iso.is_structure_paused()`                   | Current structure pause flag         |
| `Iso.set_projectile_paused(paused)` / `pause_projectile()` / `play_projectile()` | Freeze or resume projectile motion |
| `Iso.is_projectile_paused()`                  | Current projectile pause flag        |

Flags live on the active map as `map.npc_paused`, `map.structure_paused`, `map.projectile_paused`.

### Debug

| Function                         | Description                                                                                  |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| `Iso.set_debug_draw_map(enable)` | Toggle map debug overlay                                                                     |
| `Iso.debug_draw_map()`           | Current debug-draw flag                                                                      |

When enabled, `draw_map` overlays:

- Placement walk nodes (green)
- NPC and structure sprite hit boxes (cyan / magenta)
- NPC placement anchor positions (red)
- Last pick marker from `query_at_design` (yellow)

Can also set `debug_draw_map = true` in the init config.

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
| `map_offset_y`        | number?  | Shift map anchor down on screen (default `0`)   |
| `tile_size`           | number   | Base tile size in pixels                        |
| `iso_x_ratio`         | number   | Half-width factor (default-style: `0.5`)        |
| `iso_y_ratio`         | number   | Depth factor (e.g. `0.25`)                      |
| `iso_eh_ratio`        | number   | Block height factor (e.g. `0.5`)                |
| `terrain_mats`        | table    | Material id → spec (see below)                  |
| `structures`          | table    | Structure kind → spec                           |
| `npcs`                | table    | NPC kind → spec                                 |
| `projectiles`         | table?   | Projectile kind → spec (see below)              |
| `terrain_stack_top`   | string?  | Material id for top stack layer sprite fallback |
| `terrain_stack_fill`  | string?  | Material id for lower stack layers fallback     |
| `grid_point_per_tile` | number?  | Sub-tile walk grid density (default `2`)        |
| `debug_draw_map`      | boolean? | Enable map debug overlay (placement, hits, pick) |

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
| `hit`                           | Optional `{ w, h }` sprite hit box for `query_at_design` (defaults to frame `w`/`h`)                |
| `modes`                         | Mode name → `{ cols, interval, loop?, count?, pause?, after_mode?, row? }`. Omit for static frame 1 |

### `npcs[kind]`

| Field                            | Description                                         |
| -------------------------------- | --------------------------------------------------- |
| `path`                           | Sprite sheet path                                   |
| `sheet_w`, `sheet_h`             | Full sheet size                                     |
| `w`, `h`                         | Frame size                                          |
| `tiles_w`, `tiles_d`, `tiles_h`  | Footprint (default `1`)                             |
| `draw_offset_x`, `draw_offset_y` | Screen offset from feet anchor                      |
| `hit`                            | Optional `{ w, h }` sprite hit box for `query_at_design` (defaults to frame `w`/`h`) |
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

### `projectiles[kind]`

| Field            | Description                                                    |
| ---------------- | -------------------------------------------------------------- |
| `path`           | Optional sprite path (falls back to a colored circle)          |
| `w`, `h`         | Frame size when using a sprite                                 |
| `move`           | `"arc"` (default) or `"line"`                                  |
| `duration`       | Flight time in seconds (default `0.45`)                        |
| `arc_height`     | Screen-space arc peak for `move = "arc"` (default `40`)        |
| `radius`         | Draw radius when no sprite (default `5`)                       |
| `color`          | `{ r, g, b }` for procedural draw (default `{ 1, 0.85, 0.3 }`) |
| `draw_offset_x`  | Screen offset from trajectory anchor                           |
| `draw_offset_y`  | Screen offset from trajectory anchor                           |

Default kind when omitted on spawn events: `"bolt"`.

---

## Map source (`load_map` / `create_map`)

| Field                | Description                                                               |
| -------------------- | ------------------------------------------------------------------------- |
| `stacks`             | 2D array of strings: each cell is bottom→top stack; `"."` or `""` = empty |
| `stack_chars`        | Maps stack character → material id in `terrain_mats`                      |
| `tiles_w`, `tiles_d` | Optional; inferred from `stacks` if omitted                               |
| `background`         | Optional `{ R, G, B }` used as clear color in `draw_map`                  |
| `map_offset_y`       | Optional per-map vertical screen offset (overrides init `map_offset_y`)   |

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

#### `npc.remove`

| Field              | Required | Description                          |
| ------------------ | -------- | ------------------------------------ |
| `id` or `npc_id`   | yes      | NPC to remove                        |
| `duration`         | no       | Fade out time; omit or `0` = instant |

#### `npc.shoot`

Fires a projectile from an NPC, optionally playing a `shoot` or `action` mode first.

| Field                                      | Required | Description                                           |
| ------------------------------------------ | -------- | ----------------------------------------------------- |
| `id` or `npc_id`                           | yes      | Shooter NPC                                           |
| `tile_x`, `tile_y` **or** `to` / `to_px`   | yes      | Target (same shapes as `projectile.spawn` `to`)       |
| `kind` or `projectile`                     | no       | Projectile kind (default `"bolt"`)                    |
| `mode`                                     | no       | NPC mode to play; defaults to `shoot` or `action`     |
| `loop`, `count`, `after_mode`              | no       | Playback for the shoot mode                           |
| `delay`                                    | no       | Seconds before spawning the projectile                |
| `on_hit`                                   | no       | Event or event list run when the projectile lands     |
| `move`, `duration`, `arc_height`           | no       | Override projectile motion                            |
| `projectile_id`                            | no       | Custom id for the spawned projectile                  |

#### `projectile.spawn`

| Field                                      | Required | Description                                           |
| ------------------------------------------ | -------- | ----------------------------------------------------- |
| `kind` or `projectile`                     | no       | Kind from `projectiles` config (default `"bolt"`)     |
| `from`                                     | no*      | `{ npc_id }`, `{ px, py, z? }`, or `{ tile_x, tile_y }` |
| `to`                                       | no*      | `{ px, py, z? }` or `{ tile_x, tile_y, tiles_w?, tiles_d? }` |
| `npc_id` or `id`                           | no       | Shorthand origin from this NPC (`id` alone implies NPC origin) |
| `from_px`, `from_py`, `from_z`             | no       | Shorthand world origin (use with `from` table, not with `id`) |
| `tile_x`, `tile_y`                         | no       | Shorthand tile target (center of footprint)           |
| `to_px`, `to_py`, `to_z`                   | no       | Shorthand world target                                |
| `move`, `duration`, `arc_height`           | no       | Motion overrides                                      |
| `draw_offset_x`, `draw_offset_y`           | no       | Draw offset overrides                                 |
| `on_hit`                                   | no       | Event or event list dispatched on impact              |

\* Provide origin via `from`, `npc_id`/`id`, or `from_px`/`from_py`. Provide target via `to`, `tile_x`/`tile_y`, or `to_px`/`to_py`. Projectile instance ids are auto-generated (`proj_1`, …) unless set via `npc.shoot`'s `projectile_id`.

`on_hit` runs through the same event dispatcher as `Iso.run` (terrain changes, secondary spawns, etc.).

### Examples

```lua
Iso.run({ type = "terrain.add", tile_x = 2, tile_y = 1, mat = "dirt" })

Iso.run_many({
    { type = "npc.add", id = "hero", kind = "player", tile_x = 1, tile_y = 1 },
    { type = "npc.walk_to", id = "hero", tile_x = 5, tile_y = 3 },
})

-- Walk to sub-tile position
Iso.run({ type = "npc.walk_to", id = "hero", pos_x = 2.25, pos_y = 1.75 })

-- Shoot with on_hit terrain update
Iso.run({
    type = "npc.shoot",
    id = "hero",
    tile_x = 4,
    tile_y = 2,
    kind = "bolt",
    on_hit = { type = "terrain.update", tile_x = 4, tile_y = 2, mat = "dirt" },
})

-- Sequence in one call (array without .type)
Iso.run({
    { type = "terrain.add", tile_x = 0, tile_y = 0, mat = "grass" },
    { type = "npc.add", id = "a", kind = "player", tile_x = 0, tile_y = 0 },
})

-- Pick NPC or tile under cursor (design_x/y from your letterbox transform)
local hit = Iso.query_at_design(mx, my)
if hit and hit.target == "npc" then
    Iso.run({ type = "npc.set_mode", id = hit.npc.npc_id, mode = "hurt" })
end
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
| `projectiles`                          | Live projectile instances (transient)        |
| `npc_paused`, `structure_paused`, `projectile_paused` | Pause flags set via facade pause helpers |
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

| File             | Role                                              |
| ---------------- | ------------------------------------------------- |
| `isolet2d.lua`   | Public facade                                     |
| `setup.lua`      | Config get/set                                    |
| `stack.lua`      | Stack grid parsing                                |
| `tile.lua`       | Tile ↔ screen projection, layout, viewport cull   |
| `terrain.lua`    | Terrain draw, baking, autotile                    |
| `structure.lua`  | Structure sprites, modes, footprint occupancy     |
| `npc.lua`        | NPC animation, walking, queries                   |
| `placement.lua`  | Walk-node graph build/rebuild                       |
| `path.lua`       | Pathfinding and step helpers on placement graph   |
| `projectile.lua` | Projectile spawn, motion, draw, `on_hit` dispatch |
| `events.lua`     | Event dispatch                                    |
| `camera.lua`     | Pan                                               |
| `anim8.lua`      | Vendored anim8 v2.3.1                             |

Prefer the facade API; require submodules only for advanced integration.
