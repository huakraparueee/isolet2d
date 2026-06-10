--[[
  isometric island core — play: setup → load_map → draw_map()
]]

local Stack = require("stack")
local Tile = require("tile")
local Events = require("events")
local Setup = require("setup")
local Terrain = require("terrain")
local Npc = require("npc")
local Path = require("path")
local Placement = require("placement")
local Structure = require("structure")
local Projectile = require("projectile")
local Camera = require("camera")

local M = {
    camera = Camera,
}

local CULL_PAD_TILES = 1
local CULL_CACHE_PAD_TILES = 1
local CULL_MAX_Z = 1

local current_map
local pick_marker

local function active_map()
    if not current_map then
        error("iso: call load_map first")
    end

    return current_map
end

function M.init(raw)
    Setup.set(Setup.build(raw))
    Terrain.load()
    Npc.load()
    Structure.load()
    Projectile.load()

    if raw.grid_point_per_tile then
        Placement.set_grid_point_per_tile(raw.grid_point_per_tile)
    end
end

local function cfg()
    return Setup.get()
end

local function in_bounds_for(source, tile_x, tile_y)
    local c = cfg()
    local lx = tile_x - c.grid_origin_x
    local ly = tile_y - c.grid_origin_y

    return lx >= 0
        and lx < source.tiles_w
        and ly >= 0
        and ly < source.tiles_d
end

function M.layout_for(src)
    Stack.dims(src)
    local c = cfg()

    return Tile.layout({
        design_width = c.design_width,
        design_height = c.design_height,
        tiles_w = src.tiles_w,
        tiles_d = src.tiles_d,
        grid_origin_x = c.grid_origin_x,
        grid_origin_y = c.grid_origin_y,
        map_offset_y = src.map_offset_y or c.map_offset_y or 0,
        tile_size = c.tile_size,
        iso_x_ratio = c.iso_x_ratio,
        iso_y_ratio = c.iso_y_ratio,
        iso_eh_ratio = c.iso_eh_ratio,
        scale = 1,
    })
end

local function build_height_cache(map, src)
    map.height_at_cache = {}

    for row = 1, src.tiles_d do
        local ty = row - 1
        local cache_row = {}

        map.height_at_cache[ty] = cache_row

        for col = 1, src.tiles_w do
            cache_row[col - 1] = Stack.height(src, row, col)
        end
    end
end

local function surface_mat(map, src, tile_x, tile_y)
    local piece = Terrain.find_terrain_at(map, tile_x, tile_y)

    if piece and piece.mat then
        return piece.mat
    end

    local h_row = map.height_at_cache[tile_y]
    local h = h_row and h_row[tile_x] or 0

    if h <= 0 then
        return nil
    end

    return Stack.layer_mat(
        src,
        tile_y + 1,
        tile_x + 1,
        h - 1,
        cfg().terrain_mats
    )
end

local function tile_walkable(map, src, tile_x, tile_y)
    local h_row = map.height_at_cache[tile_y]
    local h = h_row and h_row[tile_x] or 0

    if h <= 0 then
        return false
    end

    return Terrain.mat_walkable(surface_mat(map, src, tile_x, tile_y))
end

local function build_walkable_cache(map, src)
    local terrain_mats = cfg().terrain_mats

    map.walkable_at_cache = {}

    for row = 1, src.tiles_d do
        local ty = row - 1
        local cache_row = {}

        map.walkable_at_cache[ty] = cache_row

        for col = 1, src.tiles_w do
            local h = Stack.height(src, row, col)

            if h <= 0 then
                cache_row[col - 1] = false
            else
                local mat = Stack.layer_mat(src, row, col, h - 1, terrain_mats)
                cache_row[col - 1] = Terrain.mat_walkable(mat)
            end
        end
    end
end

local function refresh_walkable_at(map, src, tile_x, tile_y)
    local row = map.walkable_at_cache and map.walkable_at_cache[tile_y]

    if not row then
        return
    end

    row[tile_x] = tile_walkable(map, src, tile_x, tile_y)
end

local function refresh_height_at(map, src, tile_x, tile_y)
    local row = map.height_at_cache and map.height_at_cache[tile_y]

    if not row then
        return
    end

    local z = Terrain.top_terrain_z(map, tile_x, tile_y)

    if z >= 0 then
        row[tile_x] = z + 1
    else
        row[tile_x] = Stack.height(src, tile_y + 1, tile_x + 1)
    end

    refresh_walkable_at(map, src, tile_x, tile_y)
end

