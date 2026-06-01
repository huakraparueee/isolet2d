--[[
  Screen footprint anchor — layout from IsoGround.layout (built by scene/render)
]]

local M = {}

function M.origin(piece, tiles_w, tiles_d)
    tiles_w = tiles_w or piece.tiles_w or 1
    tiles_d = tiles_d or piece.tiles_d or 1

    if piece.pos_x ~= nil and piece.pos_y ~= nil then
        return piece.pos_x - tiles_w * 0.5, piece.pos_y - tiles_d * 0.5
    end

    if piece.tile_x ~= nil and piece.tile_y ~= nil then
        return piece.tile_x, piece.tile_y
    end

    return 0, 0
end

local function tile_to_screen(layout, tile_x, tile_y, tile_z)
    tile_z = tile_z or 0
    local gx = layout.grid_x
    local gy = layout.grid_y
    local rx = tile_x - gx
    local ry = tile_y - gy
    local eh = layout.tile_size * layout.scale * layout.iso_eh_ratio

    return layout.cx + (rx - ry) * layout.iso_x,
        layout.cy + (rx + ry) * layout.iso_y - tile_z * eh
end

function M.feet_screen(layout, opts)
    local ox = opts.ox
    local oy = opts.oy
    local w = opts.tiles_w or 1
    local d = opts.tiles_d or 1
    local z_at = opts.z_at
    local fallback_z = opts.tile_z or 0
    local scale = layout.scale or 1
    local ts = layout.tile_size * scale
    local hw = ts * layout.iso_x_ratio
    local hd = ts * layout.iso_y_ratio
    local eh = ts * layout.iso_eh_ratio
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

            local cx, cy = tile_to_screen(layout, tx, ty, tz)
            local yt = cy - eh

            min_left = math.min(min_left, cx - hw)
            max_right = math.max(max_right, cx + hw)
            max_bottom = math.max(max_bottom, yt + hd)
        end
    end

    return (min_left + max_right) * 0.5, max_bottom
end

function M.feet_screen_from_piece(layout, piece, tiles_w, tiles_d, z_at)
    tiles_w = tiles_w or piece.tiles_w or 1
    tiles_d = tiles_d or piece.tiles_d or 1

    local ox, oy = M.origin(piece, tiles_w, tiles_d)

    return M.feet_screen(layout, {
        ox = ox,
        oy = oy,
        tiles_w = tiles_w,
        tiles_d = tiles_d,
        tile_z = piece.tile_z,
        z_at = z_at,
    })
end

return M
