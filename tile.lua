--[[
  Tile grid ↔ screen (pipeline step 1).
  Terrain and Structure anchor to integer tile_x, tile_y; this module owns screen projection.
]]

local Setup = require("setup")

local Tile = {}

function Tile.snap_px(n)
    return math.floor(n + 0.5)
end

function Tile.hw_for_tile_span(tile_px, iso_x_ratio)
    return tile_px * (iso_x_ratio or 0.5)
end

function Tile.hd_for_tile_span(tile_px, iso_y_ratio)
    return tile_px * (iso_y_ratio or 0.25)
end

function Tile.eh_for_tile_span(tile_px, iso_eh_ratio)
    return tile_px * (iso_eh_ratio or 0.5)
end

--[[
  opts:
    design_width, design_height
    tiles_w, tiles_d
    grid_origin_x, grid_origin_y
    tile_size, iso_x_ratio, iso_y_ratio, iso_eh_ratio
    map_offset_y (optional, default 0) — shift map anchor down on screen
    scale (optional, default 1)
]]
function Tile.layout(opts)
    local tile_size = opts.tile_size

    if not tile_size then
        error("tile.layout: missing tile_size")
    end

    local w = opts.tiles_w
    local d = opts.tiles_d
    local scale = opts.scale or 1
    local iso_x_ratio = opts.iso_x_ratio or 0.5
    local iso_y_ratio = opts.iso_y_ratio or 0.25
    local iso_eh_ratio = opts.iso_eh_ratio or 0.5
    local iso_x = tile_size * iso_x_ratio * scale
    local iso_y = tile_size * iso_y_ratio * scale
    local map_offset_y = opts.map_offset_y or 0

    return {
        cx = Tile.snap_px(opts.design_width * 0.5),
        cy = Tile.snap_px(opts.design_height * 0.5 + map_offset_y),
        map_offset_y = map_offset_y,
        grid_x = opts.grid_origin_x + (w - 1) * 0.5,
        grid_y = opts.grid_origin_y + (d - 1) * 0.5,
        tiles_w = w,
        tiles_d = d,
        scale = scale,
        tile_size = tile_size,
        iso_x_ratio = iso_x_ratio,
        iso_y_ratio = iso_y_ratio,
        iso_eh_ratio = iso_eh_ratio,
        iso_x = iso_x,
        iso_y = iso_y,
    }
end

