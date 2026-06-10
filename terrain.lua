--[[
  Pipeline step 2 — terrain pieces on tile_x, tile_y (draw + height/walkable cache).
]]

local Stack = require("stack")
local Setup = require("setup")
local Tile = require("tile")
local anim8 = require("anim8")

local Terrain = {}

function Terrain.is_terrain_block(piece)
    return piece.mat ~= nil or piece.color ~= nil
end

function Terrain.top_terrain_z(map, tile_x, tile_y)
    local max_z = -1

    for _, piece in ipairs(map.pieces or {}) do
        if Terrain.is_terrain_block(piece)
            and piece.tile_x == tile_x
            and piece.tile_y == tile_y
        then
            max_z = math.max(max_z, piece.tile_z or 0)
        end
    end

    return max_z
end

function Terrain.find_at(map, tile_x, tile_y, tile_z)
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

function Terrain.find_terrain_at(map, tile_x, tile_y, tile_z)
    if tile_z ~= nil then
        for _, piece in ipairs(map.pieces or {}) do
            if Terrain.is_terrain_block(piece)
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
        if Terrain.is_terrain_block(piece)
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

local function mat_spec(mat)
    if not mat then
        return nil
    end

    return Setup.get().terrain_mats[mat]
end

function Terrain.mat_color(mat)
    local spec = mat_spec(mat)

    if spec and spec.color then
        return spec.color[1], spec.color[2], spec.color[3]
    end
end

function Terrain.mat_walkable(mat)
    if not mat then
        return true
    end

    local spec = mat_spec(mat)

    if spec and spec.walkable == false then
        return false
    end

    return true
end

function Terrain.mat_alpha(mat)
    if not mat then
        return 1
    end

    local spec = mat_spec(mat)

    if spec and spec.alpha ~= nil then
        return spec.alpha
    end

    return 1
end

local mat_images = {}
local mat_anims = {}
local mat_sheets = {}
local mat_variants = {}
local mat_autotile = {}
local mat_pick_opts = {}

-- bitmask N=8 E=4 S=2 W=1 → variant name
local MASK_TO_VARIANT = {
    [0] = "solo",
    [1] = "w",
    [2] = "s",
    [3] = "w_s",
    [4] = "e",
    [5] = "w_e",
    [6] = "e_s",
    [7] = "w_e_s",
    [8] = "n",
    [9] = "n_w",
    [10] = "n_s",
    [11] = "n_w_s",
    [12] = "n_e",
    [13] = "w_n_e",
    [14] = "n_e_s",
    [15] = "full",
}

local T
local snap_px = Tile.snap_px

local function terrain_sprite_scale(screen_px, block_px)
    screen_px = screen_px or 1
    block_px = block_px or 1
    local target_w = screen_px
    local s = target_w / block_px
    local drawn_w = math.floor(block_px * s + 0.5)

    if drawn_w < target_w then
        s = (target_w + 1) / block_px
    end

    return s
end

local function block_sprite_bottom_y(tile_cy, scale, tile_size, iso_y_ratio)
    local ts = tile_size * scale

    return tile_cy + Tile.hd_for_tile_span(ts, iso_y_ratio)
end

local function sync_tile_size()
    T = Setup.get().tile_size
end

local function load_block_sprite(path)
    if not love.filesystem.getInfo(path) then
        return nil
    end

    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")

    return image
end

local function variant_hash(tile_x, tile_y)
    return (tile_x * 73856093 + tile_y * 19349663) % 2147483647
end

local SIMPLEX_F2 = 0.5 * (math.sqrt(3.0) - 1.0)
local SIMPLEX_G2 = (3.0 - math.sqrt(3.0)) / 6.0

local SIMPLEX_GRAD2 = {
    { 1, 1 },
    { -1, 1 },
    { 1, -1 },
    { -1, -1 },
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
}

local function mat_seed(id)
    local h = 0

    for i = 1, #id do
        h = (h * 31 + id:byte(i)) % 2147483647
    end

    return h
end

local function build_simplex_perm(seed)
    local p = {}

    for i = 0, 255 do
        p[i] = i
    end

    local state = seed % 2147483647

    for i = 255, 1, -1 do
        state = (state * 1103515245 + 12345) % 2147483647
        local j = state % (i + 1)
        p[i], p[j] = p[j], p[i]
    end

    local perm = {}

    for i = 0, 511 do
        perm[i] = p[i % 256]
    end

    return perm
end

local function simplex_dot2(g, x, y)
    return g[1] * x + g[2] * y
end

