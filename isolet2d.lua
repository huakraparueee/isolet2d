--[[
  isometric island core — play: setup → load_map → draw_map()
]]

local Stack = require("stack")
local Ground = require("ground")
local Tile = require("tile")
local Events = require("events")
local Setup = require("setup")
local Lookup = require("lookup")
local Pieces = require("pieces")
local Terrain = require("terrain")
local Npc = require("npc")
local Walk = require("walk")
local Placement = require("placement")
local Structure = require("structure")
local Occupancy = require("occupancy")
local Camera = require("camera")
local Footprint = require("footprint")

local M = {
    camera = Camera,
}

local CULL_PAD_TILES = 1
local CULL_CACHE_PAD_TILES = 1
local CULL_MAX_Z = 1

local current_map

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

    if raw.grid_point_per_tile then
        Ground.set_grid_point_per_tile(raw.grid_point_per_tile)
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
    local piece = Pieces.find_terrain_at(map, tile_x, tile_y)

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

    return Lookup.terrain_mat_walkable(
        cfg().terrain_mats,
        surface_mat(map, src, tile_x, tile_y)
    )
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
                cache_row[col - 1] = Lookup.terrain_mat_walkable(terrain_mats, mat)
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

    local z = Pieces.top_terrain_z(map, tile_x, tile_y)

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
            return Lookup.structure_tile_span(c.structures, kind)
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
        return Lookup.terrain_mat_color(c.terrain_mats, mat)
    end

    map.terrain_mat_alpha = function(mat)
        return Lookup.terrain_mat_alpha(c.terrain_mats, mat)
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
        return Lookup.has_structure_kind(c.structures, kind)
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
    return M.is_busy() or Npc.is_busy(active_map())
end

function M.is_npc_anim_busy(id)
    return Npc.is_anim_busy(active_map(), id)
end

function M.pos_step()
    return Ground.pos_step()
end

function M.pick_placement_near(px, py, radius)
    return Walk.pick_reachable_near(active_map(), px, py, radius)
end

