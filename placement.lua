--[[
  Placement graph (pipeline step 4) — Terrain walkability + Structure occupancy → nodes.
  Each node: grid ix/iy, world px/py, tile_x/tile_y, z, screen sx/sy.
]]

local Setup = require("setup")
local Tile = require("tile")
local Structure = require("structure")

local Placement = {}

local GRID_POINT_PER_TILE = 2
local POS_STEP = 1 / GRID_POINT_PER_TILE

function Placement.set_grid_point_per_tile(n)
    if type(n) ~= "number" or n < 1 or n ~= math.floor(n) then
        error("placement: grid_point_per_tile must be a positive integer")
    end

    GRID_POINT_PER_TILE = n
    POS_STEP = 1 / GRID_POINT_PER_TILE
end

function Placement.grid_point_per_tile()
    return GRID_POINT_PER_TILE
end

function Placement.pos_step()
    return POS_STEP
end

local function placement_pos(ix, iy)
    return (ix + 0.5) * POS_STEP, (iy + 0.5) * POS_STEP
end

local function key(ix, iy)
    return ix .. "," .. iy
end

function Placement.cell_ix(px, py)
    local gpp = Placement.grid_point_per_tile()

    return math.floor(px * gpp + 0.0001),
        math.floor(py * gpp + 0.0001)
end

local function node_world_pos(ix, iy)
    return placement_pos(ix, iy)
end

local function tile_allows_node(map, tile_x, tile_y)
    local g = map.grid

    if not g then
        return false
    end

    if not g.in_bounds(tile_x, tile_y) then
        return false
    end

    if g.height_at(tile_x, tile_y) <= 0 then
        return false
    end

    if not g.walkable_at(tile_x, tile_y) then
        return false
    end

    if Structure.blocks_tile(map, tile_x, tile_y) then
        return false
    end

    return true
end

local function remove_tile_nodes(placement, tile_x, tile_y)
    local gpp = Placement.grid_point_per_tile()
    local ix0 = tile_x * gpp
    local iy0 = tile_y * gpp
    local removed = {}

    for iy = iy0, iy0 + gpp - 1 do
        for ix = ix0, ix0 + gpp - 1 do
            local k = key(ix, iy)

            if placement.by_cell[k] then
                placement.by_cell[k] = nil
                removed[k] = true
            end
        end
    end

    if not next(removed) then
        return
    end

    local kept = {}

    for _, node in ipairs(placement.nodes) do
        if not removed[key(node.ix, node.iy)] then
            kept[#kept + 1] = node
        end
    end

    placement.nodes = kept
end

local function add_tile_nodes(map, placement, tile_x, tile_y)
    local gpp = Placement.grid_point_per_tile()
    local step = Placement.pos_step()
    local ix0 = tile_x * gpp
    local iy0 = tile_y * gpp
    local layout = map.layout

    for iy = iy0, iy0 + gpp - 1 do
        for ix = ix0, ix0 + gpp - 1 do
            local cell_tx = math.floor(ix * step)
            local cell_ty = math.floor(iy * step)

            if tile_allows_node(map, cell_tx, cell_ty) then
                local k = key(ix, iy)

                if not placement.by_cell[k] then
                    local px, py = node_world_pos(ix, iy)
                    local z = map.grid.surface_z(cell_tx, cell_ty)
                    local sx, sy = Tile.placement_to_screen(layout, px, py, z)
                    local node = {
                        ix = ix,
                        iy = iy,
                        px = px,
                        py = py,
                        z = z,
                        tile_x = cell_tx,
                        tile_y = cell_ty,
                        sx = sx,
                        sy = sy,
                    }

                    placement.by_cell[k] = node
                    placement.nodes[#placement.nodes + 1] = node
                end
            end
        end
    end
end

function Placement.rebuild(map)
    if not map or not map.grid or not map.source or not map.layout then
        return
    end

    map.placement = {
        nodes = {},
        by_cell = {},
    }

    local src = map.source
    local c = Setup.get()
    local ox = c.grid_origin_x
    local oy = c.grid_origin_y

    for ty = oy, oy + src.tiles_d - 1 do
        for tx = ox, ox + src.tiles_w - 1 do
            add_tile_nodes(map, map.placement, tx, ty)
        end
    end
end

function Placement.rebuild_tile(map, tile_x, tile_y)
    if not map or not map.grid then
        return
    end

    if not map.placement then
        Placement.rebuild(map)
        return
    end

    remove_tile_nodes(map.placement, tile_x, tile_y)
    add_tile_nodes(map, map.placement, tile_x, tile_y)
end

function Placement.has_cell(map, ix, iy)
    local placement = map and map.placement

    if not placement then
        return false
    end

    return placement.by_cell[key(ix, iy)] ~= nil
end

function Placement.cell_node(map, ix, iy)
    local placement = map and map.placement

    if not placement then
        return nil
    end

    return placement.by_cell[key(ix, iy)]
end

function Placement.node_at_pos(map, px, py)
    local ix, iy = Placement.cell_ix(px, py)

    return Placement.cell_node(map, ix, iy)
end

function Placement.node_for_footprint(map, tile_x, tile_y, w, d)
    local placement = map and map.placement

    if not placement then
        return nil
    end

    w = w or 1
    d = d or 1

    local gpp = Placement.grid_point_per_tile()
    local best
    local best_dist = math.huge
    local cx = tile_x + w * 0.5
    local cy = tile_y + d * 0.5

    for ty = tile_y, tile_y + d - 1 do
        for tx = tile_x, tile_x + w - 1 do
            local ix0 = tx * gpp
            local iy0 = ty * gpp

            for iy = iy0, iy0 + gpp - 1 do
                for ix = ix0, ix0 + gpp - 1 do
                    local node = placement.by_cell[key(ix, iy)]

                    if node then
                        local dx = node.px - cx
                        local dy = node.py - cy
                        local dist = dx * dx + dy * dy

                        if dist < best_dist then
                            best_dist = dist
                            best = node
                        end
                    end
                end
            end
        end
    end

    return best
end

function Placement.apply_node(piece, node)
    piece.pos_x = node.px
    piece.pos_y = node.py
    piece.tile_z = node.z
end

function Placement.spawn_at(map, piece, spawn_tx, spawn_ty)
    local w = piece.tiles_w or 1
    local d = piece.tiles_d or 1
    local node = Placement.node_for_footprint(map, spawn_tx, spawn_ty, w, d)

    if not node then
        return false
    end

    Placement.apply_node(piece, node)

    return true
end

function Placement.on_walkable_cell(map, piece)
    if piece.pos_x == nil or piece.pos_y == nil then
        return false
    end

    local ix, iy = Placement.cell_ix(piece.pos_x, piece.pos_y)

    return Placement.has_cell(map, ix, iy)
end

function Placement.neighbor(map, px, py, cell_dx, cell_dy)
    local from_ix, from_iy = Placement.cell_ix(px, py)

    return Placement.cell_node(map, from_ix + cell_dx, from_iy + cell_dy)
end

return Placement