local function simplex2(x, y, perm)
    local s = (x + y) * SIMPLEX_F2
    local i = math.floor(x + s)
    local j = math.floor(y + s)
    local t = (i + j) * SIMPLEX_G2
    local x0 = x - (i - t)
    local y0 = y - (j - t)
    local i1
    local j1

    if x0 > y0 then
        i1 = 1
        j1 = 0
    else
        i1 = 0
        j1 = 1
    end

    local x1 = x0 - i1 + SIMPLEX_G2
    local y1 = y0 - j1 + SIMPLEX_G2
    local x2 = x0 - 1 + 2 * SIMPLEX_G2
    local y2 = y0 - 1 + 2 * SIMPLEX_G2
    local ii = i % 256
    local jj = j % 256
    local gi0 = perm[ii + perm[jj]] % 8
    local gi1 = perm[ii + i1 + perm[jj + j1]] % 8
    local gi2 = perm[ii + 1 + perm[jj + 1]] % 8
    local n0 = 0
    local n1 = 0
    local n2 = 0
    local t0 = 0.5 - x0 * x0 - y0 * y0

    if t0 >= 0 then
        t0 = t0 * t0
        n0 = t0 * t0 * simplex_dot2(SIMPLEX_GRAD2[gi0 + 1], x0, y0)
    end

    local t1 = 0.5 - x1 * x1 - y1 * y1

    if t1 >= 0 then
        t1 = t1 * t1
        n1 = t1 * t1 * simplex_dot2(SIMPLEX_GRAD2[gi1 + 1], x1, y1)
    end

    local t2 = 0.5 - x2 * x2 - y2 * y2

    if t2 >= 0 then
        t2 = t2 * t2
        n2 = t2 * t2 * simplex_dot2(SIMPLEX_GRAD2[gi2 + 1], x2, y2)
    end

    return 70 * (n0 + n1 + n2)
end

local function load_mat_pick_opts(id, spec)
    local proximity = spec.proximity

    if type(proximity) ~= "number" or proximity <= 0 then
        mat_pick_opts[id] = nil
        return
    end

    local seed = mat_seed(id)

    mat_pick_opts[id] = {
        proximity = proximity,
        perm = build_simplex_perm(seed),
        seed_x = (seed % 997) * 0.013,
        seed_y = (math.floor(seed / 997) % 997) * 0.013,
        seed_z = (math.floor(seed / 994009) % 997) * 0.013,
    }
end

local function variant_roll(tile_x, tile_y, tile_z, total, opts)
    tile_z = tile_z or 0

    if total <= 0 then
        return 0
    end

    if not opts or not opts.perm then
        return variant_hash(tile_x, tile_y + tile_z * 48271) % total
    end

    local scale = opts.proximity or 1
    local v = simplex2(
        tile_x / scale + opts.seed_x,
        tile_y / scale + opts.seed_y,
        opts.perm
    )

    if tile_z ~= 0 then
        v = v * 0.5 + simplex2(
            tile_x / scale + opts.seed_x + 31.7,
            tile_z / scale + opts.seed_z,
            opts.perm
        ) * 0.5
    end

    v = v * 0.5 + 0.5

    if v < 0 then
        v = 0
    elseif v >= 1 then
        v = 1 - 1e-9
    end

    return math.floor(v * total)
end

