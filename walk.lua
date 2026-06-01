--[[
  Grid pathfinding — uses map.grid bound by bind_grid.
]]

local Occupancy = require("occupancy")

local Walk = {}

local NEIGHBORS = {
    -- Orthogonal grid directions
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
    -- Diagonal grid directions
    { -1, 1 },
    { 1, -1 },
    { -1, -1 },
    { 1, 1 },
}
local function key(tile_x, tile_y)
    return tile_x .. "," .. tile_y
end

local function grid(map)
    if not map or not map.grid then
        error("walk: map.grid is missing (call Iso.bind_grid)")
    end
    return map.grid
end

function Walk.height(map, tile_x, tile_y)
    return grid(map).height_at(tile_x, tile_y)
end

function Walk.surface_z(map, tile_x, tile_y)
    return grid(map).surface_z(tile_x, tile_y)
end

function Walk.can_step(map, from_x, from_y, to_x, to_y)
    local g = grid(map)
    local h_from = g.height_at(from_x, from_y)
    local h_to = g.height_at(to_x, to_y)

    if h_to <= 0 or h_from <= 0 then
        return false
    end

    if not g.walkable_at(to_x, to_y) then
        return false
    end

    if Occupancy.blocks_tile(map, to_x, to_y) then
        return false
    end

    return math.abs(h_from - h_to) <= 1
end

function Walk.find_path(map, from_x, from_y, to_x, to_y)
    local g = grid(map)
    local h_from = g.height_at(from_x, from_y)
    local h_to = g.height_at(to_x, to_y)

    if h_from <= 0 or h_to <= 0 then return nil end
    if not g.walkable_at(to_x, to_y) then return nil end
    if Occupancy.blocks_tile(map, to_x, to_y) then return nil end
    if from_x == to_x and from_y == to_y then return {} end

    local visited = {}
    local came_from = {}
    local queue = { { from_x, from_y } }

    visited[key(from_x, from_y)] = true
    local head = 1

    while head <= #queue do
        local cx, cy = queue[head][1], queue[head][2]
        head = head + 1

        if cx == to_x and cy == to_y then
            local path = {}
            local tx, ty = to_x, to_y

            while came_from[key(tx, ty)] do
                path[#path + 1] = {
                    x = tx,
                    y = ty,
                    z = Walk.surface_z(map, tx, ty),
                }
                local prev = came_from[key(tx, ty)]
                tx, ty = prev[1], prev[2]
            end

            local reversed = {}
            for i = #path, 1, -1 do
                reversed[#reversed + 1] = path[i]
            end
            return reversed
        end

        for _, off in ipairs(NEIGHBORS) do
            local nx, ny = cx + off[1], cy + off[2]

            if g.in_bounds(nx, ny) then
                local nk = key(nx, ny)

                if not visited[nk] and Walk.can_step(map, cx, cy, nx, ny) then
                    
                    local can_pass = true
                    local dx, dy = off[1], off[2]

                    -- Corner-cut check: block diagonal moves when adjacent terrain blocks both sides (dx and dy both non-zero)
                    if dx ~= 0 and dy ~= 0 then
                        if g.in_bounds(cx + dx, cy) and g.in_bounds(cx, cy + dy) then
                            if not Walk.can_step(map, cx, cy, cx + dx, cy) or 
                               not Walk.can_step(map, cx, cy, cx, cy + dy) then
                                can_pass = false
                            end
                        else
                            can_pass = false
                        end
                    end

                    if can_pass then
                        visited[nk] = true
                        came_from[nk] = { cx, cy }
                        queue[#queue + 1] = { nx, ny }
                    end
                end
            end
        end
    end

    return nil
end

return Walk