function Tile.to_screen(layout, tile_x, tile_y, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local gx = layout.grid_x
    local gy = layout.grid_y
    local rx = tile_x - gx
    local ry = tile_y - gy
    local eh = Tile.eh_for_tile_span(layout.tile_size * s, layout.iso_eh_ratio)

    return layout.cx + (rx - ry) * layout.iso_x,
        layout.cy + (rx + ry) * layout.iso_y - tile_z * eh
end

function Tile.from_screen(layout, sx, sy, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local eh = Tile.eh_for_tile_span(layout.tile_size * s, layout.iso_eh_ratio)
    local dx = sx - layout.cx
    local dy = sy - layout.cy + tile_z * eh
    local iso_x = layout.iso_x
    local iso_y = layout.iso_y
    local rx = (dx / iso_x + dy / iso_y) * 0.5
    local ry = (dy / iso_y - dx / iso_x) * 0.5

    return layout.grid_x + rx, layout.grid_y + ry
end

function Tile.bounds(layout, tile_x, tile_y, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local tile_px = layout.tile_size * s
    local cx, cy = Tile.to_screen(layout, tile_x, tile_y, tile_z)
    local hw = Tile.hw_for_tile_span(tile_px, layout.iso_x_ratio)
    local hd = Tile.hd_for_tile_span(tile_px, layout.iso_y_ratio)
    local eh = Tile.eh_for_tile_span(tile_px, layout.iso_eh_ratio)

    return cx - hw, cy - eh - hd, cx + hw, cy + hd
end

--[[
  world-space viewport (before camera translate) → tile AABB + margin
  opts: pad, max_z (sample corners at multiple heights to avoid clipping tall sprites)
]]
function Tile.visible_rect(layout, view_x, view_y, view_w, view_h, opts)
    opts = opts or {}
    local pad = opts.pad or 0
    local max_z = opts.max_z or 0
    local min_tx, min_ty = math.huge, math.huge
    local max_tx, max_ty = -math.huge, -math.huge
    local corners = {
        { view_x, view_y },
        { view_x + view_w, view_y },
        { view_x, view_y + view_h },
        { view_x + view_w, view_y + view_h },
    }

    for z = 0, max_z do
        for _, corner in ipairs(corners) do
            local tx, ty = Tile.from_screen(layout, corner[1], corner[2], z)
            min_tx = math.min(min_tx, tx)
            min_ty = math.min(min_ty, ty)
            max_tx = math.max(max_tx, tx)
            max_ty = math.max(max_ty, ty)
        end
    end

    return math.floor(min_tx) - pad,
        math.floor(min_ty) - pad,
        math.ceil(max_tx) + pad,
        math.ceil(max_ty) + pad
end

--[[
  Placement world position (px, py in tile units, sub-tile) → screen feet point.
]]
function Tile.placement_to_screen(layout, px, py, z)
    local cell_tx = math.floor(px)
    local cell_ty = math.floor(py)
    local ts = layout.tile_size * (layout.scale or 1)
    local eh = Tile.eh_for_tile_span(ts, layout.iso_eh_ratio)
    local cx, cy = Tile.to_screen(layout, cell_tx, cell_ty, z or 0)
    local drx = px - cell_tx - 0.5
    local dry = py - cell_ty - 0.5

    return cx + (drx - dry) * layout.iso_x,
        cy - eh + (drx + dry) * layout.iso_y
end

function Tile.origin(piece, tiles_w, tiles_d)
    tiles_w = tiles_w or piece.tiles_w or 1
    tiles_d = tiles_d or piece.tiles_d or 1

    if piece.pos_x ~= nil and piece.pos_y ~= nil then
        return piece.pos_x - tiles_w * 0.5, piece.pos_y - tiles_d * 0.5
    end

    return 0, 0
end

function Tile.feet_screen(layout, opts)
    local ox = opts.ox
    local oy = opts.oy
    local w = opts.tiles_w or 1
    local d = opts.tiles_d or 1
    local z_at = opts.z_at
    local fallback_z = opts.tile_z or 0
    local scale = layout.scale or 1
    local ts = layout.tile_size * scale
    local hw = Tile.hw_for_tile_span(ts, layout.iso_x_ratio)
    local hd = Tile.hd_for_tile_span(ts, layout.iso_y_ratio)
    local eh = Tile.eh_for_tile_span(ts, layout.iso_eh_ratio)
    local min_left = math.huge
    local max_right = -math.huge
    local max_bottom = -math.huge

    for ly = 0, d - 1 do
        for lx = 0, w - 1 do
            local tx = ox + lx
            local ty = oy + ly
            local tz = fallback_z

            if z_at then
                local z = z_at(tx, ty)

                if z ~= nil then
                    tz = z
                end
            end

            local cx, cy = Tile.to_screen(layout, tx, ty, tz)
            local yt = cy - eh

            min_left = math.min(min_left, cx - hw)
            max_right = math.max(max_right, cx + hw)
            max_bottom = math.max(max_bottom, yt + hd)
        end
    end

    return (min_left + max_right) * 0.5, max_bottom
end

function Tile.feet_screen_from_piece(layout, piece, tiles_w, tiles_d, z_at)
    tiles_w = tiles_w or piece.tiles_w or 1
    tiles_d = tiles_d or piece.tiles_d or 1

    local ox, oy = Tile.origin(piece, tiles_w, tiles_d)

    return Tile.feet_screen(layout, {
        ox = ox,
        oy = oy,
        tiles_w = tiles_w,
        tiles_d = tiles_d,
        tile_z = piece.tile_z,
        z_at = z_at,
    })
end

function Tile.grid_index(source, tile_x, tile_y)
    local c = Setup.get()
    local lx = tile_x - c.grid_origin_x
    local ly = tile_y - c.grid_origin_y

    if lx < 0 or lx >= source.tiles_w or ly < 0 or ly >= source.tiles_d then
        return nil, nil
    end

    return lx, ly
end

function Tile.build_render_cache(map, cache_rect)
    local source = map.source
    local tops = {}
    local height_cache = map.height_at_cache

    if not height_cache then
        return { tops = tops }
    end

    local min_tx, min_ty, max_tx, max_ty

    if cache_rect then
        min_tx = cache_rect.min_tx
        min_ty = cache_rect.min_ty
        max_tx = cache_rect.max_tx
        max_ty = cache_rect.max_ty
    else
        min_tx = 0
        min_ty = 0
        max_tx = source.tiles_w - 1
        max_ty = source.tiles_d - 1
    end

    for ty = min_ty, max_ty do
        local cache_row = height_cache[ty]

        if cache_row then
            local row

            for tx = min_tx, max_tx do
                local h = cache_row[tx]

                if h and h > 0 then
                    local lx, ly = Tile.grid_index(source, tx, ty)

                    if lx then
                        if not row then
                            row = {}
                            tops[ly] = row
                        end

                        row[lx] = h - 1
                    end
                end
            end
        end
    end

    return { tops = tops }
end

function Tile.top_z_from_cache(source, cache, tile_x, tile_y)
    local lx, ly = Tile.grid_index(source, math.floor(tile_x), math.floor(tile_y))

    if not lx then
        return 0
    end

    local z = cache.tops[ly]

    if not z then
        return 0
    end

    z = z[lx]

    if not z or z < 0 then
        return 0
    end

    return z
end

return Tile