local function pick_from_pool(pool, tile_x, tile_y, tile_z, opts)
    local roll = variant_roll(tile_x, tile_y, tile_z, pool.total, opts)

    for i = 1, #pool.images do
        roll = roll - pool.weights[i]

        if roll < 0 then
            return pool.images[i]
        end
    end

    return pool.images[#pool.images]
end

local function is_image(entry)
    return type(entry) == "userdata"
end

local function load_pool_item(item)
    if type(item) == "string" then
        return load_block_sprite(item), 1
    end

    if type(item) == "table" and item.path then
        local weight = item.weight

        if weight == nil then
            weight = 1
        end

        return load_block_sprite(item.path), weight
    end

    return nil, 0
end

local function load_variant_entry(entry)
    if type(entry) == "string" then
        return load_block_sprite(entry)
    end

    if type(entry) ~= "table" then
        return nil
    end

    if entry.path then
        local image = load_pool_item(entry)

        return image
    end

    local images = {}
    local weights = {}
    local total = 0
    local weighted = false

    for i = 1, #entry do
        local item = entry[i]
        local image, weight = load_pool_item(item)

        if image then
            if type(item) == "table" and item.path then
                weighted = true
            end

            if weight ~= 1 then
                weighted = true
            end

            images[#images + 1] = image
            weights[#weights + 1] = weight
            total = total + weight
        end
    end

    if #images == 0 then
        return nil
    end

    if #images == 1 then
        return images[1]
    end

    if not weighted then
        return images
    end

    return {
        images = images,
        weights = weights,
        total = total,
    }
end

local function pick_variant_image(entry, tile_x, tile_y, tile_z, opts)
    if not entry then
        return nil
    end

    if is_image(entry) then
        return entry
    end

    if entry.images and entry.total then
        return pick_from_pool(entry, tile_x, tile_y, tile_z, opts)
    end

    if entry[1] and is_image(entry[1]) then
        local n = #entry

        if n == 0 then
            return nil
        end

        if opts and opts.perm then
            return entry[variant_roll(tile_x, tile_y, tile_z, n, opts) + 1]
        end

        return entry[(tile_x + tile_y + (tile_z or 0)) % n + 1]
    end

    return entry
end

local function mat_image_at(id, tile_x, tile_y, tile_z)
    return pick_variant_image(mat_images[id], tile_x, tile_y, tile_z, mat_pick_opts[id])
end

local function grid_frames(grid, cols, row)
    row = row or 1

    if type(cols) == "number" then
        return grid(cols, row)
    end

    if type(cols) == "string" and not cols:find("-", 1, true) then
        return grid(tonumber(cols), row)
    end

    return grid(cols, row)
end

local STATIC_MODE = {
    default = { cols = "1", interval = 1, pause = true },
}

local function make_mat_clip(grid, def)
    local anim = anim8.newAnimation(
        grid_frames(grid, def.cols, def.row or 1),
        def.interval
    )

    if def.pause then
        anim:pauseAtStart()
    end

    return anim
end

local function load_mat_sheet(id, spec)
    local path = spec.path

    if not path or not love.filesystem.getInfo(path) then
        return
    end

    local image = love.graphics.newImage(path)
    local iw, ih = image:getWidth(), image:getHeight()
    local fw = spec.w
    local fh = spec.h

    image:setFilter("nearest", "nearest")

    local grid = anim8.newGrid(fw, fh, iw, ih)
    local modes = spec.modes or STATIC_MODE
    local templates = {}
    local mode_names = {}

    for mode, mode_def in pairs(modes) do
        mode_names[#mode_names + 1] = mode
        templates[mode] = make_mat_clip(grid, mode_def)
    end

    table.sort(mode_names)

    local default_mode = modes.default and "default" or mode_names[1]

    mat_sheets[id] = {
        image = image,
        w = fw,
        h = fh,
        default_mode = default_mode,
    }
    mat_anims[id] = templates[default_mode]
end

function Terrain.load()
    sync_tile_size()

    for id, spec in pairs(Setup.get().terrain_mats) do
        load_mat_pick_opts(id, spec)

        if spec.w and spec.h and not mat_sheets[id] then
            load_mat_sheet(id, spec)
        elseif spec.autotile and not mat_variants[id] then
            mat_autotile[id] = true
            mat_variants[id] = {}

            if spec.variants then
                for name, entry in pairs(spec.variants) do
                    mat_variants[id][name] = load_variant_entry(entry)
                end
            end

            if spec.path then
                mat_variants[id]._default = load_variant_entry(spec.path)
            end
        elseif spec.path and not mat_images[id] and not mat_anims[id] then
            mat_images[id] = load_variant_entry(spec.path)
        end
    end
end

function Terrain.update(dt)
    for _, anim in pairs(mat_anims) do
        anim:update(dt)
    end
end

local CHUNK_TILES = 25

local function fill_top_face_at(lg, cx, cy, screen_scale, r, g, b, a, size_mul)
    size_mul = size_mul or 1
    local s = T * (screen_scale or 1) * size_mul
    local hw = Tile.hw_for_tile_span(s, Setup.get().iso_x_ratio)
    local hd = Tile.hd_for_tile_span(s, Setup.get().iso_y_ratio)
    local eh = Tile.eh_for_tile_span(s, Setup.get().iso_eh_ratio)
    local yt = cy - eh

    cx = snap_px(cx)

    lg.setColor(r, g, b, a)
    lg.polygon(
        "fill",
        cx,
        snap_px(yt - hd),
        snap_px(cx + hw),
        yt,
        cx,
        snap_px(yt + hd),
        snap_px(cx - hw),
        yt
    )
end

local function fill_top_face(lg, layout, tile_x, tile_y, tile_z, r, g, b, a)
    local cx, cy = Tile.to_screen(layout, tile_x, tile_y, tile_z)

    fill_top_face_at(lg, cx, cy, layout.scale or 1, r, g, b, a, 1)
end

local function prism_color_for_mat(mat)
    local r, g, b = Terrain.mat_color(mat)

    if r then
        return { r, g, b }
    end

    return nil
end

local function apply_mat_spec(piece, mat_spec)
    if not mat_spec then
        return
    end

    if mat_spec.alpha ~= nil then
        piece.alpha = mat_spec.alpha
    end
end

function Terrain.initial_pieces(source, in_bounds)
    sync_tile_size()
    local tiles = {}

    for row, cells in ipairs(source.stacks) do
        local tile_y = row - 1

        for col, stack in ipairs(cells) do
            if stack ~= "." and stack ~= "" then
                local tile_x = col - 1

                if in_bounds(source, tile_x, tile_y) then
                    for z = 0, #stack - 1 do
                        local mat = Stack.layer_mat(
                            source,
                            row,
                            col,
                            z,
                            Setup.get().terrain_mats
                        )
                        local color = prism_color_for_mat(mat)
                        local piece = {
                            tile_x = tile_x,
                            tile_y = tile_y,
                            tile_z = z,
                            mat = mat,
                            map = true,
                        }
                        local mat_spec = Setup.get().terrain_mats[mat]

                        apply_mat_spec(piece, mat_spec)

                        if color then
                            piece.color = color
                        end

                        tiles[#tiles + 1] = piece
                    end
                end
            end
        end
    end

    return tiles
end

local function palette_from_rgb(rgb, alpha)
    local a = alpha or 1

    return {
        top = { rgb[1], rgb[2], rgb[3], a },
        left = {
            rgb[1] * 0.5,
            rgb[2] * 0.58,
            rgb[3] * 0.72,
            a,
        },
        right = {
            rgb[1] * 0.65,
            rgb[2] * 0.72,
            rgb[3] * 0.88,
            a,
        },
    }
end

local function top_mat_at(map, tile_x, tile_y)
    local source = map.source
    local height_cache = map.height_at_cache

    if not height_cache then
        return nil
    end

    local row = height_cache[tile_y]

    if not row then
        return nil
    end

    local h = row[tile_x]

    if not h or h <= 0 then
        return nil
    end

    return Stack.layer_mat(
        source,
        tile_y + 1,
        tile_x + 1,
        h - 1,
        Setup.get().terrain_mats
    )
end

local function top_z_at(map, tile_x, tile_y)
    local height_cache = map.height_at_cache

    if not height_cache then
        return nil
    end

    local row = height_cache[tile_y]

    if not row then
        return nil
    end

    local h = row[tile_x]

    if not h or h <= 0 then
        return nil
    end

    return h - 1
end

local function piece_is_stack_top(map, piece)
    local top_z = top_z_at(map, piece.tile_x, piece.tile_y)

    if top_z == nil then
        return false
    end

    return (piece.tile_z or 0) == top_z
end

local function mat_at_z(map, tile_x, tile_y, z)
    local source = map.source
    local height_cache = map.height_at_cache

    if not height_cache then
        return nil
    end

    local row = height_cache[tile_y]

    if not row then
        return nil
    end

    local h = row[tile_x]

    if not h or h <= 0 or z < 0 or z >= h then
        return nil
    end

    return Stack.layer_mat(
        source,
        tile_y + 1,
        tile_x + 1,
        z,
        Setup.get().terrain_mats
    )
end

local TRANSPARENT_NEIGHBOR_OFFS = {
    { 0, -1 },
    { 1, 0 },
    { 0, 1 },
    { -1, 0 },
    { 1, -1 },
    { 1, 1 },
    { -1, 1 },
    { -1, -1 },
}

local function mat_is_transparent(mat)
    return Terrain.mat_alpha(mat) < 1
end

local function piece_adjacent_to_transparent_mat(map, piece)
    local tx = piece.tile_x
    local ty = piece.tile_y
    local z = piece.tile_z or 0

    for _, off in ipairs(TRANSPARENT_NEIGHBOR_OFFS) do
        local nmat = mat_at_z(map, tx + off[1], ty + off[2], z)

        if nmat and mat_is_transparent(nmat) then
            return true
        end
    end

    return false
end

local function piece_adjacent_to_open_edge(map, piece)
    local tx = piece.tile_x
    local ty = piece.tile_y
    local z = piece.tile_z or 0

    for _, off in ipairs(TRANSPARENT_NEIGHBOR_OFFS) do
        if mat_at_z(map, tx + off[1], ty + off[2], z) == nil then
            return true
        end
    end

    return false
end

local function neighbor_same_mat_at_z(map, tile_x, tile_y, z, mat)
    local source = map.source
    local c = Setup.get()
    local lx = tile_x - c.grid_origin_x
    local ly = tile_y - c.grid_origin_y

    if lx < 0 or lx >= source.tiles_w or ly < 0 or ly >= source.tiles_d then
        return false
    end

    local nmat = mat_at_z(map, tile_x, tile_y, z)

    return nmat ~= nil and nmat == mat
end

local function autotile_mask(map, tile_x, tile_y, mat, z)
    local mask = 0

    if neighbor_same_mat_at_z(map, tile_x, tile_y - 1, z, mat) then
        mask = mask + 8
    end

    if neighbor_same_mat_at_z(map, tile_x + 1, tile_y, z, mat) then
        mask = mask + 4
    end

    if neighbor_same_mat_at_z(map, tile_x, tile_y + 1, z, mat) then
        mask = mask + 2
    end

    if neighbor_same_mat_at_z(map, tile_x - 1, tile_y, z, mat) then
        mask = mask + 1
    end

    return mask
end

local function mat_sprite(map, tile_x, tile_y, tile_z, top_z, mat)
    if not mat then
        return nil
    end

    if mat_autotile[mat] and tile_z == top_z then
        local variants = mat_variants[mat]

        if variants then
            local name = MASK_TO_VARIANT[autotile_mask(map, tile_x, tile_y, mat, tile_z)] or "solo"
            local image = pick_variant_image(
                variants[name] or variants._default,
                tile_x,
                tile_y,
                tile_z,
                mat_pick_opts[mat]
            )

            if image then
                return image, image:getWidth(), image:getHeight(), nil
            end
        end
    end

    if mat_sheets[mat] then
        local sheet = mat_sheets[mat]

        return sheet.image, sheet.w, sheet.h, mat_anims[mat]
    end

    local image = mat_image_at(mat, tile_x, tile_y, tile_z)

    if image then
        return image, image:getWidth(), image:getHeight(), nil
    end

    return nil
end

local function draw_block_sprite(lg, layout, image, src_w, src_h, tile_x, tile_y, tile_z, alpha, anim)
    local scale = layout.scale or 1
    local tile_px = layout.tile_size * scale
    local cx, cy = Tile.to_screen(layout, tile_x, tile_y, tile_z)
    local a = alpha or 1
    local fw = src_w or image:getWidth()
    local fh = src_h or image:getHeight()
    local s = terrain_sprite_scale(tile_px, fw)
    local draw_x = cx
    local draw_y = block_sprite_bottom_y(
        cy,
        scale,
        layout.tile_size,
        layout.iso_y_ratio
    )
    local ox = fw * 0.5
    local oy = fh

    lg.setColor(1, 1, 1, a)

    if anim then
        anim:draw(image, draw_x, draw_y, 0, s, s, ox, oy)
        return
    end

    lg.draw(
        image,
        draw_x,
        draw_y,
        0,
        s,
        s,
        ox,
        oy
    )
end

local function is_terrain_animating(map, tile_x, tile_y)
    for _, job in ipairs(map.pieces_updates or {}) do
        if job.tile_x == tile_x and job.tile_y == tile_y then
            return true
        end
    end

    for _, job in ipairs(map.pieces_removals or {}) do
        if not job.structure_id
            and job.tile_x == tile_x
            and job.tile_y == tile_y
        then
            return true
        end
    end

    return false
end

local function piece_bakeable(piece)
    return Terrain.is_terrain_block(piece)
        and piece.map
        and piece.bake ~= false
        and (piece.alpha or 1) >= 1
end

local function is_baked_terrain(piece)
    return Terrain.is_terrain_block(piece) and piece.baked == true
end

local function tile_chunk_index(tx, ty)
    return math.floor(tx / CHUNK_TILES), math.floor(ty / CHUNK_TILES)
end

local function chunk_tile_bounds(cx, cy, source)
    local min_tx = cx * CHUNK_TILES
    local min_ty = cy * CHUNK_TILES

    return min_tx,
        min_ty,
        math.min(min_tx + CHUNK_TILES - 1, source.tiles_w - 1),
        math.min(min_ty + CHUNK_TILES - 1, source.tiles_d - 1)
end

local function piece_screen_bounds(layout, map, piece, top_z)
    local scale = layout.scale or 1
    local tile_px = layout.tile_size * scale
    local tx, ty, tz = piece.tile_x, piece.tile_y, piece.tile_z or 0
    local cx, cy = Tile.to_screen(layout, tx, ty, tz)
    local image, src_w, src_h, anim = mat_sprite(map, tx, ty, tz, top_z, piece.mat)

    if image then
        local fw = src_w or image:getWidth()
        local fh = src_h or image:getHeight()
        local s = terrain_sprite_scale(tile_px, fw)
        local draw_y = block_sprite_bottom_y(
            cy,
            scale,
            layout.tile_size,
            layout.iso_y_ratio
        )
        local hw = fw * s * 0.5
        local hh = fh * s

        return cx - hw, draw_y - hh, cx + hw, draw_y
    end

    local s = T * scale
    local hw = Tile.hw_for_tile_span(s, layout.iso_x_ratio)
    local hd = Tile.hd_for_tile_span(s, layout.iso_y_ratio)
    local eh = Tile.eh_for_tile_span(s, layout.iso_eh_ratio)
    local yt = cy - eh

    return cx - hw, yt - hd, cx + hw, cy + hd
end

local function gather_chunk_pieces(map, cx, cy, tile_z)
    local min_tx, min_ty, max_tx, max_ty = chunk_tile_bounds(cx, cy, map.source)
    local pieces = {}

    for _, piece in ipairs(map.pieces or {}) do
        if is_baked_terrain(piece)
            and (piece.tile_z or 0) == tile_z
            and piece.tile_x >= min_tx
            and piece.tile_x <= max_tx
            and piece.tile_y >= min_ty
            and piece.tile_y <= max_ty
        then
            pieces[#pieces + 1] = piece
        end
    end

    return pieces, min_tx, min_ty, max_tx, max_ty
end

local function sort_terrain_entries(entries)
    table.sort(entries, function(a, b)
        if a.sum ~= b.sum then
            return a.sum < b.sum
        end

        if a.tx ~= b.tx then
            return a.tx < b.tx
        end

        return a.ty < b.ty
    end)
end

local function layer_pieces_in_chunk_layer(map, cx, cy, tile_z)
    local min_tx, min_ty, max_tx, max_ty = chunk_tile_bounds(cx, cy, map.source)
    local pieces = {}

    for _, piece in ipairs(map.pieces or {}) do
        if not piece._removed
            and Terrain.is_terrain_block(piece)
            and (piece.tile_z or 0) == tile_z
            and piece.tile_x >= min_tx
            and piece.tile_x <= max_tx
            and piece.tile_y >= min_ty
            and piece.tile_y <= max_ty
            and not is_terrain_animating(map, piece.tile_x, piece.tile_y)
        then
            pieces[#pieces + 1] = piece
        end
    end

    return pieces
end

local function apply_bake_flags_in_layer(map, cx, cy, tile_z)
    local pieces = layer_pieces_in_chunk_layer(map, cx, cy, tile_z)

    if #pieces == 0 then
        return
    end

    for i = 1, #pieces do
        local piece = pieces[i]

        piece.baked = piece_bakeable(piece)
            and not piece_is_stack_top(map, piece)
            and not piece_adjacent_to_transparent_mat(map, piece)
            and not piece_adjacent_to_open_edge(map, piece)
    end
end

local function bake_chunk(map, cx, cy, tile_z)
    local layout = map.layout
    local source = map.source
    local layer_pieces = layer_pieces_in_chunk_layer(map, cx, cy, tile_z)

    if #layer_pieces == 0 then
        return nil
    end

    local pieces, min_tx, min_ty, max_tx, max_ty = gather_chunk_pieces(
        map,
        cx,
        cy,
        tile_z
    )

    if #pieces == 0 then
        return nil
    end

    local cache = Tile.build_render_cache(map, {
        min_tx = min_tx,
        min_ty = min_ty,
        max_tx = max_tx,
        max_ty = max_ty,
    })
    local world_min_x, world_min_y = math.huge, math.huge
    local world_max_x, world_max_y = -math.huge, -math.huge

    for _, piece in ipairs(pieces) do
        local top_z = Tile.top_z_from_cache(source, cache, piece.tile_x, piece.tile_y)
        local x0, y0, x1, y1 = piece_screen_bounds(layout, map, piece, top_z)

        world_min_x = math.min(world_min_x, x0)
        world_min_y = math.min(world_min_y, y0)
        world_max_x = math.max(world_max_x, x1)
        world_max_y = math.max(world_max_y, y1)
    end

    local pad = layout.tile_size * (layout.scale or 1)
    local offset_x = world_min_x - pad
    local offset_y = world_min_y - pad
    local canvas_w = math.ceil(world_max_x - world_min_x + pad * 2)
    local canvas_h = math.ceil(world_max_y - world_min_y + pad * 2)
    local canvas = love.graphics.newCanvas(canvas_w, canvas_h)

    canvas:setFilter("nearest", "nearest")

    local entries = {}

    for _, piece in ipairs(pieces) do
        local tx, ty = piece.tile_x, piece.tile_y
        local tz = piece.tile_z or 0

        entries[#entries + 1] = {
            piece = piece,
            sum = tx + ty + tz,
            tx = tx,
            ty = ty,
        }
    end

    sort_terrain_entries(entries)

    love.graphics.push()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.translate(-offset_x, -offset_y)

    for _, entry in ipairs(entries) do
        local piece = entry.piece
        local tx, ty = piece.tile_x, piece.tile_y
        local tz = piece.tile_z or 0

        Terrain.draw_unit_cube(
            love.graphics,
            layout,
            cache,
            map,
            tx,
            ty,
            tz,
            piece.color,
            1,
            Tile.top_z_from_cache(source, cache, tx, ty),
            piece.mat
        )
    end

    love.graphics.setCanvas()
    love.graphics.pop()

    return {
        canvas = canvas,
        x = offset_x,
        y = offset_y,
        min_tx = min_tx,
        min_ty = min_ty,
        max_tx = max_tx,
        max_ty = max_ty,
        cx = cx,
        cy = cy,
        tile_z = tile_z,
    }
end

local function find_chunk_slot(map, cx, cy, tile_z)
    for i, chunk in ipairs(map.terrain_chunks or {}) do
        if chunk.cx == cx and chunk.cy == cy and chunk.tile_z == tile_z then
            return i
        end
    end
end

local function rebake_layer_chunk(map, cx, cy, tile_z)
    map.terrain_chunks = map.terrain_chunks or {}
    local idx = find_chunk_slot(map, cx, cy, tile_z)
    local old = idx and map.terrain_chunks[idx]

    if old and old.canvas then
        old.canvas:release()
    end

    apply_bake_flags_in_layer(map, cx, cy, tile_z)

    local chunk = bake_chunk(map, cx, cy, tile_z)

    if chunk and idx then
        map.terrain_chunks[idx] = chunk
    elseif chunk then
        map.terrain_chunks[#map.terrain_chunks + 1] = chunk
    elseif idx then
        table.remove(map.terrain_chunks, idx)
    end
end

local function bump_bake_max_z(map, tile_x, tile_y)
    local h = map.grid.height_at(tile_x, tile_y)
    local top_z = h > 0 and h - 1 or 0

    map.terrain_bake_max_z = math.max(map.terrain_bake_max_z or 0, top_z)
end

local function process_dirty_chunks(map)
    local dirty = map.terrain_dirty_chunks
    local floor_max_z = map.min_visible_z or 0

    if not dirty then
        return
    end

    for key, entry in pairs(dirty) do
        if entry.tile_z <= floor_max_z then
            rebake_layer_chunk(map, entry.cx, entry.cy, entry.tile_z)
            dirty[key] = nil
        end
    end
end

function Terrain.recompute_min_visible_z(map)
    local height_cache = map.height_at_cache

    if not height_cache then
        map.min_visible_z = 0
        return
    end

    local min_z

    for _, cache_row in pairs(height_cache) do
        for _, h in pairs(cache_row) do
            if h and h > 0 then
                local top_z = h - 1

                if min_z == nil or top_z < min_z then
                    min_z = top_z
                end
            end
        end
    end

    map.min_visible_z = min_z or 0
end

local function clear_upper_baked_flags(map)
    local floor_max_z = map.min_visible_z or 0

    for _, piece in ipairs(map.pieces or {}) do
        if Terrain.is_terrain_block(piece) and (piece.tile_z or 0) > floor_max_z then
            piece.baked = false
        end
    end
end

local function bake_floor_chunks(map)
    local source = map.source
    local floor_max_z = map.min_visible_z or 0
    local ncx = math.ceil(source.tiles_w / CHUNK_TILES)
    local ncy = math.ceil(source.tiles_d / CHUNK_TILES)

    for tile_z = 0, floor_max_z do
        for cy = 0, ncy - 1 do
            for cx = 0, ncx - 1 do
                apply_bake_flags_in_layer(map, cx, cy, tile_z)

                local chunk = bake_chunk(map, cx, cy, tile_z)

                if chunk then
                    map.terrain_chunks[#map.terrain_chunks + 1] = chunk
                end
            end
        end
    end
end

function Terrain.build_bake(map)
    sync_tile_size()

    local max_z = 0

    for _, piece in ipairs(map.pieces or {}) do
        if Terrain.is_terrain_block(piece) then
            max_z = math.max(max_z, piece.tile_z or 0)
        end
    end

    map.terrain_bake_max_z = max_z
    Terrain.recompute_min_visible_z(map)

    map.terrain_chunks = {}
    map.terrain_dirty_chunks = {}

    clear_upper_baked_flags(map)
    bake_floor_chunks(map)
end

function Terrain.rebuild_floor_chunks(map)
    sync_tile_size()
    Terrain.recompute_min_visible_z(map)

    local floor_max_z = map.min_visible_z or 0
    local kept = {}

    for _, chunk in ipairs(map.terrain_chunks or {}) do
        if chunk.tile_z > floor_max_z then
            if chunk.canvas then
                chunk.canvas:release()
            end
        else
            kept[#kept + 1] = chunk
        end
    end

    map.terrain_chunks = kept
    clear_upper_baked_flags(map)

    local source = map.source
    local ncx = math.ceil(source.tiles_w / CHUNK_TILES)
    local ncy = math.ceil(source.tiles_d / CHUNK_TILES)

    for tile_z = 0, floor_max_z do
        for cy = 0, ncy - 1 do
            for cx = 0, ncx - 1 do
                rebake_layer_chunk(map, cx, cy, tile_z)
            end
        end
    end
end

local function mark_layer_dirty(map, tile_x, tile_y, tile_z)
    local floor_max_z = map.min_visible_z or 0

    if tile_z > floor_max_z then
        return
    end

    local cx, cy = tile_chunk_index(tile_x, tile_y)

    map.terrain_dirty_chunks = map.terrain_dirty_chunks or {}
    map.terrain_dirty_chunks[cx .. "," .. cy .. "," .. tile_z] = {
        cx = cx,
        cy = cy,
        tile_z = tile_z,
    }
end

function Terrain.mark_tile_dirty(map, tile_x, tile_y, tile_z)
    if tile_z ~= nil then
        mark_layer_dirty(map, tile_x, tile_y, tile_z)
        return
    end

    local floor_max_z = map.min_visible_z or 0

    for z = 0, floor_max_z do
        mark_layer_dirty(map, tile_x, tile_y, z)
    end
end

function Terrain.mark_piece_dynamic(map, piece)
    if not piece then
        return
    end

    piece.bake = false

    local floor_max_z = map.min_visible_z or 0
    local tile_z = piece.tile_z or 0
    local cx, cy = tile_chunk_index(piece.tile_x, piece.tile_y)

    if tile_z <= floor_max_z then
        rebake_layer_chunk(map, cx, cy, tile_z)
    end
end

function Terrain.finish_piece_bake(map, piece)
    if not piece then
        return
    end

    piece.bake = nil

    local floor_max_z = map.min_visible_z or 0
    local tile_z = piece.tile_z or 0

    if tile_z > floor_max_z then
        return
    end

    local cx, cy = tile_chunk_index(piece.tile_x, piece.tile_y)
    rebake_layer_chunk(map, cx, cy, tile_z)

    local dirty = map.terrain_dirty_chunks

    if dirty then
        dirty[cx .. "," .. cy .. "," .. tile_z] = nil
    end
end

local REBAKE_NEIGHBOR_OFFS = {
    { 0, 0 },
    { 0, -1 },
    { 1, 0 },
    { 0, 1 },
    { -1, 0 },
    { 1, -1 },
    { 1, 1 },
    { -1, 1 },
    { -1, -1 },
}

function Terrain.rebake_tile_now(map, tile_x, tile_y)
    local floor_max_z = map.min_visible_z or 0
    local dirty = {}

    for _, off in ipairs(REBAKE_NEIGHBOR_OFFS) do
        local tx = tile_x + off[1]
        local ty = tile_y + off[2]

        if is_terrain_animating(map, tx, ty) then
            return
        end

        bump_bake_max_z(map, tx, ty)

        local cx, cy = tile_chunk_index(tx, ty)

        for tile_z = 0, floor_max_z do
            dirty[cx .. "," .. cy .. "," .. tile_z] = { cx = cx, cy = cy, tile_z = tile_z }
        end
    end

    for _, entry in pairs(dirty) do
        rebake_layer_chunk(map, entry.cx, entry.cy, entry.tile_z)
    end
end

function Terrain.draw_unit_cube(lg, layout, _cache, map, tile_x, tile_y, tile_z, rgb, alpha, top_z, mat)
    local image, src_w, src_h, anim = mat_sprite(map, tile_x, tile_y, tile_z, top_z, mat)

    if image then
        draw_block_sprite(
            lg,
            layout,
            image,
            src_w,
            src_h,
            tile_x,
            tile_y,
            tile_z,
            alpha,
            anim
        )
        return
    end

    if not rgb then
        return
    end

    local scale = layout.scale or 1
    local cx, cy = Tile.to_screen(layout, tile_x, tile_y, tile_z)
    local s = T * scale
    local hw = Tile.hw_for_tile_span(s, layout.iso_x_ratio)
    local hd = Tile.hd_for_tile_span(s, layout.iso_y_ratio)
    local eh = Tile.eh_for_tile_span(s, layout.iso_eh_ratio)
    local colors = palette_from_rgb(rgb, alpha)
    local yt = cy - eh

    lg.setColor(colors.left)
    lg.polygon(
        "fill",
        cx - hw,
        cy,
        cx,
        cy + hd,
        cx,
        yt + hd,
        cx - hw,
        yt
    )

    lg.setColor(colors.right)
    lg.polygon(
        "fill",
        cx + hw,
        cy,
        cx,
        cy + hd,
        cx,
        yt + hd,
        cx + hw,
        yt
    )

    fill_top_face(
        lg,
        layout,
        tile_x,
        tile_y,
        tile_z,
        colors.top[1],
        colors.top[2],
        colors.top[3],
        colors.top[4]
    )
end

function Terrain.draw(map)
    sync_tile_size()
    process_dirty_chunks(map)

    local floor_max_z = map.min_visible_z or 0

    for tile_z = 0, floor_max_z do
        love.graphics.setColor(1, 1, 1, 1)
        for _, chunk in ipairs(map.terrain_chunks or {}) do
            if chunk.tile_z == tile_z then
                love.graphics.draw(chunk.canvas, chunk.x, chunk.y)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Terrain
