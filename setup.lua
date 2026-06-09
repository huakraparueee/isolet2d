--[[
  Iso config — build from scene + get/set for iso modules
]]

local M = {}

local cfg

function M.set(iso_cfg)
    cfg = iso_cfg
end

function M.get()
    if not cfg then
        error("iso: call Iso.setup first")
    end

    return cfg
end

function M.build(raw)
    return {
        design_width = raw.design_width,
        design_height = raw.design_height,
        grid_origin_x = raw.grid_origin_x,
        grid_origin_y = raw.grid_origin_y,
        map_offset_y = raw.map_offset_y or 0,
        tile_size = raw.tile_size,
        iso_x_ratio = raw.iso_x_ratio,
        iso_y_ratio = raw.iso_y_ratio,
        iso_eh_ratio = raw.iso_eh_ratio,
        terrain_mats = raw.terrain_mats,
        structures = raw.structures,
        npcs = raw.npcs,
        projectiles = raw.projectiles,
        terrain_stack_top = raw.terrain_stack_top,
        terrain_stack_fill = raw.terrain_stack_fill,
        debug_draw_walkable = raw.debug_draw_walkable == true,
    }
end

return M
