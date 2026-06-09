# isolet2d

A **LÖVE 11.x** library for stacked isometric maps — terrain cubes, structures, animated NPCs, and projectiles with depth sorting, viewport culling, sub-tile placement walking, and an event-driven mutation API.

<img width="1207" height="679" alt="example" src="https://github.com/user-attachments/assets/c4e666bd-4980-4dbd-9ee9-3541e648234e" />

## Requirements

- [LÖVE](https://love2d.org/) 11.x
- Lua 5.1 (bundled with LÖVE)

## Quick start

```lua
package.path = package.path .. ";lib/isolet2d/?.lua"
local Iso = require("isolet2d")

function love.load()
    Iso.init(iso_cfg)
    Iso.load_map(map_src)
end

function love.update(dt)
    Iso.tick(dt)
end

function love.draw()
    -- Your viewport / letterbox into design resolution, then:
    Iso.draw_map()
end
```

Use `Iso.is_blocked()` before player input while terrain jobs, NPC movement, or projectiles are active. For direct player movement on the placement graph, use `Iso.can_step_pos()`, `Iso.try_step_neighbor()`, and `Iso.pick_placement_near()`.

**Full API reference:** [docs/api.md](docs/api.md)

## Features

- **Terrain** — solid-color cubes, sprite sheets, animated materials, and neighbor-based autotile variants
- **Structures** — multi-tile footprints with optional animated modes
- **NPCs** — anim8 sprite sheets with left/right or 8-direction walk clips (`e`, `se`, `s`, …)
- **Placement graph** — sub-tile walk nodes rebuilt from walkable terrain minus structure occupancy
- **Events** — add/update/remove terrain, spawn structures and NPCs, set modes, walk-to tile or world position, shoot projectiles with optional `on_hit` callbacks
- **Projectiles** — arc or line motion in placement space, sprite or procedural draw, fired via `projectile.spawn` or `npc.shoot`
- **Camera** — design-space pan with bounds set from map geometry

## Install

1. Copy all `.lua` files from this repo into your game (e.g. `lib/isolet2d/`).
2. Add that folder to `package.path` (see quick start).

## Repository layout

```text
isolet2d/
├── isolet2d.lua      # Entry module (require "isolet2d")
├── setup.lua         # Config build/get/set
├── stack.lua         # Stack grid parsing
├── tile.lua          # Tile ↔ screen projection, layout, culling
├── terrain.lua       # Terrain draw, baking, autotile
├── structure.lua     # Structure sprites and modes
├── npc.lua           # NPC animation and walking
├── placement.lua     # Walk-node graph
├── path.lua          # Pathfinding and step helpers on placement graph
├── projectile.lua    # Projectile spawn, motion, draw
├── events.lua        # Event dispatch
├── camera.lua        # Pan
├── anim8.lua         # Vendored anim8 v2.3.1
├── docs/
│   └── api.md        # API reference
└── LICENSE
```

## Documentation

| Doc                        | Contents                                                            |
| -------------------------- | ------------------------------------------------------------------- |
| [docs/api.md](docs/api.md) | Config, map source, events, projectiles, placement, movement, camera, map object |

## Third-party

- **[anim8](https://github.com/kikito/anim8)** v2.3.1 — `anim8.lua` (MIT)

## License

MIT © 2026 [HkpsS](https://github.com/huakraparueee). See [LICENSE](LICENSE).
