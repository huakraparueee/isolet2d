local anim8 = require("anim8")
local Setup = require("setup")
local Path = require("path")
local Placement = require("placement")
local Tile = require("tile")

local WALK_SPEED = 3
local FACING_AXIS_EPS = 0.001
local DIR8_VEC = {
    e = { 1, 0 },
    se = { 1, 1 },
    s = { 0, 1 },
    sw = { -1, 1 },
    w = { -1, 0 },
    nw = { -1, -1 },
    n = { 0, -1 },
    ne = { 1, -1 },
}
local T

local function arrive_dist()
    return Placement.pos_step() * 0.5
end

-- Scale px/py speed so screen travel matches ±x segments (e/w) for the same walkspeed.
local function walk_speed_for_segment(map, walkspeed, seg_dx, seg_dy)
    local seg_len = math.sqrt(seg_dx * seg_dx + seg_dy * seg_dy)

    if seg_len <= 0.0001 then
        return walkspeed
    end

    local layout = map and map.layout

    if not layout then
        return walkspeed * (seg_len / Placement.pos_step())
    end

    local ux = seg_dx / seg_len
    local uy = seg_dy / seg_len
    local iso_x = layout.iso_x
    local iso_y = layout.iso_y
    local ref = math.sqrt(iso_x * iso_x + iso_y * iso_y)
    local rate = math.sqrt(
        (ux - uy) * (ux - uy) * iso_x * iso_x
            + (ux + uy) * (ux + uy) * iso_y * iso_y
    )

    if rate <= 0.0001 then
        return walkspeed
    end

    return walkspeed * (ref / rate)
end

local catalogs = {}
local set_mode

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

local function make_clip(grid, def)
    local anim = anim8.newAnimation(
        grid_frames(grid, def.cols, def.row or 1),
        def.interval
    )

    if def.pause then
        anim:pauseAtStart()
    end

    return anim
end

local function apply_flip(anim, flip)
    if not flip then
        return anim
    end

    if flip == "h" then
        anim:flipH()
    elseif flip == "v" then
        anim:flipV()
    elseif flip == "hv" or flip == "vh" then
        anim:flipH()
        anim:flipV()
    else
        error("dir flip must be 'h', 'v', or 'hv'")
    end

    return anim
end