local function sync_structure_pieces(map)
    local list = {}

    for _, piece in ipairs(map.pieces or {}) do
        if Structure.is_piece(piece) and not piece._removed then
            list[#list + 1] = piece
        end
    end

    map.structure_pieces = list
end

local function sync_npc_pieces(map)
    local list = {}

    for _, piece in ipairs(map.pieces or {}) do
        if piece.npc and not piece._removed then
            list[#list + 1] = piece
        end
    end

    map.npc_pieces = list
end

function M.bind_grid(map, src)
    local c = cfg()

    build_height_cache(map, src)
    build_walkable_cache(map, src)

    map.grid = {
        height_at = function(tile_x, tile_y)
            local row = map.height_at_cache[tile_y]

            if row then
                return row[tile_x] or 0
            end

            return 0
        end,
        walkable_at = function(tile_x, tile_y)
            local row = map.walkable_at_cache[tile_y]

            if row then
                return row[tile_x] or false
            end

            return false
        end,
        surface_z = function(tile_x, tile_y)
            local h = map.grid.height_at(tile_x, tile_y)

            return h > 0 and h - 1 or 0
        end,
        in_bounds = function(tile_x, tile_y)
            return in_bounds_for(src, tile_x, tile_y)
        end,
        structure_span = function(kind)
            return Structure.tile_span(kind)
        end,
    }

    map.refresh_height_at = function(tile_x, tile_y)
        refresh_height_at(map, src, tile_x, tile_y)
        Placement.rebuild_tile(map, tile_x, tile_y)
    end

    map.rebuild_placement_tile = function(tile_x, tile_y)
        Placement.rebuild_tile(map, tile_x, tile_y)
    end

    map.sync_structure_pieces = function()
        sync_structure_pieces(map)
    end

    map.sync_npc_pieces = function()
        sync_npc_pieces(map)
    end

    map.terrain_mat_color = function(mat)
        return Terrain.mat_color(mat)
    end

    map.terrain_mat_alpha = function(mat)
        return Terrain.mat_alpha(mat)
    end

    map.apply_terrain_mat = function(piece, mat)
        local spec = mat and c.terrain_mats[mat]

        if not spec then
            return
        end

        if spec.alpha ~= nil then
            piece.alpha = spec.alpha
        end
    end

    map.has_structure_kind = function(kind)
        return Structure.has_kind(kind)
    end
end

function M.create_map(src)
    Stack.dims(src)

    -- 1. tile screen layout
    local layout = M.layout_for(src)

    -- 2. terrain pieces on tile grid
    local map = {
        source = src,
        layout = layout,
        pieces = Terrain.initial_pieces(src, in_bounds_for),
        pieces_updates = nil,
        pieces_removals = nil,
        pending_ops = nil,
        npc_paused = false,
        structure_paused = false,
        projectile_paused = false,
    }

    M.bind_grid(map, src)

    -- 3. structure list (pieces added via events hold tile_x, tile_y)
    sync_structure_pieces(map)

    -- 4. placement graph from terrain + structure
    Placement.rebuild(map)

    sync_npc_pieces(map)
    Terrain.build_bake(map)

    return map
end

function M.is_busy()
    return Events.is_busy(active_map())
end

function M.is_blocked()
    return M.is_busy() or Npc.is_busy(active_map()) or Projectile.is_busy(active_map())
end

function M.is_npc_anim_busy(id)
    return Npc.is_anim_busy(active_map(), id)
end

function M.pos_step()
    return Placement.pos_step()
end

function M.pick_placement_near(px, py, radius)
    return Path.pick_reachable_near(active_map(), px, py, radius)
end

local function point_in_tile_top(layout, wx, wy, tile_x, tile_y, tile_z)
    local cx, cy = Tile.to_screen(layout, tile_x, tile_y, tile_z)
    local s = layout.scale or 1
    local tile_px = layout.tile_size * s
    local hw = Tile.hw_for_tile_span(tile_px, layout.iso_x_ratio)
    local hd = Tile.hd_for_tile_span(tile_px, layout.iso_y_ratio)
    local eh = Tile.eh_for_tile_span(tile_px, layout.iso_eh_ratio)
    local yt = cy - eh

    return math.abs(wx - cx) / hw + math.abs(wy - yt) / hd <= 1.001
end

local function pick_max_z(map)
    local max_z = 0
    local cache = map.height_at_cache

    if not cache then
        return max_z
    end

    for _, row in pairs(cache) do
        for _, height in pairs(row) do
            if height > 0 then
                max_z = math.max(max_z, height - 1)
            end
        end
    end

    return max_z
end

local function pick_candidates(layout, wx, wy, max_z)
    local seen = {}
    local list = {}

    local function add(tile_x, tile_y)
        local key = tile_x .. "," .. tile_y

        if seen[key] then
            return
        end

        seen[key] = true
        list[#list + 1] = { tile_x, tile_y }
    end

    for z_try = 0, max_z do
        local tx0, ty0 = Tile.from_screen(layout, wx, wy, z_try)
        local base_tx = math.floor(tx0 + 0.5)
        local base_ty = math.floor(ty0 + 0.5)

        for oy = -1, 1 do
            for ox = -1, 1 do
                add(base_tx + ox, base_ty + oy)
            end
        end
    end

    return list
end

local function pick_tile_at_world(map, wx, wy)
    local layout = map.layout
    local grid = map.grid

    if not layout or not grid then
        return nil
    end

    local best
    local best_depth = -math.huge
    local max_z = pick_max_z(map)

    for _, candidate in ipairs(pick_candidates(layout, wx, wy, max_z)) do
        local tile_x = candidate[1]
        local tile_y = candidate[2]

        if grid.in_bounds(tile_x, tile_y) and grid.height_at(tile_x, tile_y) > 0 then
            local z = grid.surface_z(tile_x, tile_y)

            if point_in_tile_top(layout, wx, wy, tile_x, tile_y, z) then
                local depth = tile_x + tile_y + z

                if depth > best_depth then
                    best_depth = depth

                    best = {
                        tile_x = tile_x,
                        tile_y = tile_y,
                        z = z,
                        in_bounds = true,
                        walkable = grid.walkable_at(tile_x, tile_y),
                        sx = wx,
                        sy = wy,
                    }
                end
            end
        end
    end

    return best
end

function M.try_step_neighbor(from_px, from_py, cell_dx, cell_dy)
    return Path.try_step_neighbor(
        active_map(),
        from_px,
        from_py,
        cell_dx,
        cell_dy
    )
end

function M.on_walkable_cell(piece)
    return Placement.on_walkable_cell(active_map(), piece)
end

function M.placement_pos(ix, iy)
    local node = Placement.cell_node(active_map(), ix, iy)

    if not node then
        return nil, nil
    end

    return node.px, node.py
end

function M.placement_to_design(px, py, tile_z)
    local map = active_map()
    local sx, sy = Tile.placement_to_screen(map.layout, px, py, tile_z or 0)

    return sx + Camera.pan_x, sy + Camera.pan_y
end

function M.clear_projectiles()
    Projectile.clear(active_map())
end

function M.projectile_count()
    return Projectile.count(active_map())
end

function M.each_projectile(fn)
    Projectile.each(active_map(), fn)
end

function M.set_npc_paused(paused)
    local map = active_map()

    if map then
        map.npc_paused = paused == true
    end
end

function M.set_structure_paused(paused)
    local map = active_map()

    if map then
        map.structure_paused = paused == true
    end
end

function M.is_npc_paused()
    local map = active_map()

    return map and map.npc_paused == true
end

function M.is_structure_paused()
    local map = active_map()

    return map and map.structure_paused == true
end

function M.pause_npc()
    M.set_npc_paused(true)
end

function M.play_npc()
    M.set_npc_paused(false)
end

function M.pause_structure()
    M.set_structure_paused(true)
end

function M.play_structure()
    M.set_structure_paused(false)
end

function M.set_projectile_paused(paused)
    local map = active_map()

    if map then
        map.projectile_paused = paused == true
    end
end

function M.is_projectile_paused()
    local map = active_map()

    return map and map.projectile_paused == true
end

function M.pause_projectile()
    M.set_projectile_paused(true)
end

function M.play_projectile()
    M.set_projectile_paused(false)
end

local function terrain_cache_key(rect)
    if not rect then
        return nil
    end

    return rect.min_tx
        .. ","
        .. rect.min_ty
        .. ","
        .. rect.max_tx
        .. ","
        .. rect.max_ty
end

local function terrain_render_cache(map, cache_rect)
    local key = terrain_cache_key(cache_rect)

    if key and map._terrain_cache_key == key and map._terrain_cache then
        return map._terrain_cache
    end

    local cache = Tile.build_render_cache(map, cache_rect)

    map._terrain_cache_key = key
    map._terrain_cache = cache

    return cache
end

function M.can_step_pos(from_px, from_py, to_px, to_py)
    return Path.can_step_pos(
        active_map(),
        from_px,
        from_py,
        to_px,
        to_py
    )
end

function M.preload_npcs(_src)
    Npc.preload_npcs()
end

local function default_viewport()
    local c = cfg()

    return {
        x = -Camera.pan_x,
        y = -Camera.pan_y,
        w = c.design_width,
        h = c.design_height,
    }
end

local function sum_bucket_insert(buckets, min_sum, max_sum, entry)
    local sum = entry.sum
    local list = buckets[sum]

    if not list then
        list = {}
        buckets[sum] = list
    end

    list[#list + 1] = entry

    if sum < min_sum then
        min_sum = sum
    end

    if sum > max_sum then
        max_sum = sum
    end

    return min_sum, max_sum
end

local function compare_draw_entries(a, b)
    if a.tx ~= b.tx then
        return a.tx < b.tx
    end

    if a.ty ~= b.ty then
        return a.ty < b.ty
    end

    return a.sort_layer < b.sort_layer
end

local function foreach_sum_bucket_sorted(buckets, min_sum, max_sum, fn)
    if max_sum < min_sum then
        return
    end

    for sum = min_sum, max_sum do
        local list = buckets[sum]

        if list and #list > 0 then
            if #list > 1 then
                table.sort(list, compare_draw_entries)
            end

            for i = 1, #list do
                fn(list[i])
            end
        end
    end
end

local function draw_layer_entry(lg, layout, source, cache, map, entry)
    if entry.type == "chunk" then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(entry.chunk.canvas, entry.chunk.x, entry.chunk.y)
        return
    end

    if entry.type == "terrain_piece" then
        local piece = entry.piece
        local tx, ty = piece.tile_x, piece.tile_y
        local tz = piece.tile_z or 0

        Terrain.draw_unit_cube(
            lg,
            layout,
            cache,
            map,
            tx,
            ty,
            tz,
            piece.color,
            piece.alpha or 1,
            Tile.top_z_from_cache(source, cache, tx, ty),
            piece.mat
        )
        return
    end

    if entry.type == "npc" then
        Npc.draw(entry.piece, lg, layout, entry.piece.alpha, function(tx, ty)
            return Tile.top_z_from_cache(source, cache, tx, ty)
        end)
        return
    end

    if entry.type == "structure" then
        Structure.draw(entry.piece, lg, layout, entry.piece.alpha, function(tx, ty)
            return Tile.top_z_from_cache(source, cache, tx, ty)
        end)
    end
end

local function footprint_in_rect(min_tx, min_ty, tiles_w, tiles_d, rect)
    local max_tx = min_tx + tiles_w - 1
    local max_ty = min_ty + tiles_d - 1

    return min_tx <= rect.max_tx
        and max_tx >= rect.min_tx
        and min_ty <= rect.max_ty
        and max_ty >= rect.min_ty
end

local function tile_in_rect(tx, ty, rect)
    return tx >= rect.min_tx
        and tx <= rect.max_tx
        and ty >= rect.min_ty
        and ty <= rect.max_ty
end

local function piece_in_view(piece, rect)
    if not rect then
        return true
    end

    if piece.npc then
        local w = piece.tiles_w or 1
        local d = piece.tiles_d or 1
        local ox, oy = Tile.origin(piece, w, d)

        return footprint_in_rect(ox, oy, w, d, rect)
    end

    if Structure.is_piece(piece) then
        local w, d = Structure.tile_span(piece.structure)

        return footprint_in_rect(piece.tile_x, piece.tile_y, w, d, rect)
    end

    if Terrain.is_terrain_block(piece) then
        return tile_in_rect(piece.tile_x, piece.tile_y, rect)
    end

    return true
end

local function footprint_sort_key(tile_x, tile_y, tiles_w, tiles_d, source, cache)
    local ox = tile_x
    local oy = tile_y
    local max_sum = -1
    local ax = math.floor(ox + tiles_w - 1 + 0.5)
    local ay = math.floor(oy + tiles_d - 1 + 0.5)

    for ly = 0, tiles_d - 1 do
        for lx = 0, tiles_w - 1 do
            local tx = ox + lx
            local ty = oy + ly
            local gx = math.floor(tx + 0.5)
            local gy = math.floor(ty + 0.5)
            local cell_z = Tile.top_z_from_cache(source, cache, gx, gy)
            local sum = gx + gy + cell_z

            if sum > max_sum then
                max_sum = sum
                ax = gx
                ay = gy
            end
        end
    end

    return max_sum, ax, ay
end

local function npc_tiles_h(piece)
    if piece.tiles_h then
        return piece.tiles_h
    end

    local kind = piece.npc and piece.npc.kind

    if not kind then
        return 1
    end

    local _, _, h = Npc.tile_span(kind)

    return h
end

local function structure_tiles_h(piece)
    if piece.tiles_h then
        return piece.tiles_h
    end

    local _, _, h = Structure.tile_span(piece.structure)

    return h
end

local function piece_sort_key(piece, source, cache)
    if piece.npc then
        local w, d = Npc.tile_span(piece.npc.kind)
        local ox, oy = Tile.origin(piece, w, d)
        local sum, ax, ay = footprint_sort_key(ox, oy, w, d, source, cache)
        local h = npc_tiles_h(piece)

        return sum + h - 1, ax, ay
    end

    if Structure.is_piece(piece) then
        local w, d = Structure.tile_span(piece.structure)
        local sum, ax, ay = footprint_sort_key(
            piece.tile_x,
            piece.tile_y,
            w,
            d,
            source,
            cache
        )
        local h = structure_tiles_h(piece)

        return sum + h - 1, ax, ay
    end

    local tx = piece.tile_x
    local ty = piece.tile_y
    local z = piece.tile_z or 0

    return tx + ty + z, tx, ty
end

local function point_in_rect(wx, wy, x0, y0, x1, y1)
    return wx >= x0 and wx <= x1 and wy >= y0 and wy <= y1
end

local function resolve_hit_size(def)
    if not def then
        return 1, 1
    end

    local hit = def.hit

    if hit then
        return hit.w or def.w or 1, hit.h or def.h or 1
    end

    return def.w or 1, def.h or 1
end

local function aabb_hit_bounds(anchor_x, anchor_y, box_w, box_h, scale)
    local hw = box_w * 0.5 * scale
    local h = box_h * scale

    return anchor_x - hw, anchor_y - h, anchor_x + hw, anchor_y
end

local function npc_feet_screen(map, layout, piece, z_at)
    if piece.pos_x ~= nil and piece.pos_y ~= nil then
        return Tile.placement_to_screen(
            layout,
            piece.pos_x,
            piece.pos_y,
            piece.tile_z
        )
    end

    local w, d = Npc.npc_tile_span(piece)

    return Tile.feet_screen_from_piece(layout, piece, w, d, z_at)
end

local function structure_feet_screen(map, layout, piece, z_at)
    local w, d = Structure.tile_span(piece.structure)

    return Tile.feet_screen(layout, {
        ox = piece.tile_x,
        oy = piece.tile_y,
        tiles_w = w,
        tiles_d = d,
        tile_z = piece.tile_z,
        z_at = z_at,
    })
end

local function pack_structure(piece)
    if not piece then
        return nil
    end

    return {
        structure_id = piece.structure_id,
        kind = piece.structure,
    }
end

local function pack_npc(piece)
    if not piece or not piece.npc then
        return nil
    end

    return {
        npc_id = piece.npc_id,
        kind = piece.npc.kind,
    }
end

local function pick_placement_at_world(map, layout, wx, wy)
    local placement = map.placement

    if not placement then
        return nil
    end

    local max_dist = layout.tile_size * (layout.scale or 1) * 0.45
    local max_d2 = max_dist * max_dist
    local best
    local best_d2

    for _, node in ipairs(placement.nodes) do
        local dx = node.sx - wx
        local dy = node.sy - wy
        local d2 = dx * dx + dy * dy

        if d2 <= max_d2 and (not best_d2 or d2 < best_d2) then
            best = node
            best_d2 = d2
        end
    end

    if not best then
        return nil
    end

    return {
        x = best.ix,
        y = best.iy,
        z = best.z,
    }
end

local function npc_sprite_hit(map, layout, piece, wx, wy, z_at)
    if not Npc.is_active(piece) then
        return false
    end

    local def = Npc.def(piece.npc.kind)

    if not def then
        return false
    end

    local scale = layout.scale or 1
    local feet_x, feet_y = npc_feet_screen(map, layout, piece, z_at)
    local hit_w, hit_h = resolve_hit_size(def)
    local x0, y0, x1, y1 = aabb_hit_bounds(feet_x, feet_y, hit_w, hit_h, scale)

    return point_in_rect(wx, wy, x0, y0, x1, y1)
end

local function structure_sprite_hit(map, layout, piece, wx, wy, z_at)
    if piece._removed or not Structure.is_piece(piece) then
        return false
    end

    local def = cfg().structures[piece.structure]

    if not def then
        return false
    end

    local scale = layout.scale or 1
    local feet_x, feet_y = structure_feet_screen(map, layout, piece, z_at)
    local hit_w, hit_h = resolve_hit_size(def)
    local x0, y0, x1, y1 = aabb_hit_bounds(feet_x, feet_y, hit_w, hit_h, scale)

    return point_in_rect(wx, wy, x0, y0, x1, y1)
end

local function pick_sprite_target(map, layout, source, cache, wx, wy)
    local z_at = function(tx, ty)
        return Tile.top_z_from_cache(source, cache, tx, ty)
    end
    local best_depth = -math.huge
    local best_type
    local best_piece

    for _, piece in ipairs(map.npc_pieces or {}) do
        if npc_sprite_hit(map, layout, piece, wx, wy, z_at) then
            local depth = piece_sort_key(piece, source, cache)

            if depth > best_depth then
                best_depth = depth
                best_type = "npc"
                best_piece = piece
            end
        end
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if structure_sprite_hit(map, layout, piece, wx, wy, z_at) then
            local depth = piece_sort_key(piece, source, cache)

            if depth > best_depth then
                best_depth = depth
                best_type = "structure"
                best_piece = piece
            end
        end
    end

    return best_type, best_piece
end

function M.query_at_design(design_x, design_y)
    local map = active_map()
    local wx = design_x - Camera.pan_x
    local wy = design_y - Camera.pan_y
    local layout = map.layout
    local source = map.source
    local cache = Tile.build_render_cache(map, nil)
    local tile_hit = pick_tile_at_world(map, wx, wy)
    local tile

    if tile_hit then
        local terrain = Terrain.find_terrain_at(map, tile_hit.tile_x, tile_hit.tile_y)

        tile = {
            x = tile_hit.tile_x,
            y = tile_hit.tile_y,
            z = tile_hit.z,
            walkable = tile_hit.walkable,
            in_bounds = tile_hit.in_bounds,
            mat = terrain and terrain.mat,
        }
    end

    local placement = pick_placement_at_world(map, layout, wx, wy)
    local structure_on_tile = tile and Structure.find_at(map, tile.x, tile.y)
    local target_type, target_piece = pick_sprite_target(map, layout, source, cache, wx, wy)
    local target
    local npc
    local structure = pack_structure(structure_on_tile)

    if target_type == "npc" then
        target = "npc"
        npc = pack_npc(target_piece)
    elseif target_type == "structure" then
        target = "structure"
        structure = pack_structure(target_piece)
    elseif tile then
        target = "ground"
    end

    if not tile and not target_type then
        pick_marker = nil
        return nil
    end

    pick_marker = { wx = wx, wy = wy }

    return {
        wx = wx,
        wy = wy,
        tile = tile,
        placement = placement,
        structure = structure,
        npc = npc,
        target = target,
    }
end

function M.pick_at_design(design_x, design_y)
    local map = active_map()
    local wx = design_x - Camera.pan_x
    local wy = design_y - Camera.pan_y
    local hit = pick_tile_at_world(map, wx, wy)

    if not hit then
        return nil
    end

    hit.wx = wx
    hit.wy = wy

    return hit
end

local function tile_rect_for_viewport(layout, viewport, pad)
    if not viewport then
        return nil
    end

    local min_tx, min_ty, max_tx, max_ty = Tile.visible_rect(
        layout,
        viewport.x,
        viewport.y,
        viewport.w,
        viewport.h,
        { pad = pad, max_z = CULL_MAX_Z }
    )

    return {
        min_tx = min_tx,
        min_ty = min_ty,
        max_tx = max_tx,
        max_ty = max_ty,
    }
end

local entry_pool = {}
local entry_pool_i = 1

local function entry_take()
    local entry = entry_pool[entry_pool_i]

    if not entry then
        entry = {}
        entry_pool[entry_pool_i] = entry
    end

    entry_pool_i = entry_pool_i + 1

    return entry
end

local function entry_pool_reset()
    entry_pool_i = 1
end

local function is_live_terrain_piece(piece)
    return not piece._removed
        and Terrain.is_terrain_block(piece)
        and not piece.baked
end

local function terrain_draw_max_z(map, source, cache)
    local max_z = map.terrain_bake_max_z or 0

    for _, piece in ipairs(map.pieces or {}) do
        if is_live_terrain_piece(piece) then
            max_z = math.max(max_z, piece.tile_z or 0)
        end
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        local _, tx, ty = piece_sort_key(piece, source, cache)
        local base_z = Tile.top_z_from_cache(source, cache, tx, ty)
        max_z = math.max(max_z, base_z + structure_tiles_h(piece) - 1)
    end

    for _, piece in ipairs(map.npc_pieces or {}) do
        if piece.npc then
            local _, tx, ty = piece_sort_key(piece, source, cache)
            local base_z = Tile.top_z_from_cache(source, cache, tx, ty)
            max_z = math.max(max_z, base_z + npc_tiles_h(piece) - 1)
        end
    end

    return max_z
end

local function draw_placement_debug(map, lg, layout, view_rect)
    if not cfg().debug_draw_map or not view_rect then
        return
    end

    local placement = map.placement

    if not placement then
        return
    end

    local r = math.max(1, math.floor((layout.tile_size or 64) * (layout.scale or 1) * 0.02 + 0.5))

    lg.setColor(0.2, 1, 0.35, 0.55)

    for _, node in ipairs(placement.nodes) do
        if node.tile_x >= view_rect.min_tx
            and node.tile_x <= view_rect.max_tx
            and node.tile_y >= view_rect.min_ty
            and node.tile_y <= view_rect.max_ty
        then
            lg.circle("fill", node.sx, node.sy, r)
        end
    end
end

local function draw_hit_debug(map, lg, layout, view_rect)
    if not cfg().debug_draw_map or not view_rect then
        return
    end

    local source = map.source
    local cache = Tile.build_render_cache(map, view_rect)
    local z_at = function(tx, ty)
        return Tile.top_z_from_cache(source, cache, tx, ty)
    end
    local scale = layout.scale or 1

    lg.setLineWidth(1)

    for _, piece in ipairs(map.npc_pieces or {}) do
        if piece.npc and not piece._removed then
            local def = Npc.def(piece.npc.kind)

            if def then
                local feet_x, feet_y = npc_feet_screen(map, layout, piece, z_at)
                local hit_w, hit_h = resolve_hit_size(def)
                local x0, y0, x1, y1 = aabb_hit_bounds(
                    feet_x,
                    feet_y,
                    hit_w,
                    hit_h,
                    scale
                )

                lg.setColor(0.35, 0.75, 1, 0.85)
                lg.rectangle("line", x0, y0, x1 - x0, y1 - y0)
            end
        end
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if not piece._removed and Structure.is_piece(piece) then
            local def = cfg().structures[piece.structure]

            if def then
                local feet_x, feet_y = structure_feet_screen(map, layout, piece, z_at)
                local hit_w, hit_h = resolve_hit_size(def)
                local x0, y0, x1, y1 = aabb_hit_bounds(
                    feet_x,
                    feet_y,
                    hit_w,
                    hit_h,
                    scale
                )

                lg.setColor(1, 0.45, 0.9, 0.85)
                lg.rectangle("line", x0, y0, x1 - x0, y1 - y0)
            end
        end
    end

    lg.setColor(1, 1, 1, 1)
end

local function draw_pick_marker(lg, layout)
    if not cfg().debug_draw_map or not pick_marker then
        return
    end

    local ts = layout.tile_size * (layout.scale or 1)
    local r = math.max(4, ts * 0.06)

    lg.setColor(1, 0.85, 0.1, 0.95)
    lg.setLineWidth(2)
    lg.circle("line", pick_marker.wx, pick_marker.wy, r)
    lg.circle("fill", pick_marker.wx, pick_marker.wy, math.max(2, r * 0.25))
    lg.setColor(1, 1, 1, 1)
    lg.setLineWidth(1)
end

local function draw_npc_pos_debug(map, lg, layout, view_rect)
    if not cfg().debug_draw_map or not view_rect then
        return
    end

    local ts = layout.tile_size * (layout.scale or 1)
    local r = math.max(2, math.floor(ts * 0.04 + 0.5))

    lg.setColor(1, 0.15, 0.15, 0.9)

    for _, piece in ipairs(map.npc_pieces or {}) do
        if piece.npc and piece.pos_x ~= nil and piece.pos_y ~= nil then
            local anchor_tx = math.floor(piece.pos_x)
            local anchor_ty = math.floor(piece.pos_y)

            if anchor_tx >= view_rect.min_tx
                and anchor_tx <= view_rect.max_tx
                and anchor_ty >= view_rect.min_ty
                and anchor_ty <= view_rect.max_ty
            then
                local sx, sy = Tile.placement_to_screen(
                    layout,
                    piece.pos_x,
                    piece.pos_y,
                    piece.tile_z
                )

                lg.circle("fill", sx, sy, r)
            end
        end
    end
end

function M.draw_map()
    if not current_map then
        return
    end

    love.graphics.push()
    Camera.apply()

    local vp = default_viewport()
    local lg = love.graphics
    local source = current_map.source
    local layout = current_map.layout
    local view_rect = tile_rect_for_viewport(layout, vp, CULL_PAD_TILES)
    local cache_rect = tile_rect_for_viewport(layout, vp, CULL_PAD_TILES + CULL_CACHE_PAD_TILES)
    local cache = terrain_render_cache(current_map, cache_rect)
    local max_z = terrain_draw_max_z(current_map, source, cache)

    if source.background then
        lg.clear(
            source.background.R or 0,
            source.background.G or 0,
            source.background.B or 0,
            1
        )
    end

    Terrain.draw(current_map)

    entry_pool_reset()
    local buckets = {}
    local min_sum, max_sum = math.huge, -math.huge

    for tile_z = 0, max_z do
        for _, piece in ipairs(current_map.pieces or {}) do
            if (piece.tile_z or 0) == tile_z
                and piece_in_view(piece, view_rect)
                and is_live_terrain_piece(piece)
            then
                local sum, tx, ty = piece_sort_key(piece, source, cache)

                local entry = entry_take()
                entry.type = "terrain_piece"
                entry.chunk = nil
                entry.piece = piece
                entry.sum = sum
                entry.tx = tx
                entry.ty = ty
                entry.sort_layer = 1
                min_sum, max_sum = sum_bucket_insert(buckets, min_sum, max_sum, entry)
            end
        end

        for _, piece in ipairs(current_map.structure_pieces or {}) do
            if piece_in_view(piece, view_rect) then
                local sum, tx, ty = piece_sort_key(piece, source, cache)
                local struct_base_z = Tile.top_z_from_cache(source, cache, tx, ty)
                local struct_top_z = struct_base_z + structure_tiles_h(piece) - 1

                if struct_top_z == tile_z then
                    local entry = entry_take()
                    entry.type = "structure"
                    entry.chunk = nil
                    entry.piece = piece
                    entry.sum = sum
                    entry.tx = tx
                    entry.ty = ty
                    entry.sort_layer = 2
                    min_sum, max_sum = sum_bucket_insert(buckets, min_sum, max_sum, entry)
                end
            end
        end

        for _, piece in ipairs(current_map.npc_pieces or {}) do
            if Npc.is_active(piece) and piece_in_view(piece, view_rect) then
                local sum, tx, ty = piece_sort_key(piece, source, cache)
                local npc_base_z = Tile.top_z_from_cache(source, cache, tx, ty)
                local npc_top_z = npc_base_z + npc_tiles_h(piece) - 1

                if npc_top_z == tile_z then
                    local entry = entry_take()
                    entry.type = "npc"
                    entry.chunk = nil
                    entry.piece = piece
                    entry.sum = sum
                    entry.tx = tx
                    entry.ty = ty
                    entry.sort_layer = 3
                    min_sum, max_sum = sum_bucket_insert(buckets, min_sum, max_sum, entry)
                end
            end
        end
    end

    foreach_sum_bucket_sorted(buckets, min_sum, max_sum, function(entry)
        draw_layer_entry(lg, layout, source, cache, current_map, entry)
    end)

    lg.setColor(1, 1, 1, 1)
    for _, proj in ipairs(current_map.projectiles or {}) do
        local tx = math.floor(proj.px + 0.0001)
        local ty = math.floor(proj.py + 0.0001)

        if tile_in_rect(tx, ty, view_rect) then
            Projectile.draw(proj, lg, layout)
        end
    end

    draw_placement_debug(current_map, lg, layout, view_rect)
    draw_npc_pos_debug(current_map, lg, layout, view_rect)
    draw_hit_debug(current_map, lg, layout, view_rect)
    draw_pick_marker(lg, layout)

    love.graphics.pop()
end

function M.set_pick_marker(wx, wy)
    if wx == nil or wy == nil then
        pick_marker = nil
        return
    end

    pick_marker = { wx = wx, wy = wy }
end

function M.set_debug_draw_map(enable)
    cfg().debug_draw_map = enable and true or false
end

function M.debug_draw_map()
    return cfg().debug_draw_map == true
end

local function map_pan_bounds(src, layout)
    local c = cfg()
    local ox = c.grid_origin_x
    local oy = c.grid_origin_y
    local w = src.tiles_w
    local d = src.tiles_d
    local corners = {
        { ox, oy },
        { ox + w - 1, oy },
        { ox, oy + d - 1 },
        { ox + w - 1, oy + d - 1 },
    }
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge

    for _, corner in ipairs(corners) do
        local tx, ty = corner[1], corner[2]
        local top_z = math.max(
            0,
            Stack.height(src, ty - oy + 1, tx - ox + 1) - 1
        )

        for z = 0, top_z do
            local x0, y0, x1, y1 = Tile.bounds(layout, tx, ty, z)

            min_x = math.min(min_x, x0)
            min_y = math.min(min_y, y0)
            max_x = math.max(max_x, x1)
            max_y = math.max(max_y, y1)
        end
    end

    local pad = layout.tile_size * (layout.scale or 1)

    return min_x - pad, min_y - pad, max_x + pad, max_y + pad
end

function M.load_map(src)
    pick_marker = nil
    current_map = M.create_map(src)
    current_map._terrain_cache = nil
    current_map._terrain_cache_key = nil
    M.preload_npcs(src)

    local min_x, min_y, max_x, max_y = map_pan_bounds(src, current_map.layout)

    local c = cfg()
    local oy = current_map.layout.map_offset_y or 0

    Camera.set_bounds({
        min_x = min_x,
        min_y = min_y - oy,
        max_x = max_x,
        max_y = max_y - oy,
        view_w = c.design_width,
        view_h = c.design_height,
    })
    Camera.reset()
end

function M.find_by_id(id)
    return Npc.find_by_id(active_map(), id)
end

function M.each_npc_piece(fn)
    if not fn then
        return
    end

    for _, piece in ipairs(active_map().npc_pieces or {}) do
        fn(piece)
    end
end

local function apply_pending_ops(map, ops)
    if not ops then
        return
    end

    for _, op in ipairs(ops) do
        if op.type == "npc.add" then
            Npc.add(map, op.piece, op.ev)
        elseif op.type == "npc.place" then
            Npc.place(map, op.ev)
        elseif op.type == "npc.retire" then
            Npc.retire(map, op.id)
        elseif op.type == "structure.add" then
            Structure.init_piece(op.piece, op.ev)

            local kind = op.ev.kind or op.ev.structure

            if map.rebuild_placement_tile then
                for _, cell in ipairs(
                    Structure.footprint_cells(
                        map,
                        op.piece.tile_x,
                        op.piece.tile_y,
                        kind
                    )
                ) do
                    map.rebuild_placement_tile(cell.tile_x, cell.tile_y)
                end
            end
        elseif op.type == "npc.set_mode" then
            Npc.set_mode(map, op.mode, op.id, op.opts)
        elseif op.type == "structure.set_mode" then
            Structure.set_mode(map, op.mode, op.id, op.opts)
        elseif op.type == "npc.walk_to" then
            if op.pos_x ~= nil and op.pos_y ~= nil then
                Npc.walk_to_pos(map, op.pos_x, op.pos_y, op.id, op.tile_z)
            else
                Npc.walk_to(map, op.tile_x, op.tile_y, op.id, op.tile_z)
            end
        elseif op.type == "projectile.spawn" then
            Projectile.spawn(map, op.ev)
        elseif op.type == "npc.shoot" then
            Projectile.shoot_from_npc(map, op.ev)
        elseif op.type == "npc.remove" then
            Npc.remove(map, op.id, { duration = op.duration })
        end
    end
end

local function flush_pending_ops()
    apply_pending_ops(active_map(), Events.take_pending_ops(active_map()))
end

function M.run(ev)
    Events.run(active_map(), ev)
    flush_pending_ops()
end

function M.run_many(evs)
    Events.run_many(active_map(), evs)
    flush_pending_ops()
end

function M.update(dt)
    Events.update(active_map(), dt)
end

function M.tick(dt)
    local map = active_map()

    M.update(dt)
    Projectile.update(map, dt)
    flush_pending_ops()
    Terrain.update(dt)
    Structure.update(map, dt)
    Npc.update(map, dt)
end

return M
