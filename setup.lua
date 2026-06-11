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
        error("iso: call Iso.init first")
    end

    return cfg
end

function M.build(raw)
    raw = raw or {}

    return {
        design_width = raw.design_width or 1280,
        design_height = raw.design_height or 720,
        grid_origin_x = raw.grid_origin_x or 0,
        grid_origin_y = raw.grid_origin_y or 0,
        map_offset_y = raw.map_offset_y or 0,
        tile_size = raw.tile_size or 64,
        iso_x_ratio = raw.iso_x_ratio or 0.5,
        iso_y_ratio = raw.iso_y_ratio or 0.25,
        iso_eh_ratio = raw.iso_eh_ratio or 0.5,
        terrain_mats = raw.terrain_mats or {},
        structures = raw.structures or {},
        npcs = raw.npcs or {},
        projectiles = raw.projectiles or {},
        debug_draw_map = raw.debug_draw_map == true,
    }
end

return M