local function load_sheet(spec)
    local path = spec.path
    local image = love.graphics.newImage(path)
    local iw, ih = image:getWidth(), image:getHeight()

    if spec.sheet_w and spec.sheet_h then
        if iw ~= spec.sheet_w or ih ~= spec.sheet_h then
            error(
                string.format(
                    "%s must be %dx%d, got %dx%d",
                    path,
                    spec.sheet_w,
                    spec.sheet_h,
                    iw,
                    ih
                )
            )
        end
    end

    image:setFilter("nearest", "nearest")

    local grid = anim8.newGrid(spec.w, spec.h, iw, ih)
    local templates = {}
    local mode_names = {}
    local dir_modes = {}

    for mode, def in pairs(spec.modes) do
        mode_names[#mode_names + 1] = mode
        if def.dirs then
            dir_modes[mode] = {}

            for dir_name, dir_def in pairs(def.dirs) do
                if not DIR8_VEC[dir_name] then
                    error(
                        "unknown walk dir '"
                            .. tostring(dir_name)
                            .. "' (use e, se, s, sw, w, nw, n, ne)"
                    )
                end

                local clip_def = {
                    cols = dir_def.cols or def.cols,
                    row = dir_def.row or 1,
                    interval = dir_def.interval or def.interval,
                    pause = def.pause,
                    loop = def.loop,
                }

                local clip = make_clip(grid, clip_def)

                apply_flip(clip, dir_def.flip)
                templates[mode .. "_" .. dir_name] = clip
                dir_modes[mode][dir_name] = true
            end
        else
            local right = make_clip(grid, def)

            templates[mode .. "_right"] = right
            templates[mode .. "_left"] = right:clone():flipH()
        end
    end

    table.sort(mode_names)

    return {
        image = image,
        w = spec.w,
        h = spec.h,
        modes = spec.modes,
        mode_names = mode_names,
        templates = templates,
        dir_modes = dir_modes,
    }
end

local function clip_key(mode, clip_side)
    return mode .. "_" .. clip_side
end

-- Unflipped sheet frames live under *_right; *_left is flipH. clip_side picks which to show.
local function clip_facing(sprite_faces, facing)
    if sprite_faces == facing then
        return "right"
    end

    return "left"
end

local function facing_lr_for_step(dx, dy)
    if dx == 0 and dy == 0 then
        return nil
    end

    local screen_x = dx - dy

    if math.abs(screen_x) <= FACING_AXIS_EPS then
        if dy > 0 then
            return "left"
        end

        if dy < 0 then
            return "right"
        end

        if dx > 0 then
            return "right"
        end

        if dx < 0 then
            return "left"
        end

        return nil
    end

    if screen_x < 0 then
        return "left"
    end

    return "right"
end

local function facing8_for_step(dx, dy)
    if dx == 0 and dy == 0 then
        return nil
    end

    -- 💡 หมายเหตุ: หากเกมของคุณใช้มุมมอง Isometric แบบ 2.5D และทิศทางยังเพี้ยนอยู่ 
    -- ให้เปิดใช้งาน 3 บรรทัดด้านล่างนี้เพื่อแปลงเวกเตอร์เป็น Screen Space ก่อนคำนวณครับ
    --[[
    local isox = dx - dy
    local isoy = (dx + dy) * 0.5
    dx, dy = isox, isoy
    --]]

    for dir_name, vec in pairs(DIR8_VEC) do
        if dx * vec[2] == dy * vec[1]
            and (dx == 0 or (dx > 0) == (vec[1] > 0))
            and (dy == 0 or (dy > 0) == (vec[2] > 0))
        then
            return dir_name
        end
    end

    if math.abs(dx) >= math.abs(dy) then
        if dx > 0 then
            return dy >= 0 and "se" or "ne"
        end

        return dy >= 0 and "sw" or "nw"
    end

    if dy > 0 then
        return dx >= 0 and "se" or "sw"
    end

    return dx >= 0 and "ne" or "nw"
end

local function facing_lr_for_facing(facing)
    if facing == "left" or facing == "right" then
        return facing
    end

    local vec = DIR8_VEC[facing]

    if vec then
        return facing_lr_for_step(vec[1], vec[2])
    end

    return "right"
end

local function clip_side_for_state(state)
    local mode = state.mode

    if state.catalog.dir_modes and state.catalog.dir_modes[mode] then
        return state.facing
    end

    return clip_facing(state.sprite_faces, facing_lr_for_facing(state.facing))
end

local function mode_def(catalog, mode)
    return catalog.modes and catalog.modes[mode]
end

local function resolve_playback(def, play_opts)
    play_opts = play_opts or {}

    if def and def.pause then
        return { pause = true }
    end

    local loop = play_opts.loop

    if loop == nil then
        loop = def and def.loop
    end

    if loop == nil then
        loop = true
    end

    local count = play_opts.count

    if count == nil then
        count = def and def.count
    end

    local after_mode = play_opts.after_mode or (def and def.after_mode) or "stand"

    if not loop and count == nil then
        count = 1
    end

    return {
        loop = loop,
        count = count,
        after_mode = after_mode,
    }
end

local function finish_mode_play(state)
    state.mode_busy = false
    state.mode_left = nil

    if state.path then
        return
    end

    local next_mode = state.after_mode or "stand"

    state.after_mode = nil
    state.play_opts = nil
    set_mode(state, next_mode)
end

local function configure_playback(state, anim, playback)
    if playback.pause then
        anim:gotoFrame(1)
        anim:pause()
        state.mode_busy = false
        state.mode_left = nil
        return
    end

    state.after_mode = playback.after_mode

    if playback.loop then
        anim.onLoop = function()
        end
        anim:gotoFrame(1)
        anim.timer = 0
        anim:resume()
        state.mode_busy = false
        state.mode_left = nil
        return
    end

    state.mode_left = playback.count
    state.mode_busy = true

    anim.onLoop = function(a, loops)
        if state.mode_left == nil then
            return
        end

        state.mode_left = state.mode_left - loops

        if state.mode_left <= 0 then
            a:pauseAtEnd()
            finish_mode_play(state)
        end
    end

    anim:gotoFrame(1)
    anim.timer = 0
    anim:resume()
end

local function apply_state(state)
    local key = clip_key(state.mode, clip_side_for_state(state))
    local template = state.catalog.templates[key]

    if not template then
        error(
            "unknown npc clip: "
                .. tostring(key)
                .. " (mode "
                .. tostring(state.mode)
                .. ", facing "
                .. tostring(state.facing)
                .. ")"
        )
    end

    local anim = template:clone()
    state.anims[key] = anim
    state.current = anim

    local def = mode_def(state.catalog, state.mode)
    local playback = resolve_playback(def, state.play_opts)

    state.play_opts = nil
    configure_playback(state, anim, playback)
end

local function clear_walk(state)
    state.path = nil
    state.path_i = nil
    state.final_z = nil
    state.seg_x0 = nil
    state.seg_y0 = nil
    state.seg_z0 = nil
end

local function begin_path_segment(state, piece, map, wp)
    state.seg_x0 = piece.pos_x
    state.seg_y0 = piece.pos_y
    state.seg_z0 = piece.tile_z

    if state.seg_z0 == nil and wp then
        state.seg_z0 = wp.z
        piece.tile_z = state.seg_z0
    end
end

set_mode = function(state, mode, play_opts)
    if state.mode == mode and play_opts == nil and not state.mode_busy then
        return
    end

    state.mode = mode
    state.play_opts = play_opts
    apply_state(state)
end

local function finish_walk(state, piece, map)
    if state.final_z ~= nil then
        piece.tile_z = state.final_z
    end

    clear_walk(state)
    set_mode(state, "stand")
end

local function npc_spec(kind)
    if not kind then
        return nil
    end

    return Setup.get().npcs[kind]
end

local function ensure_catalog(kind)
    if catalogs[kind] then
        return catalogs[kind]
    end

    local def = npc_spec(kind)

    if not def then
        error("unknown npc kind: " .. tostring(kind))
    end

    catalogs[kind] = load_sheet(def)

    return catalogs[kind]
end

local function npc_def(kind)
    return npc_spec(kind) or {}
end

local function spawn(opts)
    opts = opts or {}

    local kind = opts.kind or "r"
    local catalog = ensure_catalog(kind)
    local def = npc_def(kind)

    local sprite_faces = def.sprite_faces or "right"
    local facing = opts.facing or def.facing or sprite_faces
    local mode = opts.mode or "stand"

    if sprite_faces ~= "left" and sprite_faces ~= "right" then
        error("npc sprite_faces must be 'left' or 'right'")
    end

    if facing ~= "left" and facing ~= "right" and not DIR8_VEC[facing] then
        error(
            "npc facing must be 'left', 'right', or e/se/s/sw/w/nw/n/ne"
        )
    end

    if not catalog.modes[mode] then
        error(
            "unknown npc mode: "
                .. tostring(mode)
                .. " (kind "
                .. kind
                .. ")"
        )
    end

    local anims = {}

    for key, template in pairs(catalog.templates) do
        anims[key] = template:clone()
    end

    local state = {
        kind = kind,
        catalog = catalog,
        sprite_faces = sprite_faces,
        facing = facing,
        mode = mode,
        walkspeed = opts.walkspeed or def.walkspeed or WALK_SPEED,
        anims = anims,
        current = nil,
        mode_busy = false,
        play_opts = opts.play,
    }

    apply_state(state)

    return state
end

local function set_facing(state, facing)
    if state.facing == facing then
        return
    end

    state.facing = facing

    if state.path and state.mode == "walk" and not state.mode_busy then
        local key = clip_key(state.mode, clip_side_for_state(state))
        local anim = state.anims[key]

        if anim and state.current then
            anim.timer = state.current.timer
            anim.position = state.current.position
            anim.status = state.current.status

            if anim.status ~= "playing" then
                anim:resume()
            end

            state.current = anim
            return
        end
    end

    apply_state(state)
end

local function facing_for_step(dx, dy, state)
    if state and state.catalog.dir_modes and state.catalog.dir_modes.walk then
        return facing8_for_step(dx, dy)
    end

    return facing_lr_for_step(dx, dy)
end

-- 🛠 แก้ไข: เปลี่ยนให้รับค่าเวกเตอร์ dx, dy ของทิศทางการเคลื่อนที่โดยตรง
local function apply_segment_facing(state, dx, dy)
    if not dx or not dy then
        return
    end

    local facing = facing_for_step(dx, dy, state)

    if facing then
        set_facing(state, facing)
    end
end

local function is_walking(state)
    return state.path ~= nil
end

local function walk_state_to_pos(state, piece, map, goal_x, goal_y, tile_z)
    state.mode_busy = false
    state.mode_left = nil
    state.after_mode = nil
    clear_walk(state)

    local w = piece.tiles_w or 1
    local d = piece.tiles_d or 1
    local goal_node = Placement.node_at_pos(map, goal_x, goal_y)

    if goal_node then
        goal_x = goal_node.px
        goal_y = goal_node.py
    end

    local path = Path.find_path_pos(map, piece.pos_x, piece.pos_y, goal_x, goal_y)

    if path == nil then
        set_mode(state, "stand")
        return false
    end

    local goal_tx = math.floor(goal_x - w * 0.5 + 0.0001)
    local goal_ty = math.floor(goal_y - d * 0.5 + 0.0001)
    goal_node = goal_node or Placement.node_at_pos(map, goal_x, goal_y)

    state.final_z = tile_z ~= nil and tile_z or (
        goal_node and goal_node.z or Path.surface_z(map, goal_tx, goal_ty)
    )

    if #path == 0 then
        if goal_node then
            goal_x = goal_node.px
            goal_y = goal_node.py
        end

        piece.pos_x = goal_x
        piece.pos_y = goal_y
        piece.tile_z = state.final_z
        finish_walk(state, piece, map)
        return true
    end

    if goal_node then
        path[#path].x = goal_node.px
        path[#path].y = goal_node.py
        path[#path].z = state.final_z
    end

    state.path = path
    state.path_i = 1
    begin_path_segment(state, piece, map, path[1])
    set_mode(state, "walk")
    
    -- 🛠 แก้ไข: คำนวณทิศทางเริ่มต้นจากตำแหน่งปัจจุบันของตัวละครไปยัง Waypoint แรก
    apply_segment_facing(state, path[1].x - piece.pos_x, path[1].y - piece.pos_y)
    return true
end

local function update_state(state, piece, map, dt)
    state.current:update(dt)

    if not state.path then
        return
    end

    local wp = state.path[state.path_i]

    if not wp then
        finish_walk(state, piece, map)
        return
    end

    local px = piece.pos_x
    local py = piece.pos_y
    local dx = wp.x - px
    local dy = wp.y - py
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist <= arrive_dist() then
        piece.pos_x = wp.x
        piece.pos_y = wp.y
        piece.tile_z = wp.z

        if state.path_i >= #state.path then
            finish_walk(state, piece, map)
            return
        end

        state.path_i = state.path_i + 1
        local next_wp = state.path[state.path_i]

        if next_wp then
            begin_path_segment(state, piece, map, next_wp)
            apply_segment_facing(state, next_wp.x - wp.x, next_wp.y - wp.y)
        end

        return
    end

    local seg_dx = wp.x - state.seg_x0
    local seg_dy = wp.y - state.seg_y0
    local seg_len = math.sqrt(seg_dx * seg_dx + seg_dy * seg_dy)
    local speed = walk_speed_for_segment(map, state.walkspeed, seg_dx, seg_dy)
    local step = math.min(dist, speed * dt)
    piece.pos_x = px + (dx / dist) * step
    piece.pos_y = py + (dy / dist) * step
    local moved_x = piece.pos_x - state.seg_x0
    local moved_y = piece.pos_y - state.seg_y0
    local moved = math.sqrt(moved_x * moved_x + moved_y * moved_y)
    local t = 0

    if seg_len > 0.0001 then
        t = moved / seg_len
    end

    piece.tile_z = state.seg_z0 + (wp.z - state.seg_z0) * t
end

local function want_id(npc_id, filter)
    if not filter then
        return true
    end

    if type(filter) == "string" then
        return npc_id == filter
    end

    for _, id in ipairs(filter) do
        if npc_id == id then
            return true
        end
    end

    return false
end

local Npc = {}

function Npc.find_by_id(map, id)
    if not map.pieces or not id then
        return nil
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc_id == id then
            return piece
        end
    end

    return nil
end

function Npc.apply_facing(piece, facing)
    if piece.npc and facing then
        set_facing(piece.npc, facing)
    end
end

function Npc.facing_for_delta(dx, dy, state)
    return facing_for_step(dx, dy, state)
end

function Npc.clear_piece_walk(piece)
    if piece.npc then
        clear_walk(piece.npc)
    end
end

function Npc.def(kind)
    return npc_spec(kind)
end

function Npc.footprint(kind, overrides)
    local def = npc_spec(kind) or {}
    overrides = overrides or {}

    return overrides.tiles_w or def.tiles_w or 1,
        overrides.tiles_d or def.tiles_d or 1,
        overrides.tiles_h or def.tiles_h or 1
end

function Npc.tile_span(kind)
    return Npc.footprint(kind, nil)
end

function Npc.draw_offset(kind, overrides)
    local def = npc_spec(kind) or {}
    overrides = overrides or {}

    local ox = overrides.draw_offset_x

    if ox == nil then
        ox = def.draw_offset_x or 0
    end

    local oy = overrides.draw_offset_y

    if oy == nil then
        oy = def.draw_offset_y or 0
    end

    return ox, oy
end

function Npc.catalog()
    return Setup.get().npcs or {}
end

function Npc.preload_npcs()
    T = Setup.get().tile_size

    for kind, _ in pairs(Npc.catalog()) do
        ensure_catalog(kind)
    end
end

function Npc.load()
    T = Setup.get().tile_size
    Npc.preload_npcs()
end

function Npc.sync_footprint(map, piece, kind, overrides)
    local w, d, h = Npc.footprint(kind, overrides)
    local draw_ox, draw_oy = Npc.draw_offset(kind, overrides)

    piece.tiles_w = w
    piece.tiles_d = d
    piece.tiles_h = h
    piece.draw_offset_x = draw_ox
    piece.draw_offset_y = draw_oy
end

function Npc.sync_footprint_from_kind(map, piece, kind)
    Npc.sync_footprint(map, piece, kind, nil)
end

function Npc.change_kind(map, piece, kind, opts)
    if not piece.npc then
        return false
    end

    opts = opts or {}
    local facing = opts.facing or piece.npc.facing
    local mode = opts.mode or piece.npc.mode

    Npc.clear_piece_walk(piece)
    Npc.sync_footprint_from_kind(map, piece, kind)

    piece.npc = spawn({
        kind = kind,
        facing = facing,
        mode = mode,
        play = opts.play,
    })

    return true
end

function Npc.add(map, piece, ev)
    Npc.sync_footprint(map, piece, ev.kind, ev)

    piece.npc = spawn({
        kind = ev.kind,
        facing = ev.facing,
        mode = ev.mode,
        play = {
            loop = ev.loop,
            count = ev.count,
            after_mode = ev.after_mode,
        },
    })

    -- pipeline step 5: npc feet on placement node
    if not Placement.spawn_at(map, piece, ev.tile_x, ev.tile_y) then
        error(
            "npc.add: no placement node at "
                .. tostring(ev.tile_x)
                .. ","
                .. tostring(ev.tile_y)
        )
    end
end

function Npc.set_mode(map, mode, id_filter, play_opts)
    if not map.pieces then
        return
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc and want_id(piece.npc_id, id_filter) then
            set_mode(piece.npc, mode, play_opts)
        end
    end
end

function Npc.walk_to(map, tile_x, tile_y, id_filter, tile_z)
    if not map.pieces then
        return
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc
            and want_id(piece.npc_id, id_filter)
        then
            local w = piece.tiles_w or 1
            local d = piece.tiles_d or 1
            local node = Placement.node_for_footprint(map, tile_x, tile_y, w, d)

            if node then
                walk_state_to_pos(
                    piece.npc,
                    piece,
                    map,
                    node.px,
                    node.py,
                    tile_z or node.z
                )
            end
        end
    end
end

function Npc.walk_to_pos(map, pos_x, pos_y, id_filter, tile_z)
    if not map.pieces then
        return
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc
            and want_id(piece.npc_id, id_filter)
        then
            walk_state_to_pos(piece.npc, piece, map, pos_x, pos_y, tile_z)
        end
    end
end

function Npc.is_anim_busy(map, id_filter)
    if not map.pieces then
        return false
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc
            and want_id(piece.npc_id, id_filter)
            and piece.npc.mode_busy
        then
            return true
        end
    end

    return false
end

function Npc.is_busy(map)
    if not map.pieces then
        return false
    end

    for _, piece in ipairs(map.pieces) do
        if piece.npc then
            if is_walking(piece.npc) or piece.npc.mode_busy then
                return true
            end
        end
    end

    return false
end

function Npc.update(map, dt)
    for _, piece in ipairs(map.npc_pieces or {}) do
        if piece.npc then
            update_state(piece.npc, piece, map, dt)
        end
    end
end

function Npc.npc_tile_span(piece)
    local kind = piece.npc and piece.npc.kind

    if not kind then
        return 1, 1, 1
    end

    local dw, dd, dh = Npc.tile_span(kind)

    return piece.tiles_w or dw, piece.tiles_d or dd, piece.tiles_h or dh
end

function Npc.draw(piece, lg, layout, alpha, z_at)
    if not piece.npc then
        return false
    end

    local catalog = piece.npc.catalog

    if not catalog then
        return false
    end

    local scale = layout.scale or 1
    alpha = alpha or 1
    local feet_x, feet_y

    if piece.pos_x ~= nil and piece.pos_y ~= nil then
        feet_x, feet_y = Tile.placement_to_screen(
            layout,
            piece.pos_x,
            piece.pos_y,
            piece.tile_z
        )
    else
        local w, d = Npc.npc_tile_span(piece)
        feet_x, feet_y =
            Tile.feet_screen_from_piece(layout, piece, w, d, z_at)
    end

    local draw_ox = piece.draw_offset_x or 0
    local draw_oy = piece.draw_offset_y or 0

    lg.setColor(1, 1, 1, alpha)
    piece.npc.current:draw(
        catalog.image,
        Tile.snap_px(feet_x + draw_ox),
        Tile.snap_px(feet_y + draw_oy),
        0,
        scale,
        scale,
        catalog.w * 0.5,
        catalog.h
    )

    return true
end

function Npc.compact_removed(map)
    local kept = {}

    for _, piece in ipairs(map.pieces or {}) do
        if not piece._removed then
            kept[#kept + 1] = piece
        end
    end

    map.pieces = kept
    map.sync_npc_pieces()
end

function Npc.remove(map, id_filter, opts)
    opts = opts or {}

    if not map.pieces then
        return
    end

    local duration = opts.duration
    local faded = false

    for _, piece in ipairs(map.pieces) do
        if piece.npc and want_id(piece.npc_id, id_filter) then
            Npc.clear_piece_walk(piece)

            if duration and duration > 0 then
                map.pieces_removals = map.pieces_removals or {}
                map.pieces_removals[#map.pieces_removals + 1] = {
                    npc_id = piece.npc_id,
                    piece = piece,
                    elapsed = 0,
                    duration = duration,
                }
                faded = true
            else
                piece._removed = true
            end
        end
    end

    if not faded then
        Npc.compact_removed(map)
    end
end

return Npc