--[[
  Pathfinding on map.placement graph. Terrain rules live in placement rebuild; edges use node tile coords.
  Long routes use coarse tile A* (1 node/tile), then placement waypoints with string-pull.
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

local DIAG_STEP = 1.41421356
local MAX_FINE_ASTAR_EXPAND = 2048
local MAX_TILE_ASTAR_EXPAND = 1024

local pool = {
    visited = {},
    came_from = {},
    g_score = {},
    heap = {},
    visit_keys = {},
    visit_n = 0,
}

local tile_pool = {
    visited = {},
    came_from = {},
    g_score = {},
    heap = {},
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

local function tile_key(tx, ty)
    return tx * 4096 + ty
end

local function pool_reset(p)
    local keys = p.visit_keys
    local n = p.visit_n

    for i = 1, n do
        local k = keys[i]
        p.visited[k] = nil
        p.came_from[k] = nil
        p.g_score[k] = nil
    end

    p.visit_n = 0
end

local function pool_mark(p, k)
    local n = p.visit_n + 1
    p.visit_n = n
    p.visit_keys[n] = k
end

local function heap_clear(h)
    for i = #h, 1, -1 do
        h[i] = nil
    end
end

local function heap_push(h, item)
    local i = #h + 1
    h[i] = item

    while i > 1 do
        local parent = math.floor(i * 0.5)

        if h[parent].f <= h[i].f then
            break
        end

        h[parent], h[i] = h[i], h[parent]
        i = parent
    end
end

local function heap_pop(h)
    local top = h[1]
    local last = h[#h]
    h[#h] = nil

    if #h == 0 then
        return top
    end

    h[1] = last
    local i = 1

    while true do
        local left = i * 2
        local right = left + 1
        local smallest = i

        if left <= #h and h[left].f < h[smallest].f then
            smallest = left
        end

        if right <= #h and h[right].f < h[smallest].f then
            smallest = right
        end

        if smallest == i then
            break
        end

        h[i], h[smallest] = h[smallest], h[i]
        i = smallest
    end

    return top
end

local function octile_dist(dx, dy)
    dx = math.abs(dx)
    dy = math.abs(dy)
    local mn = math.min(dx, dy)
    local mx = math.max(dx, dy)

    return mx + mn * (DIAG_STEP - 1)
end

local function dist_sq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by

    return dx * dx + dy * dy
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

function Path.greedy_path_pos(map, from_px, from_py, to_px, to_py, max_steps)
    max_steps = max_steps or 48

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

local function cells_are_neighbors(ix1, iy1, ix2, iy2)
    local dx = math.abs(ix2 - ix1)
    local dy = math.abs(iy2 - iy1)

    return dx <= 1 and dy <= 1 and (dx + dy) > 0
end

local function tile_at_pos(map, px, py)
    local node = Placement.node_at_pos(map, px, py)

    if node then
        return node.tile_x, node.tile_y
    end

    return math.floor(px + 0.0001), math.floor(py + 0.0001)
end

local function tile_center_node(map, tile_x, tile_y)
    local gpp = Placement.grid_point_per_tile()
    local mid = math.floor(gpp * 0.5)
    local ix0 = tile_x * gpp
    local iy0 = tile_y * gpp
    local node = Placement.cell_node(map, ix0 + mid, iy0 + mid)

    if node then
        return node
    end

    for iy = iy0, iy0 + gpp - 1 do
        for ix = ix0, ix0 + gpp - 1 do
            node = Placement.cell_node(map, ix, iy)

            if node then
                return node
            end
        end
    end
end

local function rebuild_tile_path(came_from, to_tx, to_ty)
    local tiles = {}
    local tx, ty = to_tx, to_ty

    while came_from[tile_key(tx, ty)] do
        tiles[#tiles + 1] = { tx, ty }
        local prev = came_from[tile_key(tx, ty)]
        tx, ty = prev[1], prev[2]
    end

    local reversed = {}
    local n = #tiles

    for i = 1, n do
        reversed[i] = tiles[n - i + 1]
    end

    return reversed
end

local function max_tile_expand(from_tx, from_ty, to_tx, to_ty)
    return MAX_TILE_ASTAR_EXPAND
end

local function find_tile_path_astar(map, from_tx, from_ty, to_tx, to_ty, to_px, to_py)
    pool_reset(tile_pool)

    local closed = tile_pool.visited
    local came_from = tile_pool.came_from
    local g_score = tile_pool.g_score
    local open = tile_pool.heap

    heap_clear(open)

    local start_k = tile_key(from_tx, from_ty)
    g_score[start_k] = 0
    pool_mark(tile_pool, start_k)

    heap_push(open, {
        tx = from_tx,
        ty = from_ty,
        f = octile_dist(to_tx - from_tx, to_ty - from_ty),
        g = 0,
    })

    local expanded = 0
    local max_expand = max_tile_expand(from_tx, from_ty, to_tx, to_ty)
    local best_tx
    local best_ty
    local best_d = math.huge

    while #open > 0 do
        local current = heap_pop(open)
        local cx = current.tx
        local cy = current.ty
        local ck = tile_key(cx, cy)

        if not closed[ck] then
            closed[ck] = true
            expanded = expanded + 1

            if expanded > max_expand then
                break
            end

            if cx == to_tx and cy == to_ty then
                return rebuild_tile_path(came_from, to_tx, to_ty)
            end

            local d = dist_sq(cx + 0.5, cy + 0.5, to_px, to_py)

            if d < best_d then
                best_d = d
                best_tx = cx
                best_ty = cy
            end

            for i = 1, #NEIGHBORS do
                local off = NEIGHBORS[i]
                local nx = cx + off[1]
                local ny = cy + off[2]
                local nk = tile_key(nx, ny)

                if not closed[nk] and Path.can_step(map, cx, cy, nx, ny) then
                    local step_cost = (off[1] ~= 0 and off[2] ~= 0) and DIAG_STEP or 1
                    local tentative_g = current.g + step_cost

                    if tentative_g < (g_score[nk] or math.huge) then
                        came_from[nk] = { cx, cy }
                        g_score[nk] = tentative_g
                        pool_mark(tile_pool, nk)

                        heap_push(open, {
                            tx = nx,
                            ty = ny,
                            g = tentative_g,
                            f = tentative_g + octile_dist(to_tx - nx, to_ty - ny),
                        })
                    end
                end
            end
        end
    end

    if best_tx and (best_tx ~= from_tx or best_ty ~= from_ty) then
        return rebuild_tile_path(came_from, best_tx, best_ty)
    end

    return nil
end

local function foreach_tile_border_cell(from_tx, from_ty, to_tx, to_ty, gpp, fn)
    local dx = to_tx - from_tx
    local dy = to_ty - from_ty
    local ix0 = from_tx * gpp
    local iy0 = from_ty * gpp
    local ix1 = ix0 + gpp - 1
    local iy1 = iy0 + gpp - 1
    local seen = {}

    local function visit(ix, iy)
        local k = cell_key(ix, iy)

        if not seen[k] then
            seen[k] = true
            fn(ix, iy)
        end
    end

    if dx > 0 then
        for iy = iy0, iy1 do
            visit(ix1, iy)
        end
    elseif dx < 0 then
        for iy = iy0, iy1 do
            visit(ix0, iy)
        end
    end

    if dy > 0 then
        for ix = ix0, ix1 do
            visit(ix, iy1)
        end
    elseif dy < 0 then
        for ix = ix0, ix1 do
            visit(ix, iy0)
        end
    end
end

local function crossing_node_to_tile(map, from_tx, from_ty, to_tx, to_ty)
    if from_tx == nil or from_ty == nil then
        return tile_center_node(map, to_tx, to_ty)
    end

    local gpp = Placement.grid_point_per_tile()
    local best
    local best_d = math.huge

    foreach_tile_border_cell(from_tx, from_ty, to_tx, to_ty, gpp, function(ix, iy)
        for i = 1, #NEIGHBORS do
            local off = NEIGHBORS[i]
            local nx = ix + off[1]
            local ny = iy + off[2]

            if Path.can_edge(map, ix, iy, nx, ny, false) then
                local node = Placement.cell_node(map, nx, ny)

                if node and node.tile_x == to_tx and node.tile_y == to_ty then
                    local d = dist_sq(node.px, node.py, to_tx + 0.5, to_ty + 0.5)

                    if d < best_d then
                        best_d = d
                        best = node
                    end
                end
            end
        end
    end)

    return best or tile_center_node(map, to_tx, to_ty)
end

local function tiles_to_placement_path(map, tiles, from_tx, from_ty)
    local path = {}
    local prev_tx, prev_ty = from_tx, from_ty

    for i = 1, #tiles do
        local tile = tiles[i]
        local node = crossing_node_to_tile(map, prev_tx, prev_ty, tile[1], tile[2])

        if node then
            path[#path + 1] = {
                x = node.px,
                y = node.py,
                z = node.z,
            }
        end

        prev_tx, prev_ty = tile[1], tile[2]
    end

    if #path == 0 then
        return nil
    end

    return path
end

local function find_coarse_path_pos(map, from_px, from_py, to_px, to_py)
    local from_tx, from_ty = tile_at_pos(map, from_px, from_py)
    local to_tx, to_ty = tile_at_pos(map, to_px, to_py)

    if from_tx == to_tx and from_ty == to_ty then
        return nil
    end

    local tiles = find_tile_path_astar(map, from_tx, from_ty, to_tx, to_ty, to_px, to_py)

    if not tiles or #tiles == 0 then
        return nil
    end

    return tiles_to_placement_path(map, tiles, from_tx, from_ty)
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

local function max_fine_expand(from_ix, from_iy, to_ix, to_iy, exact_ix)
    if exact_ix then
        return math.min(
            MAX_FINE_ASTAR_EXPAND,
            math.max(256, octile_dist(to_ix - from_ix, to_iy - from_iy) * 16)
        )
    end

    return math.min(MAX_FINE_ASTAR_EXPAND, 512)
end

local function find_path_fine_astar(map, from_ix, from_iy, to_px, to_py, exact_ix, exact_iy)
    pool_reset(pool)

    local closed = pool.visited
    local came_from = pool.came_from
    local g_score = pool.g_score
    local open = pool.heap

    heap_clear(open)

    local start_k = cell_key(from_ix, from_iy)
    g_score[start_k] = 0
    pool_mark(pool, start_k)

    local to_ix, to_iy = Placement.cell_ix(to_px, to_py)

    heap_push(open, {
        ix = from_ix,
        iy = from_iy,
        f = octile_dist(to_ix - from_ix, to_iy - from_iy),
        g = 0,
    })

    local expanded = 0
    local max_expand = max_fine_expand(from_ix, from_iy, to_ix, to_iy, exact_ix)
    local best_ix
    local best_iy
    local best_d = math.huge

    while #open > 0 do
        local current = heap_pop(open)
        local cx = current.ix
        local cy = current.iy
        local ck = cell_key(cx, cy)

        if not closed[ck] then
            closed[ck] = true
            expanded = expanded + 1

            if expanded > max_expand then
                break
            end

            if exact_ix and exact_iy and cx == exact_ix and cy == exact_iy then
                return rebuild_path(map, came_from, exact_ix, exact_iy)
            end

            local node = Placement.cell_node(map, cx, cy)

            if node then
                local d = dist_sq(node.px, node.py, to_px, to_py)

                if d < best_d then
                    best_d = d
                    best_ix = cx
                    best_iy = cy
                end
            end

            for i = 1, #NEIGHBORS do
                local off = NEIGHBORS[i]
                local nx = cx + off[1]
                local ny = cy + off[2]

                if cell_in_bounds(map, nx, ny) then
                    local nk = cell_key(nx, ny)

                    if not closed[nk] and Path.can_edge(map, cx, cy, nx, ny, false) then
                        local step_cost = (off[1] ~= 0 and off[2] ~= 0) and DIAG_STEP or 1
                        local tentative_g = current.g + step_cost

                        if tentative_g < (g_score[nk] or math.huge) then
                            came_from[nk] = { cx, cy }
                            g_score[nk] = tentative_g
                            pool_mark(pool, nk)

                            heap_push(open, {
                                ix = nx,
                                iy = ny,
                                g = tentative_g,
                                f = tentative_g + octile_dist(to_ix - nx, to_iy - ny),
                            })
                        end
                    end
                end
            end
        end
    end

    if best_ix and (best_ix ~= from_ix or best_iy ~= from_iy) then
        return rebuild_path(map, came_from, best_ix, best_iy)
    end

    return nil
end

function Path.find_path_toward_pos(map, from_px, from_py, to_px, to_py)
    local from_ix, from_iy = Placement.cell_ix(from_px, from_py)
    local to_ix, to_iy = Placement.cell_ix(to_px, to_py)

    if from_ix == to_ix and from_iy == to_iy then
        return {}
    end

    if not Placement.has_cell(map, from_ix, from_iy) then
        return nil
    end

    local coarse = find_coarse_path_pos(map, from_px, from_py, to_px, to_py)

    if coarse then
        return coarse
    end

    return find_path_fine_astar(map, from_ix, from_iy, to_px, to_py, nil, nil)
end

function Path.pick_reachable_near(map, px, py, radius)
    local from_node = Placement.node_at_pos(map, px, py)

    if not from_node or not map.placement then
        return nil
    end

    radius = radius or 1
    local candidates = {}
    pool_reset(pool)

    local visited = pool.visited
    local queue = {}
    local expanded = 0

    local start_k = cell_key(from_node.ix, from_node.iy)
    pool_mark(pool, start_k)
    visited[start_k] = true

    local head = 1
    local tail = 1
    queue[1] = from_node.ix
    queue[2] = from_node.iy

    while head <= tail do
        expanded = expanded + 1

        if expanded > 256 then
            break
        end

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
                    pool_mark(pool, nk)

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

    if not Placement.has_cell(map, from_ix, from_iy) then
        return nil
    end

    if Placement.has_cell(map, to_ix, to_iy)
        and cells_are_neighbors(from_ix, from_iy, to_ix, to_iy)
        and Path.can_step_pos(map, from_px, from_py, to_px, to_py)
    then
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

    local coarse = find_coarse_path_pos(map, from_px, from_py, to_px, to_py)

    if coarse then
        return coarse
    end

    local exact_ix = Placement.has_cell(map, to_ix, to_iy) and to_ix or nil
    local exact_iy = Placement.has_cell(map, to_ix, to_iy) and to_iy or nil

    return find_path_fine_astar(map, from_ix, from_iy, to_px, to_py, exact_ix, exact_iy)
end

return Path