function M.try_step_neighbor(from_px, from_py, cell_dx, cell_dy)
    return Walk.try_step_neighbor(
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

function M.can_step_pos(from_px, from_py, to_px, to_py)
    return Walk.can_step_pos(
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

local function grid_index(source, tile_x, tile_y)
    local c = Setup.get()
    local lx = tile_x - c.grid_origin_x
    local ly = tile_y - c.grid_origin_y

    if lx < 0 or lx >= source.tiles_w or ly < 0 or ly >= source.tiles_d then
        return nil, nil
    end

    return lx, ly
end

local function top_z_from_cache(source, cache, tile_x, tile_y)
    local lx, ly = grid_index(source, math.floor(tile_x), math.floor(tile_y))

    if not lx then
        return 0
    end

    local z = cache.tops[ly]

    if not z then
        return 0
    end

    z = z[lx]

    if not z or z < 0 then
        return 0
    end

    return z
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
            top_z_from_cache(source, cache, tx, ty),
            piece.mat
        )
        return
    end

    if entry.type == "npc" then
        Npc.draw(entry.piece, lg, layout, entry.piece.alpha, function(tx, ty)
            return top_z_from_cache(source, cache, tx, ty)
        end)
        return
    end

    if entry.type == "structure" then
        Structure.draw(entry.piece, lg, layout, entry.piece.alpha, function(tx, ty)
            return top_z_from_cache(source, cache, tx, ty)
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
        local ox, oy = Footprint.origin(piece, w, d)

        return footprint_in_rect(ox, oy, w, d, rect)
    end

    if Structure.is_piece(piece) then
        local w, d = Lookup.structure_tile_span(
            Setup.get().structures,
            piece.structure
        )

        return footprint_in_rect(piece.tile_x, piece.tile_y, w, d, rect)
    end

    if Pieces.is_terrain_block(piece) then
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
            local cell_z = top_z_from_cache(source, cache, gx, gy)
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

    local _, _, h = Lookup.npc_tile_span(Setup.get().npcs, kind)

    return h
end

local function structure_tiles_h(piece)
    if piece.tiles_h then
        return piece.tiles_h
    end

    local _, _, h = Lookup.structure_tile_span(
        Setup.get().structures,
        piece.structure
    )

    return h
end

local function piece_sort_key(piece, source, cache)
    if piece.npc then
        local w, d = Lookup.npc_tile_span(
            Setup.get().npcs,
            piece.npc.kind
        )
        local ox, oy = Footprint.origin(piece, w, d)
        local sum, ax, ay = footprint_sort_key(ox, oy, w, d, source, cache)
        local h = npc_tiles_h(piece)

        return sum + h - 1, ax, ay
    end

    if Structure.is_piece(piece) then
        local w, d = Lookup.structure_tile_span(
            Setup.get().structures,
            piece.structure
        )
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

local function build_render_cache(map, cache_rect)
    local source = map.source
    local tops = {}
    local height_cache = map.height_at_cache

    if not height_cache then
        return { tops = tops }
    end

    local min_tx, min_ty, max_tx, max_ty

    if cache_rect then
        min_tx = cache_rect.min_tx
        min_ty = cache_rect.min_ty
        max_tx = cache_rect.max_tx
        max_ty = cache_rect.max_ty
    else
        min_tx = 0
        min_ty = 0
        max_tx = source.tiles_w - 1
        max_ty = source.tiles_d - 1
    end

    for ty = min_ty, max_ty do
        local cache_row = height_cache[ty]

        if cache_row then
            local row

            for tx = min_tx, max_tx do
                local h = cache_row[tx]

                if h and h > 0 then
                    local lx, ly = grid_index(source, tx, ty)

                    if lx then
                        if not row then
                            row = {}
                            tops[ly] = row
                        end

                        row[lx] = h - 1
                    end
                end
            end
        end
    end

    return { tops = tops }
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
        and Pieces.is_terrain_block(piece)
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
        local base_z = top_z_from_cache(source, cache, tx, ty)
        max_z = math.max(max_z, base_z + structure_tiles_h(piece) - 1)
    end

    for _, piece in ipairs(map.npc_pieces or {}) do
        if piece.npc then
            local _, tx, ty = piece_sort_key(piece, source, cache)
            local base_z = top_z_from_cache(source, cache, tx, ty)
            max_z = math.max(max_z, base_z + npc_tiles_h(piece) - 1)
        end
    end

    return max_z
end

local function draw_placement_debug(map, lg, layout, view_rect)
    if not cfg().debug_draw_walkable or not view_rect then
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

local function draw_npc_pos_debug(map, lg, layout, view_rect)
    if not cfg().debug_draw_walkable or not view_rect then
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
                local sx, sy = Placement.pos_to_screen(
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
    local cache = build_render_cache(current_map, cache_rect)
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
                local struct_base_z = top_z_from_cache(source, cache, tx, ty)
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
            if piece_in_view(piece, view_rect) then
                local sum, tx, ty = piece_sort_key(piece, source, cache)
                local npc_base_z = top_z_from_cache(source, cache, tx, ty)
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

    draw_placement_debug(current_map, lg, layout, view_rect)
    draw_npc_pos_debug(current_map, lg, layout, view_rect)

    love.graphics.pop()
end

function M.set_debug_draw_walkable(enable)
    cfg().debug_draw_walkable = enable and true or false
end

function M.debug_draw_walkable()
    return cfg().debug_draw_walkable == true
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
    current_map = M.create_map(src)
    M.preload_npcs(src)

    local min_x, min_y, max_x, max_y = map_pan_bounds(src, current_map.layout)

    local c = cfg()

    Camera.set_bounds({
        min_x = min_x,
        min_y = min_y,
        max_x = max_x,
        max_y = max_y,
        view_w = c.design_width,
        view_h = c.design_height,
    })
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
    flush_pending_ops()
    Terrain.update(dt)
    Structure.update(map, dt)
    Npc.update(map, dt)
end

return M
