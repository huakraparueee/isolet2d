local ISOLET_MODULES = {
    "isolet2d",
    "stack",
    "tile",
    "events",
    "setup",
    "terrain",
    "npc",
    "structure",
    "projectile",
    "camera",
    "path",
    "placement",
    "anim8",
}

local M = {}

function M.registerModules (dir)
    love.filesystem.setRequirePath(
        love.filesystem.getRequirePath() .. ";" .. dir .. "/?.lua"
    )
end

function M.clearModules()
    for _, name in ipairs(ISOLET_MODULES) do
        package.loaded[name] = nil
    end
end

return M