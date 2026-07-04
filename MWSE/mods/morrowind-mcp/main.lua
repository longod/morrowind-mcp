local function Test()
    -- commandline and environment variables are not available in MWSE with MO2
    -- so we use a file to indicate that we should exit after running tests
    local settings = require("morrowind-mcp.settings")
    local exitAfterFlagPath = settings.modDir .. ".exit-after-tests"
    local exitAfter = lfs.attributes(exitAfterFlagPath, "mode") == "file"
    local dir = settings.modDir .. "tests"
    for file in lfs.dir(dir) do
        if (string.endswith(file:lower(), ".lua")) then
            local test = dofile(dir .. "\\" .. file)
            if test then
                pcall(test.Test)
            end
        end
    end
    if exitAfter then
        os.exit(0)
    end
end

local config = require("morrowind-mcp.config")

if config.development.unitTest then
    Test()
end

---@return string?
local function GetNewestSave()

    local newestSave = nil
    local newestTimestamp = 0
    for file in lfs.dir("saves") do
        if (string.endswith(file, ".ess")) then
            -- Check to see if the file is newer than our current newest file.
            local lastModified = lfs.attributes("saves/" .. file, "modification")
            if (lastModified > newestTimestamp) then
                newestSave = file
                newestTimestamp = lastModified;
            end
        end
    end

    if (newestSave ~= nil) then
        return string.sub(newestSave, 1, -5)
    end
    return nil
end

--- @param e enterFrameEventData
local function SkipMainMenu(e)
    if not tes3.onMainMenu() then
        return
    end
    if not e.menuMode then
        return
    end

    -- jump into game.
    -- only first time or player died? every time is needed force quit.
    event.unregister(tes3.event.enterFrame, SkipMainMenu) -- once

    local save = GetNewestSave()
    if save then
        tes3.loadGame(save)
    else
        tes3.newGame()
    end
end

local server = require("morrowind-mcp.server.http_server").new({
    hostname = config.server.address,
    port = config.server.port,
})

---@param e initializedEventData
local function OnInitialized(e)
    if config.autoplay.skipMainMenu then
        event.register(tes3.event.enterFrame, SkipMainMenu)
    end

    server:Start()
end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")





-- missing annotations

---@class tes3scriptVariables
---@class tes3keyframeDefinition
---@class tes3mapController
---@class HINSTANCE
---@class HWND
