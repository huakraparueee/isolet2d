--[[
  Run event payloads on the iso map — scene resolves ids to objects before dispatch.
  Uses map.grid / map.terrain_mat_color bound by bind_grid.
]]

local Terrain = require("terrain")
local Structure = require("structure")
local Npc = require("npc")

local Events = {}

local function queue_op(map, op)
    map.pending_ops = map.pending_ops or {}
    map.pending_ops[#map.pending_ops + 1] = op
end

local function grid(map)
    if not map or not map.grid then
        error("events: map.grid is missing (call Iso.bind_grid)")
    end

    return map.grid
end

local function color_for_event(map, ev)
    if ev.color then
        return ev.color
    end

    if ev.mat and map.terrain_mat_color then
        local r, g, b = map.terrain_mat_color(ev.mat)

        if r then
            return { r, g, b }
        end
    end

    return nil
end

local function terrain_add(map, ev)
    if not grid(map).in_bounds(ev.tile_x, ev.tile_y) then
        return
    end

    local tile_z = ev.tile_z

    if tile_z == nil then
        tile_z = grid(map).height_at(ev.tile_x, ev.tile_y)

        if tile_z < 0 then
            tile_z = 0
        end
    end

    local piece = {
        tile_x = ev.tile_x,
        tile_y = ev.tile_y,
        tile_z = tile_z,
        color = color_for_event(map, ev),
        mat = ev.mat,
    }

    if map.apply_terrain_mat and ev.mat then
        map.apply_terrain_mat(piece, ev.mat)
    end

    if ev.alpha ~= nil then
        piece.alpha = ev.alpha
    end

    if piece.alpha == nil then
        piece.alpha = 1
    end

    map.pieces[#map.pieces + 1] = piece
    map.refresh_height_at(ev.tile_x, ev.tile_y)
    Terrain.rebake_tile_now(map, ev.tile_x, ev.tile_y)

    local h = grid(map).height_at(ev.tile_x, ev.tile_y)
    local top_z = h > 0 and h - 1 or 0

    map.terrain_bake_max_z = math.max(map.terrain_bake_max_z or 0, top_z)
    Terrain.mark_piece_dynamic(map, piece)
end

local function npc_add(map, ev)
    if not ev.id then
        error("npc.add requires id")
    end

    if not ev.kind then
        error("npc.add requires kind")
    end

    local piece = {
        npc_id = ev.id,
        alpha = 1,
    }

    map.pieces[#map.pieces + 1] = piece
    map.npc_pieces = map.npc_pieces or {}
    map.npc_pieces[#map.npc_pieces + 1] = piece
    queue_op(map, { type = "npc.add", piece = piece, ev = ev })
end

local function structure_add(map, ev)
    local kind = ev.kind or ev.structure

    if not kind then
        error("structure.add requires kind")
    end

    if map.has_structure_kind
        and not map.has_structure_kind(kind)
    then
        error("unknown structure kind: " .. tostring(kind))
    end

    if not grid(map).in_bounds(ev.tile_x, ev.tile_y) then
        return
    end

    local structure_id = ev.id or ev.structure_id

    if not structure_id then
        error("structure.add requires id")
    end

    if Structure.find_by_id(map, structure_id) then
        return
    end

    for _, cell in ipairs(Structure.footprint_cells(map, ev.tile_x, ev.tile_y, kind)) do
        if not grid(map).in_bounds(cell.tile_x, cell.tile_y) then
            return
        end

        if Structure.find_at(map, cell.tile_x, cell.tile_y) then
            return
        end
    end

    local tile_z = grid(map).surface_z(ev.tile_x, ev.tile_y)

    map.pieces[#map.pieces + 1] = {
        structure = kind,
        structure_id = structure_id,
        tile_x = ev.tile_x,
        tile_y = ev.tile_y,
        tile_z = tile_z,
        alpha = 1,
    }
    map.structure_pieces = map.structure_pieces or {}
    map.structure_pieces[#map.structure_pieces + 1] = map.pieces[#map.pieces]
    queue_op(map, {
        type = "structure.add",
        piece = map.pieces[#map.pieces],
        ev = ev,
    })
end

local function structure_remove(map, ev)
    local piece

    if ev.id or ev.structure_id then
        piece = Structure.find_by_id(map, ev.id or ev.structure_id)
    else
        piece = Structure.find_at(map, ev.tile_x, ev.tile_y)
    end

    if not piece then
        return
    end

    map.pieces_removals = map.pieces_removals or {}
    map.pieces_removals[#map.pieces_removals + 1] = {
        structure_id = piece.structure_id,
        tile_x = piece.tile_x,
        tile_y = piece.tile_y,
        tile_z = piece.tile_z or 0,
        elapsed = 0,
        duration = ev.duration or 0.3,
    }
end

local function npc_set_mode(map, ev)
    if not ev.mode then
        error("npc.set_mode requires mode")
    end

    queue_op(map, {
        type = "npc.set_mode",
        mode = ev.mode,
        id = ev.id or ev.npc_id,
        opts = {
            loop = ev.loop,
            count = ev.count,
            after_mode = ev.after_mode,
        },
    })
end

local function structure_set_mode(map, ev)
    if not ev.mode then
        error("structure.set_mode requires mode")
    end

    queue_op(map, {
        type = "structure.set_mode",
        mode = ev.mode,
        id = ev.id or ev.structure_id,
        opts = {
            loop = ev.loop,
            count = ev.count,
            after_mode = ev.after_mode,
        },
    })
end

local function projectile_spawn(map, ev)
    queue_op(map, { type = "projectile.spawn", ev = ev })
end

local function npc_remove(map, ev)
    queue_op(map, {
        type = "npc.remove",
        id = ev.id or ev.npc_id,
        duration = ev.duration,
    })
end

local function npc_place(map, ev)
    if not ev.id then
        error("npc.place requires id")
    end

    if not ev.kind then
        error("npc.place requires kind")
    end

    queue_op(map, { type = "npc.place", ev = ev })
end

local function npc_retire(map, ev)
    queue_op(map, {
        type = "npc.retire",
        id = ev.id or ev.npc_id,
    })
end

local function npc_shoot(map, ev)
    queue_op(map, { type = "npc.shoot", ev = ev })
end

local function npc_walk_to(map, ev)
    local op = {
        type = "npc.walk_to",
        id = ev.id or ev.npc_id,
    }

    if ev.pos_x ~= nil and ev.pos_y ~= nil then
        local tx = math.floor(ev.pos_x + 0.0001)
        local ty = math.floor(ev.pos_y + 0.0001)

        op.pos_x = ev.pos_x
        op.pos_y = ev.pos_y
        op.tile_z = grid(map).surface_z(tx, ty)
    else
        op.tile_x = ev.tile_x
        op.tile_y = ev.tile_y
        op.tile_z = grid(map).surface_z(ev.tile_x, ev.tile_y)
    end

    queue_op(map, op)
end

local function copy_color(rgb)
    if not rgb then
        return nil
    end

    return { rgb[1], rgb[2], rgb[3] }
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_color(from, to, t)
    if not to then
        return copy_color(from)
    end

    if not from then
        return copy_color(to)
    end

    return {
        lerp(from[1], to[1], t),
        lerp(from[2], to[2], t),
        lerp(from[3], to[3], t),
    }
end

local function target_state_for_update(map, piece, ev)
    local to_mat = ev.mat ~= nil and ev.mat or piece.mat
    local to_color

    if ev.color ~= nil then
        to_color = copy_color(ev.color)
    elseif ev.mat ~= nil then
        to_color = color_for_event(map, ev)
    else
        to_color = copy_color(piece.color)
    end

    local to_alpha = ev.alpha

    if to_alpha == nil and ev.mat ~= nil and map.terrain_mat_alpha then
        to_alpha = map.terrain_mat_alpha(ev.mat)
    end

    if to_alpha == nil then
        to_alpha = piece.alpha or 1
    end

    return {
        mat = to_mat,
        color = to_color,
        alpha = to_alpha,
    }
end

local function apply_terrain_update_job(piece, job, t)
    t = math.min(t, 1)

    if job.mat_fade_in then
        piece.alpha = lerp(0, job.to.alpha, t)

        if t >= 1 then
            piece.mat = job.to.mat

            if job.to.color then
                piece.color = copy_color(job.to.color)
            end

            piece.alpha = job.to.alpha
            return true
        end

        return false
    end

    piece.alpha = lerp(job.from.alpha, job.to.alpha, t)

    if job.from.color or job.to.color then
        piece.color = lerp_color(job.from.color, job.to.color, t)
    end

    if t >= 1 then
        piece.mat = job.to.mat

        if job.to.color then
            piece.color = copy_color(job.to.color)
        end

        piece.alpha = job.to.alpha
        return true
    end

    return false
end

local function terrain_update(map, ev)
    if not grid(map).in_bounds(ev.tile_x, ev.tile_y) then
        return
    end

    local piece = Terrain.find_terrain_at(
        map,
        ev.tile_x,
        ev.tile_y,
        ev.tile_z
    )

    if not piece then
        return
    end

    Terrain.mark_piece_dynamic(map, piece)

    local duration = ev.duration

    if not duration or duration <= 0 then
        local to = target_state_for_update(map, piece, ev)

        piece.mat = to.mat

        if to.color then
            piece.color = to.color
        end

        piece.alpha = to.alpha

        if map.apply_terrain_mat and piece.mat then
            map.apply_terrain_mat(piece, piece.mat)
            piece.alpha = to.alpha
        end

        map.refresh_height_at(ev.tile_x, ev.tile_y)
        Terrain.finish_piece_bake(map, piece)
        Terrain.rebake_tile_now(map, ev.tile_x, ev.tile_y)
        return
    end

    local to = target_state_for_update(map, piece, ev)
    local from = {
        mat = piece.mat,
        color = copy_color(piece.color),
        alpha = piece.alpha or 1,
    }
    local mat_changed = ev.mat ~= nil and ev.mat ~= piece.mat

    if mat_changed then
        piece.mat = to.mat

        if to.color then
            piece.color = copy_color(to.color)
        end

        piece.alpha = 0
    end

    map.pieces_updates = map.pieces_updates or {}
    map.pieces_updates[#map.pieces_updates + 1] = {
        piece = piece,
        tile_x = piece.tile_x,
        tile_y = piece.tile_y,
        tile_z = piece.tile_z or 0,
        elapsed = 0,
        duration = duration,
        from = from,
        to = to,
        mat_fade_in = mat_changed,
    }
end

local function terrain_remove(map, ev)
    local piece = Terrain.find_terrain_at(
        map,
        ev.tile_x,
        ev.tile_y,
        ev.tile_z
    )

    if not piece then
        return
    end

    Terrain.mark_piece_dynamic(map, piece)

    map.pieces_removals = map.pieces_removals or {}
    map.pieces_removals[#map.pieces_removals + 1] = {
        piece = piece,
        tile_x = piece.tile_x,
        tile_y = piece.tile_y,
        tile_z = piece.tile_z or 0,
        elapsed = 0,
        duration = ev.duration or 0.3,
    }
end

local HANDLERS = {
    ["terrain.add"] = terrain_add,
    ["terrain.update"] = terrain_update,
    ["terrain.remove"] = terrain_remove,
    ["structure.add"] = structure_add,
    ["structure.remove"] = structure_remove,
    ["structure.set_mode"] = structure_set_mode,
    ["npc.add"] = npc_add,
    ["npc.place"] = npc_place,
    ["npc.retire"] = npc_retire,
    ["npc.set_mode"] = npc_set_mode,
    ["npc.walk_to"] = npc_walk_to,
    ["npc.shoot"] = npc_shoot,
    ["npc.remove"] = npc_remove,
    ["projectile.spawn"] = projectile_spawn,
}

local function run_event(map, ev)
    if not ev.type then
        return
    end

    local fn = HANDLERS[ev.type]

    if fn then
        fn(map, ev)
    end
end

local function run_payload(map, ev)
    if not ev then
        return
    end

    if ev[1] and not ev.type then
        for _, step in ipairs(ev) do
            run_event(map, step)
        end

        return
    end

    run_event(map, ev)
end

function Events.run(map, ev)
    run_payload(map, ev)
end

function Events.run_many(map, evs)
    for _, ev in ipairs(evs or {}) do
        run_payload(map, ev)
    end
end

function Events.is_busy(map)
    local updates = map.pieces_updates

    if updates and #updates > 0 then
        return true
    end

    local removals = map.pieces_removals

    if removals and #removals > 0 then
        return true
    end

    local pending = map.pending_ops

    if pending and #pending > 0 then
        return true
    end

    if map.pieces then
        for _, piece in ipairs(map.pieces) do
            if piece.npc_id and not piece.npc then
                return true
            end
        end
    end

    return false
end

function Events.take_pending_ops(map)
    local ops = map.pending_ops

    map.pending_ops = nil

    return ops
end

local function update_terrain_updates(map, dt)
    local updates = map.pieces_updates

    if not updates or #updates == 0 then
        return
    end

    local i = 1

    while i <= #updates do
        local job = updates[i]
        job.elapsed = job.elapsed + dt
        local piece = job.piece

        if not piece or piece._removed then
            piece = Terrain.find_at(
                map,
                job.tile_x,
                job.tile_y,
                job.tile_z
            )
        end

        if not piece then
            table.remove(updates, i)
        else
            local t = job.elapsed / job.duration

            if apply_terrain_update_job(piece, job, t) then
                if map.apply_terrain_mat and piece.mat then
                    map.apply_terrain_mat(piece, piece.mat)
                    piece.alpha = job.to.alpha
                end

                map.refresh_height_at(job.tile_x, job.tile_y)
                Terrain.finish_piece_bake(map, piece)
                Terrain.rebake_tile_now(map, job.tile_x, job.tile_y)
                table.remove(updates, i)
            else
                i = i + 1
            end
        end
    end
end

local function update_terrain_removals(map, dt)
    local removals = map.pieces_removals

    if not removals or #removals == 0 then
        return
    end

    local i = 1

    while i <= #removals do
        local job = removals[i]
        job.elapsed = job.elapsed + dt
        local piece = job.piece

        if job.structure_id then
            piece = Structure.find_by_id(map, job.structure_id)
        elseif job.npc_id then
            piece = Npc.find_by_id(map, job.npc_id)
        elseif not piece or piece._removed then
            piece = Terrain.find_at(
                map,
                job.tile_x,
                job.tile_y,
                job.tile_z
            )
        end

        if piece then
            local t = job.elapsed / job.duration

            if t >= 1 then
                piece._removed = true
                table.remove(removals, i)
            else
                piece.alpha = 1 - t
                i = i + 1
            end
        else
            table.remove(removals, i)
        end
    end

    local kept = {}
    local removed_tiles = {}
    local placement_tiles = {}

    for _, piece in ipairs(map.pieces) do
        if piece._removed then
            if Terrain.is_terrain_block(piece) then
                removed_tiles[#removed_tiles + 1] = {
                    piece.tile_x,
                    piece.tile_y,
                }
            elseif Structure.is_piece(piece) then
                for _, cell in ipairs(
                    Structure.footprint_cells(
                        map,
                        piece.tile_x,
                        piece.tile_y,
                        piece.structure
                    )
                ) do
                    placement_tiles[#placement_tiles + 1] = cell
                end
            end
        else
            kept[#kept + 1] = piece
        end
    end

    map.pieces = kept
    map.sync_structure_pieces()
    map.sync_npc_pieces()

    for _, tile in ipairs(removed_tiles) do
        map.refresh_height_at(tile[1], tile[2])
    end

    if map.rebuild_placement_tile then
        for _, cell in ipairs(placement_tiles) do
            map.rebuild_placement_tile(cell.tile_x, cell.tile_y)
        end
    end

    if #removed_tiles > 0 then
        Terrain.rebuild_floor_chunks(map)
    end
end

function Events.update(map, dt)
    update_terrain_updates(map, dt)
    update_terrain_removals(map, dt)
end

return Events
