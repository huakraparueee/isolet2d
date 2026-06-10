--[[
  Transient projectiles — spawn, arc/line motion in placement space, on_hit events.
]]

local Events
local Npc = require("npc")
local Path = require("path")
local Placement = require("placement")
local Setup = require("setup")
local Tile = require("tile")

local Projectile = {}

local catalogs = {}
local pool = {}
local next_id = 1
local MAX_ACTIVE = 32

local function release(proj)
    for k in pairs(proj) do
        proj[k] = nil
    end

    pool[#pool + 1] = proj
end

local function take()
    return table.remove(pool) or {}
end

local function active_count(map)
    local list = map.projectiles

    return list and #list or 0
end

local function spec(kind)
    local cfg = Setup.get().projectiles or {}

    return cfg[kind]
end

local function grid(map)
    if not map or not map.grid then
        error("projectile: map.grid is missing")
    end

    return map.grid
end

local function load_image(def)
    if not def.path then
        return nil
    end

    local image = love.graphics.newImage(def.path)
    image:setFilter("nearest", "nearest")

    return image
end

local function ensure_catalog(kind)
    if catalogs[kind] then
        return catalogs[kind]
    end

    local def = spec(kind)

    if not def then
        error("unknown projectile kind: " .. tostring(kind))
    end

    catalogs[kind] = {
        kind = kind,
        image = load_image(def),
        w = def.w,
        h = def.h,
        move = def.move or "arc",
        duration = def.duration or 0.45,
        arc_height = def.arc_height or 40,
        radius = def.radius or 5,
        color = def.color or { 1, 0.85, 0.3 },
        draw_offset_x = def.draw_offset_x or 0,
        draw_offset_y = def.draw_offset_y or 0,
    }

    return catalogs[kind]
end

local function unique_id(ev)
    if ev.id then
        return ev.id
    end

    local id = "proj_" .. next_id
    next_id = next_id + 1

    return id
end

local function resolve_from(map, ev)
    if ev.from then
        local from = ev.from

        if from.npc_id or from.id then
            local piece = Npc.find_by_id(map, from.npc_id or from.id)

            if not piece or piece.pos_x == nil or piece.pos_y == nil then
                error("projectile: unknown from npc " .. tostring(from.npc_id or from.id))
            end

            return piece.pos_x, piece.pos_y, piece.tile_z or 0, piece
        end

        if from.px ~= nil and from.py ~= nil then
            local tx = math.floor(from.px + 0.0001)
            local ty = math.floor(from.py + 0.0001)

            return from.px, from.py, from.z or grid(map).surface_z(tx, ty), nil
        end

        if from.tile_x ~= nil and from.tile_y ~= nil then
            return Projectile.tile_target(map, from.tile_x, from.tile_y, 1, 1)
        end
    end

    if ev.npc_id or ev.id then
        local piece = Npc.find_by_id(map, ev.npc_id or ev.id)

        if not piece or piece.pos_x == nil or piece.pos_y == nil then
            error("projectile: unknown npc " .. tostring(ev.npc_id or ev.id))
        end

        return piece.pos_x, piece.pos_y, piece.tile_z or 0, piece
    end

    if ev.from_px ~= nil and ev.from_py ~= nil then
        local tx = math.floor(ev.from_px + 0.0001)
        local ty = math.floor(ev.from_py + 0.0001)

        return ev.from_px, ev.from_py, ev.from_z or grid(map).surface_z(tx, ty), nil
    end

    error("projectile.spawn requires from (npc_id, px/py, or tile_x/y)")
end

function Projectile.tile_target(map, tile_x, tile_y, tiles_w, tiles_d)
    tiles_w = tiles_w or 1
    tiles_d = tiles_d or 1

    local node = Placement.node_for_footprint(map, tile_x, tile_y, tiles_w, tiles_d)

    if node then
        return node.px, node.py, node.z
    end

    return tile_x + tiles_w * 0.5,
        tile_y + tiles_d * 0.5,
        Path.surface_z(map, tile_x, tile_y)
end

local function resolve_to(map, ev)
    if ev.to then
        local to = ev.to

        if to.px ~= nil and to.py ~= nil then
            local tx = math.floor(to.px + 0.0001)
            local ty = math.floor(to.py + 0.0001)

            return to.px, to.py, to.z or grid(map).surface_z(tx, ty)
        end

        if to.tile_x ~= nil and to.tile_y ~= nil then
            return Projectile.tile_target(
                map,
                to.tile_x,
                to.tile_y,
                to.tiles_w,
                to.tiles_d
            )
        end
    end

    if ev.tile_x ~= nil and ev.tile_y ~= nil then
        return Projectile.tile_target(
            map,
            ev.tile_x,
            ev.tile_y,
            ev.tiles_w,
            ev.tiles_d
        )
    end

    if ev.to_px ~= nil and ev.to_py ~= nil then
        local tx = math.floor(ev.to_px + 0.0001)
        local ty = math.floor(ev.to_py + 0.0001)

        return ev.to_px, ev.to_py, ev.to_z or grid(map).surface_z(tx, ty)
    end

    error("projectile.spawn requires to (tile_x/y, px/py, or to table)")
end

local function merge_spec(kind, ev)
    local cat = ensure_catalog(kind)

    return {
        kind = kind,
        move = ev.move or cat.move,
        duration = ev.duration or cat.duration,
        arc_height = ev.arc_height or cat.arc_height,
        catalog = cat,
    }
end

local function fire_on_hit(map, payload)
    if not payload then
        return
    end

    if not Events then
        Events = require("events")
    end

    Events.run(map, payload)
end

local function finish_projectile(map, proj)
    fire_on_hit(map, proj.on_hit)
end

function Projectile.load()
    catalogs = {}
    next_id = 1

    for kind, _ in pairs(Setup.get().projectiles or {}) do
        ensure_catalog(kind)
    end
end

function Projectile.preload()
    Projectile.load()
end

function Projectile.spawn(map, ev)
    ev = ev or {}

    map.projectiles = map.projectiles or {}

    if active_count(map) >= MAX_ACTIVE then
        return nil
    end

    local kind = ev.kind or ev.projectile or "bolt"
    local opts = merge_spec(kind, ev)
    local from_px, from_py, from_z, from_piece = resolve_from(map, ev)
    local to_px, to_py, to_z = resolve_to(map, ev)
    local proj = take()

    proj.id = unique_id(ev)
    proj.kind = kind
    proj.move = opts.move
    proj.duration = opts.duration
    proj.arc_height = opts.arc_height
    proj.catalog = opts.catalog
    proj.from_px = from_px
    proj.from_py = from_py
    proj.from_z = from_z
    proj.to_px = to_px
    proj.to_py = to_py
    proj.to_z = to_z
    proj.px = from_px
    proj.py = from_py
    proj.z = from_z
    proj.elapsed = 0
    proj.t = 0
    proj.draw_offset_x = ev.draw_offset_x
    proj.draw_offset_y = ev.draw_offset_y
    proj.on_hit = ev.on_hit
    proj.from_piece = from_piece
    proj.meta = ev.meta

    map.projectiles[#map.projectiles + 1] = proj

    return proj
end

function Projectile.count(map)
    return active_count(map)
end

function Projectile.each(map, fn)
    if not fn then
        return
    end

    for _, proj in ipairs(map.projectiles or {}) do
        fn(proj)
    end
end

function Projectile.queue_spawn(map, spawn_ev, delay)
    spawn_ev = spawn_ev or {}
    map.projectile_pending = map.projectile_pending or {}
    map.projectile_pending[#map.projectile_pending + 1] = {
        delay = delay or spawn_ev.delay or 0,
        elapsed = 0,
        ev = spawn_ev,
    }
end

local function default_shoot_mode(piece)
    local kind = piece.npc and piece.npc.kind

    if not kind then
        return nil
    end

    local def = Npc.def(kind)

    if not def or not def.modes then
        return nil
    end

    if def.modes.shoot then
        return "shoot"
    end

    if def.modes.action then
        return "action"
    end

    return nil
end

function Projectile.shoot_from_npc(map, ev)
    ev = ev or {}

    local id = ev.id or ev.npc_id

    if not id then
        error("npc.shoot requires id")
    end

    local piece = Npc.find_by_id(map, id)

    if not piece or piece.pos_x == nil or piece.pos_y == nil then
        error("npc.shoot: unknown npc " .. tostring(id))
    end

    local to_px, to_py = resolve_to(map, ev)
    local dx = to_px - piece.pos_x
    local dy = to_py - piece.pos_y
    local facing = Npc.facing_for_delta(dx, dy, piece.npc)

    if facing then
        Npc.apply_facing(piece, facing)
    end

    local shoot_mode = ev.mode

    if shoot_mode == nil then
        shoot_mode = default_shoot_mode(piece)
    end

    if shoot_mode then
        Npc.set_mode(map, shoot_mode, id, {
            loop = ev.loop,
            count = ev.count or 1,
            after_mode = ev.after_mode or "stand",
        })
    end

    local spawn_ev = {
        kind = ev.kind or ev.projectile,
        from = { npc_id = id },
        move = ev.move,
        duration = ev.duration,
        arc_height = ev.arc_height,
        on_hit = ev.on_hit,
        id = ev.projectile_id,
    }

    if ev.to then
        spawn_ev.to = ev.to
    elseif ev.tile_x ~= nil and ev.tile_y ~= nil then
        spawn_ev.to = {
            tile_x = ev.tile_x,
            tile_y = ev.tile_y,
            tiles_w = ev.tiles_w,
            tiles_d = ev.tiles_d,
        }
    elseif ev.to_px ~= nil and ev.to_py ~= nil then
        spawn_ev.to = { px = ev.to_px, py = ev.to_py, z = ev.to_z }
    else
        error("npc.shoot requires to (tile_x/y or to table)")
    end

    local delay = ev.delay

    if delay and delay > 0 then
        Projectile.queue_spawn(map, spawn_ev, delay)
    else
        Projectile.spawn(map, spawn_ev)
    end
end

function Projectile.find_by_id(map, id)
    for _, proj in ipairs(map.projectiles or {}) do
        if proj.id == id then
            return proj
        end
    end
end

function Projectile.clear(map)
    if not map then
        return
    end

    if map.projectiles then
        for i = #map.projectiles, 1, -1 do
            release(map.projectiles[i])
        end
    end

    map.projectiles = nil
    map.projectile_pending = nil
end

function Projectile.is_busy(map)
    local pending = map.projectile_pending

    if pending and #pending > 0 then
        return true
    end

    local list = map.projectiles

    return list ~= nil and #list > 0
end

local function update_pending(map, dt)
    local pending = map.projectile_pending

    if not pending or #pending == 0 then
        return
    end

    local i = 1

    while i <= #pending do
        local job = pending[i]
        job.elapsed = job.elapsed + dt

        if job.elapsed >= job.delay then
            Projectile.spawn(map, job.ev)
            table.remove(pending, i)
        else
            i = i + 1
        end
    end
end

function Projectile.update(map, dt)
    if map.projectile_paused then
        return
    end

    update_pending(map, dt)

    local list = map.projectiles

    if not list or #list == 0 then
        return
    end

    local i = 1

    while i <= #list do
        local proj = list[i]
        proj.elapsed = proj.elapsed + dt
        local t = proj.elapsed / proj.duration

        if t >= 1 then
            proj.px = proj.to_px
            proj.py = proj.to_py
            proj.z = proj.to_z
            finish_projectile(map, proj)
            list[i] = list[#list]
            list[#list] = nil
            release(proj)
        else
            proj.px = proj.from_px + (proj.to_px - proj.from_px) * t
            proj.py = proj.from_py + (proj.to_py - proj.from_py) * t
            proj.z = proj.from_z + (proj.to_z - proj.from_z) * t
            proj.t = t
            i = i + 1
        end
    end
end

function Projectile.sort_key(proj)
    local tx = math.floor(proj.px + 0.0001)
    local ty = math.floor(proj.py + 0.0001)

    return tx + ty, tx, ty
end

function Projectile.draw(proj, lg, layout)
    local t = proj.t or 0
    local sx, sy = Tile.placement_to_screen(layout, proj.px, proj.py, proj.z)

    if proj.move == "arc" then
        sy = sy - math.sin(math.pi * t) * proj.arc_height
    end

    local cat = proj.catalog
    local scale = layout.scale or 1
    local draw_ox = proj.draw_offset_x

    if draw_ox == nil and cat then
        draw_ox = cat.draw_offset_x
    end

    local draw_oy = proj.draw_offset_y

    if draw_oy == nil and cat then
        draw_oy = cat.draw_offset_y
    end

    sx = sx + (draw_ox or 0) * scale
    sy = sy + (draw_oy or 0) * scale

    local color = cat and cat.color or { 1, 0.85, 0.3 }
    local dx = proj.to_px - proj.from_px
    local dy = proj.to_py - proj.from_py
    local angle = math.atan2(dy, dx)

    if cat and cat.image then
        local w = cat.w or cat.image:getWidth()
        local h = cat.h or cat.image:getHeight()

        lg.setColor(1, 1, 1, 1)
        lg.draw(
            cat.image,
            sx,
            sy,
            angle,
            scale,
            scale,
            w * 0.5,
            h * 0.5
        )
        return
    end

    local r = (cat and cat.radius or 5) * (layout.scale or 1)

    lg.setColor(0, 0, 0, 0.85)
    lg.circle("fill", sx, sy, r + 2)
    lg.setColor(color[1], color[2], color[3], 1)
    lg.circle("fill", sx, sy, r)
    lg.setColor(1, 1, 1, 1)
    lg.circle("line", sx, sy, r + 1)
    lg.setColor(1, 1, 1, 1)
end

return Projectile
