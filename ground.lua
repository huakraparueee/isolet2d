
local M = {}

function M.snap_px(n)
    return math.floor(n + 0.5)
end

function M.hw_for_tile_span(tile_px, iso_x_ratio)
    return tile_px * (iso_x_ratio or 0.5)
end

function M.hd_for_tile_span(tile_px, iso_y_ratio)
    return tile_px * (iso_y_ratio or 0.25)
end

function M.eh_for_tile_span(tile_px, iso_eh_ratio)
    return tile_px * (iso_eh_ratio or 0.5)
end

function M.hd_eh(scale, tile_size, iso_y_ratio, iso_eh_ratio)
    local ts = (tile_size or 64) * (scale or 1)
    local y_ratio = iso_y_ratio or 0.25
    local eh_ratio = iso_eh_ratio or 0.5

    return ts * y_ratio, ts * eh_ratio
end

function M.block_sprite_bottom_y(tile_cy, scale, tile_size, iso_y_ratio)
    local hd = M.hd_eh(scale, tile_size, iso_y_ratio, 0.5)

    return tile_cy + hd
end

function M.terrain_sprite_scale(screen_px, block_px)
    screen_px = screen_px or 1
    block_px = block_px or 1
    local target_w = screen_px
    local s = target_w / block_px
    local drawn_w = math.floor(block_px * s + 0.5)

    if drawn_w < target_w then
        s = (target_w + 1) / block_px
    end

    return s
end

--[[
  opts:
    design_width, design_height
    tiles_w, tiles_d
    grid_origin_x, grid_origin_y
    tile_size, iso_x_ratio, iso_y_ratio, iso_eh_ratio
    scale (optional, default 1)
]]
function M.layout(opts)
    local tile_size = opts.tile_size

    if not tile_size then
        error("iso.ground.layout: missing tile_size")
    end

    local w = opts.tiles_w
    local d = opts.tiles_d
    local scale = opts.scale or 1
    local iso_x_ratio = opts.iso_x_ratio or 0.5
    local iso_y_ratio = opts.iso_y_ratio or 0.25
    local iso_eh_ratio = opts.iso_eh_ratio or 0.5
    local iso_x = tile_size * iso_x_ratio * scale
    local iso_y = tile_size * iso_y_ratio * scale

    return {
        cx = M.snap_px(opts.design_width * 0.5),
        cy = M.snap_px(opts.design_height * 0.5),
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

function M.tile_screen_bounds(layout, tile_x, tile_y, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local tile_px = layout.tile_size * s
    local cx, cy = M.tile_to_screen(layout, tile_x, tile_y, tile_z)
    local hw = M.hw_for_tile_span(tile_px, layout.iso_x_ratio)
    local hd = M.hd_for_tile_span(tile_px, layout.iso_y_ratio)
    local eh = M.eh_for_tile_span(tile_px, layout.iso_eh_ratio)

    return cx - hw, cy - eh - hd, cx + hw, cy + hd
end

function M.tile_to_screen(layout, tile_x, tile_y, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local gx = layout.grid_x
    local gy = layout.grid_y
    local rx = tile_x - gx
    local ry = tile_y - gy
    local eh = M.eh_for_tile_span(layout.tile_size * s, layout.iso_eh_ratio)

    return layout.cx + (rx - ry) * layout.iso_x,
        layout.cy + (rx + ry) * layout.iso_y - tile_z * eh
end

function M.screen_to_tile(layout, sx, sy, tile_z)
    tile_z = tile_z or 0
    local s = layout.scale or 1
    local eh = M.eh_for_tile_span(layout.tile_size * s, layout.iso_eh_ratio)
    local dx = sx - layout.cx
    local dy = sy - layout.cy + tile_z * eh
    local iso_x = layout.iso_x
    local iso_y = layout.iso_y
    local rx = (dx / iso_x + dy / iso_y) * 0.5
    local ry = (dy / iso_y - dx / iso_x) * 0.5

    return layout.grid_x + rx, layout.grid_y + ry
end

--[[
  world-space viewport (before camera translate) → tile AABB + margin
  opts: pad, max_z (sample corners at multiple heights to avoid clipping tall sprites)
]]
function M.visible_tile_rect(layout, view_x, view_y, view_w, view_h, opts)
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
            local tx, ty = M.screen_to_tile(layout, corner[1], corner[2], z)
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

return M
