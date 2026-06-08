# isolet2d

A **LÖVE 11.x** library for stacked isometric maps — terrain cubes, structures, and animated NPCs with depth sorting, viewport culling, and an event-driven mutation API.

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

Use `Iso.is_blocked()` before player input while terrain or NPC actions are running.

**Full API reference:** [docs/api.md](docs/api.md)

## Install

1. Copy all `.lua` files from this repo into your game (e.g. `lib/isolet2d/`).
2. Add that folder to `package.path` (see quick start).

## Repository layout

```text
isolet2d/
├── isolet2d.lua      # Entry module (require "isolet2d")
├── setup.lua …       # Internal modules (flat require names)
├── docs/
│   └── api.md        # API reference
└── LICENSE
```

## Documentation

| Doc                        | Contents                                       |
| -------------------------- | ---------------------------------------------- |
| [docs/api.md](docs/api.md) | Config, map source, events, camera, map object |

## Third-party

- **[anim8](https://github.com/kikito/anim8)** v2.3.1 — `anim8.lua` (MIT)

## License

MIT © 2026 [HkpsS](https://github.com/huakraparueee). See [LICENSE](LICENSE).
