--[[
  Pipeline step 3 — structure pieces on tile_x, tile_y (occupancy blocks placement).
  w/h = frame size on the sheet; modes animate frames, no modes = frame 1 paused.
]]

local anim8 = require("anim8")
local Setup = require("setup")
local Tile = require("tile")

local catalogs = {}
local set_mode

local STATIC_MODE = {
    default = { cols = "1", interval = 1, pause = true },
}

local function spec(kind)
    return Setup.get().structures[kind]
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

local function load_sheet(kind, def)
    if not def.path then
        error("structure " .. tostring(kind) .. " requires path")
    end

    if not def.w or not def.h then
        error("structure " .. tostring(kind) .. " requires w and h (frame size)")
    end

    local path = def.path
    local image = love.graphics.newImage(path)
    local iw, ih = image:getWidth(), image:getHeight()

    if def.sheet_w and def.sheet_h then
        if iw ~= def.sheet_w or ih ~= def.sheet_h then
            error(
                string.format(
                    "%s must be %dx%d, got %dx%d",
                    path,
                    def.sheet_w,
                    def.sheet_h,
                    iw,
                    ih
                )
            )
        end
    end

    image:setFilter("nearest", "nearest")

    local grid = anim8.newGrid(def.w, def.h, iw, ih)
    local modes = def.modes or STATIC_MODE
    local templates = {}
    local mode_names = {}

    for mode, mode_def in pairs(modes) do
        mode_names[#mode_names + 1] = mode
        templates[mode] = make_clip(grid, mode_def)
    end

    table.sort(mode_names)

    local default_mode = modes.default and "default" or mode_names[1]

    return {
        kind = kind,
        image = image,
        w = def.w,
        h = def.h,
        modes = modes,
        mode_names = mode_names,
        templates = templates,
        default_mode = default_mode,
    }
end

local function ensure_catalog(kind)
    if catalogs[kind] then
        return catalogs[kind]
    end

    local def = spec(kind)

    if not def or not def.path or not def.w or not def.h then
        return nil
    end

    catalogs[kind] = load_sheet(kind, def)

    return catalogs[kind]
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

    local after_mode = play_opts.after_mode
        or (def and def.after_mode)
        or nil

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

    local next_mode = state.after_mode or state.catalog.default_mode

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
    local template = state.catalog.templates[state.mode]

    if not template then
        error(
            "unknown structure mode: "
                .. tostring(state.mode)
                .. " (kind "
                .. tostring(state.catalog.kind)
                .. ")"
        )
    end

    local anim = state.anims[state.mode]

    if not anim then
        anim = template:clone()
        state.anims[state.mode] = anim
    end

    state.current = anim

    local def = mode_def(state.catalog, state.mode)
    local playback = resolve_playback(def, state.play_opts)

    state.play_opts = nil
    configure_playback(state, anim, playback)
end

set_mode = function(state, mode, play_opts)
    if state.mode == mode and play_opts == nil and not state.mode_busy then
        return
    end

    if not state.catalog.modes[mode] then
        error(
            "unknown structure mode: "
                .. tostring(mode)
                .. " (kind "
                .. tostring(state.catalog.kind)
                .. ")"
        )
    end

    state.mode = mode
    state.play_opts = play_opts
    apply_state(state)
end

local function spawn(kind, opts)
    opts = opts or {}

    local catalog = ensure_catalog(kind)

    if not catalog then
        return nil
    end

    local mode = opts.mode or catalog.default_mode

    if not catalog.modes[mode] then
        error(
            "unknown structure mode: "
                .. tostring(mode)
                .. " (kind "
                .. tostring(kind)
                .. ")"
        )
    end

    local state = {
        catalog = catalog,
        mode = mode,
        anims = {},
        current = nil,
        mode_busy = false,
        mode_left = nil,
        after_mode = nil,
        play_opts = opts.play,
    }

    apply_state(state)

    return state
end

local function want_id(structure_id, filter)
    if not filter then
        return true
    end

    if type(filter) == "string" then
        return structure_id == filter
    end

    for _, id in ipairs(filter) do
        if structure_id == id then
            return true
        end
    end

    return false
end

local Structure = {}

function Structure.is_piece(piece)
    return piece.structure ~= nil
end

function Structure.tile_span(kind)
    local def = spec(kind)

    if not def then
        return 1, 1, 1
    end

    return def.tiles_w or 1, def.tiles_d or 1, def.tiles_h or 1
end

function Structure.has_kind(kind)
    return spec(kind) ~= nil
end

local function structure_span(map)
    return map.grid.structure_span
end

function Structure.covers_tile(map, piece, tile_x, tile_y)
    if not Structure.is_piece(piece) then
        return false
    end

    local w, d = structure_span(map)(piece.structure)
    local lx = tile_x - piece.tile_x
    local ly = tile_y - piece.tile_y

    return lx >= 0 and lx < w and ly >= 0 and ly < d
end

function Structure.blocks_tile(map, tile_x, tile_y)
    if not map then
        return false
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if not piece._removed
            and Structure.covers_tile(map, piece, tile_x, tile_y)
        then
            return true
        end
    end

    return false
end

function Structure.find_by_id(map, structure_id)
    if not map or not structure_id then
        return nil
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if piece.structure_id == structure_id then
            return piece
        end
    end
end

function Structure.find_at(map, tile_x, tile_y)
    if not map then
        return nil
    end

    for _, piece in ipairs(map.structure_pieces or {}) do
        if not piece._removed
            and Structure.covers_tile(map, piece, tile_x, tile_y)
        then
            return piece
        end
    end
end

function Structure.footprint_cells(map, tile_x, tile_y, kind)
    local w, d = structure_span(map)(kind)
    local cells = {}

    for ly = 0, d - 1 do
        for lx = 0, w - 1 do
            cells[#cells + 1] = {
                tile_x = tile_x + lx,
                tile_y = tile_y + ly,
            }
        end
    end

    return cells
end

function Structure.load()
    for kind, def in pairs(Setup.get().structures) do
        if def.path and def.w and def.h then
            ensure_catalog(kind)
        end
    end
end

function Structure.init_piece(piece, ev)
    ev = ev or {}

    if not ensure_catalog(piece.structure) then
        return
    end

    piece.struct_anim = spawn(piece.structure, {
        mode = ev.mode,
        play = {
            loop = ev.loop,
            count = ev.count,
            after_mode = ev.after_mode,
        },
    })
end

function Structure.set_mode(map, mode, id_filter, play_opts)
    for _, piece in ipairs(map.structure_pieces or {}) do
        if piece.struct_anim and want_id(piece.structure_id, id_filter) then
            set_mode(piece.struct_anim, mode, play_opts)
        end
    end
end

function Structure.update(map, dt)
    for _, piece in ipairs(map.structure_pieces or {}) do
        if piece.struct_anim and piece.struct_anim.current then
            piece.struct_anim.current:update(dt)
        end
    end
end

function Structure.draw(piece, lg, layout, alpha, z_at)
    local kind = piece.structure
    local def = spec(kind)

    if not def then
        return
    end

    if not piece.struct_anim and ensure_catalog(kind) then
        Structure.init_piece(piece, {})
    end

    if not piece.struct_anim or not piece.struct_anim.current then
        return
    end

    local scale = layout.scale or 1
    alpha = alpha or 1
    local w, d = Structure.tile_span(piece.structure)
    local feet_x, feet_y = Tile.feet_screen(layout, {
        ox = piece.tile_x,
        oy = piece.tile_y,
        tiles_w = w,
        tiles_d = d,
        tile_z = piece.tile_z,
        z_at = z_at,
    })

    local catalog = piece.struct_anim.catalog

    lg.setColor(1, 1, 1, alpha)
    piece.struct_anim.current:draw(
        catalog.image,
        Tile.snap_px(feet_x),
        Tile.snap_px(feet_y),
        0,
        scale,
        scale,
        catalog.w * 0.5,
        catalog.h
    )
end

return Structure
