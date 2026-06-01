--[[
  Lookups from cfg tables — no stored state
]]

local Lookup = {}

function Lookup.structure_tile_span(structures, kind)
    local def = structures and structures[kind]

    if not def then
        return 1, 1, 1
    end

    return def.tiles_w or 1, def.tiles_d or 1, def.tiles_h or 1
end

function Lookup.has_structure_kind(structures, kind)
    return structures ~= nil and structures[kind] ~= nil
end

function Lookup.terrain_mat_color(terrain_mats, mat)
    if not mat or not terrain_mats then
        return nil
    end

    local spec = terrain_mats[mat]

    if spec and spec.color then
        return spec.color[1], spec.color[2], spec.color[3]
    end
end

function Lookup.terrain_mat_walkable(terrain_mats, mat)
    if not mat or not terrain_mats then
        return true
    end

    local spec = terrain_mats[mat]

    if spec and spec.walkable == false then
        return false
    end

    return true
end

function Lookup.terrain_mat_alpha(terrain_mats, mat)
    if not mat or not terrain_mats then
        return 1
    end

    local spec = terrain_mats[mat]

    if spec and spec.alpha ~= nil then
        return spec.alpha
    end

    return 1
end

function Lookup.npc_spec(npc_defs, kind)
    if not kind then
        return nil
    end

    return npc_defs and npc_defs[kind]
end

function Lookup.npc_tile_span(npc_defs, kind)
    local def = Lookup.npc_spec(npc_defs, kind)

    if not def then
        return 1, 1, 1
    end

    return def.tiles_w or 1, def.tiles_d or 1, def.tiles_h or 1
end

function Lookup.npc_footprint(npc_defs, kind, overrides)
    local def = Lookup.npc_spec(npc_defs, kind) or {}
    overrides = overrides or {}

    return overrides.tiles_w or def.tiles_w or 1,
        overrides.tiles_d or def.tiles_d or 1,
        overrides.tiles_h or def.tiles_h or 1
end

function Lookup.npc_draw_offset(npc_defs, kind, overrides)
    local def = Lookup.npc_spec(npc_defs, kind) or {}
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

function Lookup.npc_catalog(npc_defs)
    return npc_defs or {}
end

return Lookup
