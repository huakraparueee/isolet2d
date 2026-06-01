--[[
  Queries on map.pieces — no stored state
]]

local Pieces = {}

function Pieces.is_terrain_block(piece)
    return piece.mat ~= nil or piece.color ~= nil
end

function Pieces.top_terrain_z(map, tile_x, tile_y)
    local max_z = -1

    for _, piece in ipairs(map.pieces or {}) do
        if Pieces.is_terrain_block(piece)
            and piece.tile_x == tile_x
            and piece.tile_y == tile_y
        then
            max_z = math.max(max_z, piece.tile_z or 0)
        end
    end

    return max_z
end

function Pieces.find_at(map, tile_x, tile_y, tile_z)
    local z = tile_z or 0

    for _, piece in ipairs(map.pieces or {}) do
        if piece.tile_x == tile_x
            and piece.tile_y == tile_y
            and (piece.tile_z or 0) == z
        then
            return piece
        end
    end
end

function Pieces.find_terrain_at(map, tile_x, tile_y, tile_z)
    if tile_z ~= nil then
        for _, piece in ipairs(map.pieces or {}) do
            if Pieces.is_terrain_block(piece)
                and piece.tile_x == tile_x
                and piece.tile_y == tile_y
                and (piece.tile_z or 0) == tile_z
            then
                return piece
            end
        end

        return nil
    end

    local best_z = -1
    local best = nil

    for _, piece in ipairs(map.pieces or {}) do
        if Pieces.is_terrain_block(piece)
            and piece.tile_x == tile_x
            and piece.tile_y == tile_y
        then
            local z = piece.tile_z or 0

            if z > best_z then
                best_z = z
                best = piece
            end
        end
    end

    return best
end

return Pieces
