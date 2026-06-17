--[[
  Pathfinding on map.placement graph. Terrain rules live in placement rebuild; edges use node tile coords.
]]

local Placement = require("placement")

local Path = {}

local NEIGHBORS = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
    { -1, 1 },
    { 1, -1 },
    { -1, -1 },
    { 1, 1 },
}

local MAX_BFS_EXPAND = 200
local MAX_GREEDY_STEPS = 48

local pool = {
    visited = {},
    came_from = {},
    queue = {},
    visit_keys = {},
    visit_n = 0,
}

local function grid(map)
    if not map or not map.grid then
        error("path: map.grid is missing (call Iso.bind_grid)")
    end

    return map.grid
end

local function cell_key(ix, iy)
    return ix * 4096 + iy
end

local function pool_reset()
    local keys = pool.visit_keys
    local n = pool.visit_n

    for i = 1, n do
        local k = keys[i]
        pool.visited[k] = nil
        pool.came_from[k] = nil
    end

    pool.visit_n = 0
end

local function pool_mark(ix, iy)
    local k = cell_key(ix, iy)
    local n = pool.visit_n + 1

    pool.visit_n = n
    pool.visit_keys[n] = k

    return k
end

function Path.surface_z(map, tile_x, tile_y)
    return grid(map).surface_z(tile_x, tile_y)
end

function Path.surface_z_at_pos(map, px, py, tiles_w, tiles_d)
    tiles_w = tiles_w or 1
    tiles_d = tiles_d or 1
    local tx = math.floor(px - tiles_w * 0.5 + 0.0001)
    local ty = math.floor(py - tiles_d * 0.5 + 0.0001)

    return Path.surface_z(map, tx, ty)
end

function Path.can_step(map, from_x, from_y, to_x, to_y)
    local g = grid(map)
    local h_from = g.height_at(from_x, from_y)
    local h_to = g.height_at(to_x, to_y)

    if h_to <= 0 or h_from <= 0 then
        return false
    end

    if not g.walkable_at(to_x, to_y) then
        return false
    end

    return math.abs(h_from - h_to) <= 1
end

local function node_pair(map, from_ix, from_iy, to_ix, to_iy)
    if from_ix == to_ix and from_iy == to_iy then
        return nil, nil
    end

    if not Placement.has_cell(map, from_ix, from_iy)
        or not Placement.has_cell(map, to_ix, to_iy)
    then
        return nil, nil
    end

    return Placement.cell_node(map, from_ix, from_iy),
        Placement.cell_node(map, to_ix, to_iy)
end

function Path.can_edge(map, from_ix, from_iy, to_ix, to_iy, allow_corner_cut)
    local from_node, to_node = node_pair(map, from_ix, from_iy, to_ix, to_iy)

    if not from_node or not to_node then
        return false
    end

    if not Path.can_step(
        map,
        from_node.tile_x,
        from_node.tile_y,
        to_node.tile_x,
        to_node.tile_y
    ) then
        return false
    end

    if allow_corner_cut == false then
        local dx = to_ix - from_ix
        local dy = to_iy - from_iy

        if dx ~= 0 and dy ~= 0 then
            if not Path.can_edge(map, from_ix, from_iy, from_ix + dx, from_iy, true)
                or not Path.can_edge(map, from_ix, from_iy, from_ix, from_iy + dy, true)
            then
                return false
            end
        end
    end

    return true
end

local function cell_in_bounds(map, ix, iy)
    local g = grid(map)
    local step = Placement.pos_step()
    local tx, ty = math.floor(ix * step), math.floor(iy * step)

    return g.in_bounds(tx, ty)
end

function Path.can_step_pos(map, from_px, from_py, to_px, to_py)
    if from_px == to_px and from_py == to_py then
        return false
    end

    local from_ix, from_iy = Placement.cell_ix(from_px, from_py)
    local to_ix, to_iy = Placement.cell_ix(to_px, to_py)

    return Path.can_edge(map, from_ix, from_iy, to_ix, to_iy, false)
end

function Path.try_step_neighbor(map, from_px, from_py, cell_dx, cell_dy)
    local from_ix, from_iy = Placement.cell_ix(from_px, from_py)
    local to_ix = from_ix + cell_dx
    local to_iy = from_iy + cell_dy

    if not Path.can_edge(map, from_ix, from_iy, to_ix, to_iy, false) then
        return nil
    end

    return Placement.cell_node(map, to_ix, to_iy)
end

local function dist_sq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by

    return dx * dx + dy * dy
end

