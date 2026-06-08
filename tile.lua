--[[
  Tile grid ↔ screen (pipeline step 1).
  Terrain and Structure anchor to integer tile_x, tile_y; this module owns screen projection.
]]

local Ground = require("ground")

local Tile = {}

function Tile.layout(opts)
    return Ground.layout(opts)
end

function Tile.to_screen(layout, tile_x, tile_y, tile_z)
    return Ground.tile_to_screen(layout, tile_x, tile_y, tile_z)
end

function Tile.from_screen(layout, sx, sy, tile_z)
    return Ground.screen_to_tile(layout, sx, sy, tile_z)
end

function Tile.bounds(layout, tile_x, tile_y, tile_z)
    return Ground.tile_screen_bounds(layout, tile_x, tile_y, tile_z)
end

function Tile.visible_rect(layout, view_x, view_y, view_w, view_h, opts)
    return Ground.visible_tile_rect(
        layout,
        view_x,
        view_y,
        view_w,
        view_h,
        opts
    )
end

--[[
  Placement world position (px, py in tile units, sub-tile) → screen feet point.
]]
function Tile.placement_to_screen(layout, px, py, z)
    local cell_tx = math.floor(px)
    local cell_ty = math.floor(py)
    local ts = layout.tile_size * (layout.scale or 1)
    local eh = Ground.eh_for_tile_span(ts, layout.iso_eh_ratio)
    local cx, cy = Ground.tile_to_screen(layout, cell_tx, cell_ty, z or 0)
    local drx = px - cell_tx - 0.5
    local dry = py - cell_ty - 0.5

    return cx + (drx - dry) * layout.iso_x,
        cy - eh + (drx + dry) * layout.iso_y
end

return Tile
