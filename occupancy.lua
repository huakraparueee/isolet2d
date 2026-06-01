--[[
  Grid occupancy — tile coverage / blocking movement
  Uses map.grid.structure_span bound by bind_grid
]]

local Structure = require("structure")

local Occupancy = {}

local function span_fn(map)
    return map.grid.structure_span
end

function Occupancy.covers_tile(map, piece, tile_x, tile_y)
    if not Structure.is_piece(piece) then
        return false
    end

    local w, d = span_fn(map)(piece.structure)
    local lx = tile_x - piece.tile_x
    local ly = tile_y - piece.tile_y

    return lx >= 0 and lx < w and ly >= 0 and ly < d
end

function Occupancy.blocks_tile(map, tile_x, tile_y)
    if not map then
        return false
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if not piece._removed
            and Occupancy.covers_tile(map, piece, tile_x, tile_y)
        then
            return true
        end
    end

    return false
end

function Occupancy.find_by_id(map, structure_id)
    if not map or not structure_id then
        return nil
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if piece.structure_id == structure_id then
            return piece
        end
    end
end

function Occupancy.find_at(map, tile_x, tile_y)
    if not map then
        return nil
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if not piece._removed
            and Occupancy.covers_tile(map, piece, tile_x, tile_y)
        then
            return piece
        end
    end
end

function Occupancy.footprint_cells(map, tile_x, tile_y, kind)
    local w, d = span_fn(map)(kind)
    local cells = {}

    for ly = 0, d - 1 do
        for lx = 0, w - 1 do
            cells[#cells + 1] = {
                tile_x = tile_x + lx,
                tile_y = tile_y + ly,
            }
        end
    end

    return cells
end

return Occupancy
