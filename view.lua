local M = {}

M.scale = 1
M.offset_x = 0
M.offset_y = 0
M.window_w = 1600
M.window_h = 900
M.design_w = 1600
M.design_h = 900

local canvas

local function ensure_canvas()
    if canvas
        and canvas:getWidth() == M.design_w
        and canvas:getHeight() == M.design_h
    then
        return
    end

    canvas = love.graphics.newCanvas(M.design_w, M.design_h)
    canvas:setFilter("nearest", "nearest")
end

function M.resize(window_w, window_h, design_w, design_h)
    design_w = design_w or M.design_w
    design_h = design_h or M.design_h

    M.design_w = design_w
    M.design_h = design_h
    M.window_w = window_w
    M.window_h = window_h

    local sx = window_w / design_w
    
    local sy = window_h / design_h

    M.scale = math.max(math.max(sx, sy), 0.25)

    local draw_w = design_w * M.scale
    local draw_h = design_h * M.scale

    M.offset_x = math.floor((window_w - draw_w) * 0.5)
    M.offset_y = math.floor((window_h - draw_h) * 0.5)
end

function M.begin()
    ensure_canvas()

    love.graphics.push()
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.clear()
end

function M.finish()
    love.graphics.setCanvas()
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        canvas,
        M.offset_x,
        M.offset_y,
        0,
        M.scale,
        M.scale
    )
end

function M.screen_to_design(sx, sy)
    local x = (sx - M.offset_x) / M.scale
    local y = (sy - M.offset_y) / M.scale
    return x, y
end

return M
