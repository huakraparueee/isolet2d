
local anim8 = require("anim8")
local Setup = require("setup")
local Lookup = require("lookup")
local Footprint = require("footprint")
local Walk = require("walk")
local IsoGround = require("ground")

local WALK_SPEED = 7
local ARRIVE_DIST = 0.04
local T

local function tile_center(tile_x, tile_y, tiles_w, tiles_d)
    return tile_x + tiles_w * 0.5, tile_y + tiles_d * 0.5
end

local function sync_pos_from_tiles(piece)
    piece.pos_x, piece.pos_y = tile_center(
        piece.tile_x,
        piece.tile_y,
        piece.tiles_w or 1,
        piece.tiles_d or 1
    )
end

local function sync_tiles_from_pos(piece)
    local w = piece.tiles_w or 1
    local d = piece.tiles_d or 1

    piece.tile_x = math.floor(piece.pos_x - w * 0.5 + 0.0001)
    piece.tile_y = math.floor(piece.pos_y - d * 0.5 + 0.0001)
end

local function path_waypoint_center(wp, tiles_w, tiles_d)
    return {
        x = wp.x + tiles_w * 0.5,
        y = wp.y + tiles_d * 0.5,
        z = wp.z,
    }
end

local catalogs = {}
local set_mode

local function grid_frames(grid, cols)
    if type(cols) == "number" then
        return grid(cols, 1)
    end

    if type(cols) == "string" and not cols:find("-", 1, true) then
        return grid(tonumber(cols), 1)
    end

    return grid(cols, 1)
end

local function make_clip(grid, def)
    local anim = anim8.newAnimation(grid_frames(grid, def.cols), def.interval)

    if def.pause then
        anim:pauseAtStart()
    end

    return anim
end

