--[[
  Structure sprites — load + draw (called from terrain draw path)
]]

local Setup = require("setup")
local Lookup = require("lookup")
local Footprint = require("footprint")
local IsoGround = require("ground")

local images = {}

local function spec(kind)
    return Setup.get().structures[kind]
end

local Structure = {}

function Structure.is_piece(piece)
    return piece.structure ~= nil
end

function Structure.load()
    for kind, def in pairs(Setup.get().structures) do
        if def.path and not images[kind] then
            local image = love.graphics.newImage(def.path)
            local iw, ih = image:getWidth(), image:getHeight()

            if iw ~= def.w or ih ~= def.h then
                error(
                    string.format(
                        "%s must be %dx%d, got %dx%d",
                        def.path,
                        def.w,
                        def.h,
                        iw,
                        ih
                    )
                )
            end

            image:setFilter("nearest", "nearest")
            images[kind] = image
        end
    end
end

function Structure.draw(piece, lg, layout, alpha, z_at)
    local kind = piece.structure
    local def = spec(kind)
    local image = images[kind]

    if not def or not image then
        return
    end

    local scale = layout.scale or 1
    alpha = alpha or 1
    local w, d = Lookup.structure_tile_span(
        Setup.get().structures,
        piece.structure
    )
    local feet_x, feet_y = Footprint.feet_screen(layout, {
        ox = piece.tile_x,
        oy = piece.tile_y,
        tiles_w = w,
        tiles_d = d,
        tile_z = piece.tile_z,
        z_at = z_at,
    })

    lg.setColor(1, 1, 1, alpha)
    lg.draw(
        image,
        IsoGround.snap_px(feet_x),
        IsoGround.snap_px(feet_y),
        0,
        scale,
        scale,
        def.w * 0.5,
        def.h
    )
end

return Structure
