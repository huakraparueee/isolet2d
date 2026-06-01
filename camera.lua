--[[
  Pan in design space (pairs with game viewport / design resolution)
]]

local M = {
    pan_x = 0,
    pan_y = 0,
    bounds_min_x = nil,
    bounds_min_y = nil,
    bounds_max_x = nil,
    bounds_max_y = nil,
    view_w = nil,
    view_h = nil,
}

local function clamp_axis(value, min_v, max_v)
    if min_v > max_v then
        return (min_v + max_v) * 0.5
    end

    return math.max(min_v, math.min(max_v, value))
end

function M.clamp()
    if not M.bounds_min_x then
        return
    end

    local min_pan_x = M.view_w - M.bounds_max_x
    local max_pan_x = -M.bounds_min_x
    local min_pan_y = M.view_h - M.bounds_max_y
    local max_pan_y = -M.bounds_min_y

    M.pan_x = clamp_axis(M.pan_x, min_pan_x, max_pan_x)
    M.pan_y = clamp_axis(M.pan_y, min_pan_y, max_pan_y)
end

function M.set_bounds(opts)
    M.bounds_min_x = opts.min_x
    M.bounds_min_y = opts.min_y
    M.bounds_max_x = opts.max_x
    M.bounds_max_y = opts.max_y
    M.view_w = opts.view_w
    M.view_h = opts.view_h
    M.clamp()
end

function M.clear_bounds()
    M.bounds_min_x = nil
    M.bounds_min_y = nil
    M.bounds_max_x = nil
    M.bounds_max_y = nil
    M.view_w = nil
    M.view_h = nil
end

function M.reset()
    M.pan_x = 0
    M.pan_y = 0
    M.clamp()
end

function M.apply()
    love.graphics.translate(M.pan_x, M.pan_y)
end

function M.pan(dx, dy)
    M.pan_x = M.pan_x + dx
    M.pan_y = M.pan_y + dy
    M.clamp()
end

return M