function Path.greedy_path_pos(map, from_px, from_py, to_px, to_py, max_steps)
    max_steps = max_steps or MAX_GREEDY_STEPS

    local to_ix, to_iy = Placement.cell_ix(to_px, to_py)
    local px, py = from_px, from_py
    local path = {}

    for _ = 1, max_steps do
        local ix, iy = Placement.cell_ix(px, py)

        if ix == to_ix and iy == to_iy then
            return path
        end

        local best_node
        local best_d = math.huge

        for i = 1, #NEIGHBORS do
            local off = NEIGHBORS[i]
            local node = Path.try_step_neighbor(map, px, py, off[1], off[2])

            if node then
                local d = dist_sq(node.px, node.py, to_px, to_py)

                if d < best_d then
                    best_d = d
                    best_node = node
                end
            end
        end

        if not best_node then
            break
        end

        path[#path + 1] = {
            x = best_node.px,
            y = best_node.py,
            z = best_node.z,
        }
        px, py = best_node.px, best_node.py
    end

    if #path == 0 then
        return nil
    end

    local last = path[#path]
    local goal_ix, goal_iy = Placement.cell_ix(to_px, to_py)
    local last_ix, last_iy = Placement.cell_ix(last.x, last.y)

    if last_ix == goal_ix and last_iy == goal_iy then
        return path
    end

    return nil
end

local function rebuild_path(map, came_from, to_ix, to_iy)
    local path = {}
    local ix, iy = to_ix, to_iy

    while came_from[cell_key(ix, iy)] do
        local node = Placement.cell_node(map, ix, iy)

        if node then
            path[#path + 1] = {
                x = node.px,
                y = node.py,
                z = node.z,
            }
        end

        local prev = came_from[cell_key(ix, iy)]
        ix, iy = prev[1], prev[2]
    end

    local reversed = {}
    local n = #path

    for i = 1, n do
        reversed[i] = path[n - i + 1]
    end

    return reversed
end

local function find_path_bfs(map, from_ix, from_iy, to_ix, to_iy)
    pool_reset()

    local visited = pool.visited
    local came_from = pool.came_from
    local queue = pool.queue

    local start_k = pool_mark(from_ix, from_iy)
    visited[start_k] = true

    local head = 1
    local tail = 1
    queue[1] = from_ix
    queue[2] = from_iy

    local expanded = 0

    while head <= tail do
        local cx = queue[head]
        local cy = queue[head + 1]
        head = head + 2

        if cx == to_ix and cy == to_iy then
            return rebuild_path(map, came_from, to_ix, to_iy)
        end

        expanded = expanded + 1

        if expanded > MAX_BFS_EXPAND then
            return nil
        end

        for i = 1, #NEIGHBORS do
            local off = NEIGHBORS[i]
            local nx = cx + off[1]
            local ny = cy + off[2]

            if cell_in_bounds(map, nx, ny) then
                local nk = cell_key(nx, ny)

                if not visited[nk] and Path.can_edge(map, cx, cy, nx, ny, false) then
                    visited[nk] = true
                    came_from[nk] = { cx, cy }
                    pool_mark(nx, ny)

                    tail = tail + 1
                    queue[tail] = nx
                    tail = tail + 1
                    queue[tail] = ny
                end
            end
        end
    end

    return nil
end

function Path.pick_reachable_near(map, px, py, radius)
    local from_node = Placement.node_at_pos(map, px, py)

    if not from_node or not map.placement then
        return nil
    end

    radius = radius or 1
    local candidates = {}
    pool_reset()

    local visited = pool.visited
    local queue = pool.queue

    local start_k = pool_mark(from_node.ix, from_node.iy)
    visited[start_k] = true

    local head = 1
    local tail = 1
    queue[1] = from_node.ix
    queue[2] = from_node.iy

    while head <= tail do
        local cx = queue[head]
        local cy = queue[head + 1]
        head = head + 2
        local node = Placement.cell_node(map, cx, cy)

        if node
            and (node.ix ~= from_node.ix or node.iy ~= from_node.iy)
            and math.abs(node.px - px) <= radius
            and math.abs(node.py - py) <= radius
        then
            candidates[#candidates + 1] = node
        end

        for i = 1, #NEIGHBORS do
            local off = NEIGHBORS[i]
            local nx = cx + off[1]
            local ny = cy + off[2]
            local nk = cell_key(nx, ny)

            if not visited[nk]
                and cell_in_bounds(map, nx, ny)
                and Path.can_edge(map, cx, cy, nx, ny, false)
            then
                local next_node = Placement.cell_node(map, nx, ny)

                if next_node
                    and math.abs(next_node.px - px) <= radius + 1
                    and math.abs(next_node.py - py) <= radius + 1
                then
                    visited[nk] = true
                    pool_mark(nx, ny)

                    tail = tail + 1
                    queue[tail] = nx
                    tail = tail + 1
                    queue[tail] = ny
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    return candidates[love.math.random(#candidates)]
end

function Path.find_path_pos(map, from_px, from_py, to_px, to_py)
    local from_ix, from_iy = Placement.cell_ix(from_px, from_py)
    local to_ix, to_iy = Placement.cell_ix(to_px, to_py)

    if from_ix == to_ix and from_iy == to_iy then
        return {}
    end

    if not Placement.has_cell(map, from_ix, from_iy)
        or not Placement.has_cell(map, to_ix, to_iy)
    then
        return nil
    end

    if Path.can_step_pos(map, from_px, from_py, to_px, to_py) then
        local node = Placement.node_at_pos(map, to_px, to_py)

        if node then
            return {
                {
                    x = node.px,
                    y = node.py,
                    z = node.z,
                },
            }
        end
    end

    local greedy = Path.greedy_path_pos(map, from_px, from_py, to_px, to_py)

    if greedy then
        return greedy
    end

    return find_path_bfs(map, from_ix, from_iy, to_ix, to_iy)
end

return Path
