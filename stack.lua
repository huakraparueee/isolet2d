--[[
  Stack grid from src.stacks + src.stack_chars
]]

local M = {}

function M.dims(src)
    if src.tiles_w and src.tiles_d then
        return src.tiles_w, src.tiles_d
    end

    local grid = src.stacks

    if not grid or #grid == 0 then
        error("iso stack: missing stacks")
    end

    local tiles_d = #grid
    local tiles_w = 0

    for _, row in ipairs(grid) do
        tiles_w = math.max(tiles_w, #row)
    end

    if tiles_w == 0 then
        error("iso stack: stacks has no columns")
    end

    src.tiles_w = tiles_w
    src.tiles_d = tiles_d

    return tiles_w, tiles_d
end

function M.at(src, row, col)
    local cells = src.stacks[row]

    if not cells then
        return "."
    end

    return cells[col] or "."
end

function M.height(src, row, col)
    local cell = M.at(src, row, col)

    if cell == "." or cell == "" then
        return 0
    end

    return #cell
end

function M.mat(src, ch, terrain_mats)
    if not ch or ch == "" or ch == "." then
        return nil
    end

    local mat = src.stack_chars[ch]

    if mat then
        return mat
    end

    if terrain_mats and terrain_mats[ch] then 
        return ch
    end

    error("iso stack: unknown char " .. tostring(ch))
end

function M.layer_mat(src, row, col, z, terrain_mats)
    local cell = M.at(src, row, col)
    local ch = cell:sub(z + 1, z + 1)

    return M.mat(src, ch, terrain_mats)
end

return M