local function load_sheet(spec)
    local path = spec.path
    local image = love.graphics.newImage(path)
    local w, h = image:getWidth(), image:getHeight()

    if w ~= spec.sheet_w or h ~= spec.sheet_h then
        error(
            string.format(
                "%s must be %dx%d, got %dx%d",
                path,
                spec.sheet_w,
                spec.sheet_h,
                w,
                h
            )
        )
    end

    image:setFilter("nearest", "nearest")

    local grid = anim8.newGrid(spec.w, spec.h, w, h)
    local templates = {}
    local mode_names = {}

    for mode, def in pairs(spec.modes) do
        mode_names[#mode_names + 1] = mode
        local right = make_clip(grid, def)

        templates[mode .. "_right"] = right
        templates[mode .. "_left"] = right:clone():flipH()
    end

    table.sort(mode_names)

    return {
        image = image,
        w = spec.w,
        h = spec.h,
        modes = spec.modes,
        mode_names = mode_names,
        templates = templates,
    }
end

local function clip_key(mode, facing)
    return mode .. "_" .. facing
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
    local key = clip_key(state.mode, state.facing)
    local template = state.catalog.templates[key]

    if not template then
        error("unknown npc mode: " .. tostring(state.mode))
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

    if state.seg_z0 == nil then
        local w = piece.tiles_w or 1
        local d = piece.tiles_d or 1

        state.seg_z0 = Walk.surface_z(
            map,
            math.floor(piece.pos_x - w * 0.5 + 0.0001),
            math.floor(piece.pos_y - d * 0.5 + 0.0001)
        )
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

local function finish_walk(state, piece)
    if state.final_z ~= nil then
        piece.tile_z = state.final_z
    end

    sync_tiles_from_pos(piece)
    clear_walk(state)
    set_mode(state, "stand")
end

local function ensure_catalog(kind)
    if catalogs[kind] then
        return catalogs[kind]
    end

    local spec = Lookup.npc_spec(Setup.get().npcs, kind)

    if not spec then
        error("unknown npc kind: " .. tostring(kind))
    end

    catalogs[kind] = load_sheet(spec)

    return catalogs[kind]
end

local function spawn(opts)
    opts = opts or {}

    local kind = opts.kind or "r"
    local catalog = ensure_catalog(kind)

    local facing = opts.facing or "right"
    local mode = opts.mode or "stand"

    if facing ~= "left" and facing ~= "right" then
        error("npc facing must be 'left' or 'right'")
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
        facing = facing,
        mode = mode,
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
    apply_state(state)
end

local function is_walking(state)
    return state.path ~= nil
end

local function walk_state_to(state, piece, map, tile_x, tile_y, tile_z)
    state.mode_busy = false
    state.mode_left = nil
    state.after_mode = nil
    clear_walk(state)

    local w = piece.tiles_w or 1
    local d = piece.tiles_d or 1
    local from_x = math.floor(piece.pos_x - w * 0.5 + 0.0001)
    local from_y = math.floor(piece.pos_y - d * 0.5 + 0.0001)
    local path = Walk.find_path(map, from_x, from_y, tile_x, tile_y)

    if path == nil then
        set_mode(state, "stand")
        return false
    end

    state.final_z = tile_z ~= nil and tile_z or Walk.surface_z(map, tile_x, tile_y)

    if #path == 0 then
        piece.tile_x = tile_x
        piece.tile_y = tile_y
        sync_pos_from_tiles(piece)
        finish_walk(state, piece)
        return true
    end

    local centered = {}

    for i, wp in ipairs(path) do
        centered[i] = path_waypoint_center(wp, w, d)
    end

    state.path = centered
    state.path_i = 1
    begin_path_segment(state, piece, map, centered[1])
    set_mode(state, "walk")
    return true
end

local function facing_for_step(dx, dy)
    local screen_x = dx - dy

    if screen_x < 0 then
        return "left"
    end

    if screen_x > 0 then
        return "right"
    end

    if dy > 0 then
        return "left"
    end

    if dy < 0 then
        return "right"
    end
end

local function update_state(state, piece, map, dt)
    state.current:update(dt)

    if not state.path then
        return
    end

    local wp = state.path[state.path_i]

    if not wp then
        finish_walk(state, piece)
        return
    end

    local px = piece.pos_x
    local py = piece.pos_y
    local dx = wp.x - px
    local dy = wp.y - py
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist <= ARRIVE_DIST then
        piece.pos_x = wp.x
        piece.pos_y = wp.y
        piece.tile_z = wp.z
        sync_tiles_from_pos(piece)

        if state.path_i >= #state.path then
            finish_walk(state, piece)
            return
        end

        state.path_i = state.path_i + 1
        local next_wp = state.path[state.path_i]

        if next_wp then
            begin_path_segment(state, piece, map, next_wp)
        end

        return
    end

    local step = math.min(dist, WALK_SPEED * dt)
    piece.pos_x = px + (dx / dist) * step
    piece.pos_y = py + (dy / dist) * step

    local seg_dx = wp.x - state.seg_x0
    local seg_dy = wp.y - state.seg_y0
    local seg_len = math.sqrt(seg_dx * seg_dx + seg_dy * seg_dy)
    local moved_x = piece.pos_x - state.seg_x0
    local moved_y = piece.pos_y - state.seg_y0
    local moved = math.sqrt(moved_x * moved_x + moved_y * moved_y)
    local t = 0

    if seg_len > 0.0001 then
        t = moved / seg_len
    end

    piece.tile_z = state.seg_z0 + (wp.z - state.seg_z0) * t

    local facing = facing_for_step(dx, dy)

    if facing then
        set_facing(state, facing)
    end
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

function Npc.facing_for_delta(dx, dy)
    return facing_for_step(dx, dy)
end

function Npc.clear_piece_walk(piece)
    if piece.npc then
        clear_walk(piece.npc)
    end
end

function Npc.preload_npcs()
    T = Setup.get().tile_size

    for kind, _ in pairs(Lookup.npc_catalog(Setup.get().npcs)) do
        ensure_catalog(kind)
    end
end

function Npc.load()
    T = Setup.get().tile_size
    Npc.preload_npcs()
end

function Npc.sync_footprint(map, piece, kind, overrides)
    local w, d, h = Lookup.npc_footprint(
        Setup.get().npcs,
        kind,
        overrides
    )
    local draw_ox, draw_oy = Lookup.npc_draw_offset(
        Setup.get().npcs,
        kind,
        overrides
    )

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

    local w, d = piece.tiles_w, piece.tiles_d

    piece.tile_x = ev.tile_x
    piece.tile_y = ev.tile_y
    piece.tile_z = Walk.surface_z(map, ev.tile_x, ev.tile_y)

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

    sync_pos_from_tiles(piece)
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
            walk_state_to(piece.npc, piece, map, tile_x, tile_y, tile_z)
        end
    end
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

    local dw, dd, dh = Lookup.npc_tile_span(Setup.get().npcs, kind)

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
    local w, d = Npc.npc_tile_span(piece)
    local feet_x, feet_y =
        Footprint.feet_screen_from_piece(layout, piece, w, d, z_at)
    local draw_ox = piece.draw_offset_x or 0
    local draw_oy = piece.draw_offset_y or 0

    lg.setColor(1, 1, 1, alpha)
    piece.npc.current:draw(
        catalog.image,
        IsoGround.snap_px(feet_x + draw_ox),
        IsoGround.snap_px(feet_y + draw_oy),
        0,
        scale,
        scale,
        catalog.w * 0.5,
        catalog.h
    )

    return true
end

return Npc
