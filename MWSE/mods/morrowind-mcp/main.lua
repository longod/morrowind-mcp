local config = require("morrowind-mcp.config")
local disclaimer = require("morrowind-mcp.disclaimer")
local settings = require("morrowind-mcp.settings")
local ui_action = require("morrowind-mcp.util.ui_action")
local input_action = require("morrowind-mcp.util.input_action")
local unittest = require("morrowind-mcp.unittest")

local function HasAutomatedServerTestFlag()
    local flagPath = settings.modDir .. ".server-test-running"
    return lfs.attributes(flagPath, "mode") == "file"
end

if config.development.unitTest and not HasAutomatedServerTestFlag() then
    unittest.Run()
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

---@param e enterFrameEventData
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

local function RegisterSkipMainMenu()
    if config.autoplay.skipMainMenu and not HasAutomatedServerTestFlag() then
        event.register(tes3.event.enterFrame, SkipMainMenu)
    end
end

local server = nil ---@type MCP.IServer?

local function StartServer()
    if server ~= nil then
        return
    end

    server = require("morrowind-mcp.server.http_server").new({
        hostname = config.server.address,
        port = config.server.port,
    })
    server:Start()
end

local function StartRuntime()
    input_action.RegisterEventHandlers()
    ui_action.RegisterEventHandlers()
    RegisterSkipMainMenu()
    StartServer()
end

local function AcceptDisclaimer()
    config.disclaimer = disclaimer.version
    mwse.saveConfig(settings.configPath, config)
    local logger = require("morrowind-mcp.logger").Get({ moduleName = "disclaimer" })
    logger:info("Disclaimer accepted. Starting MCP server.")
    StartRuntime()
end

local function DeclineDisclaimer()
    local logger = require("morrowind-mcp.logger").Get({ moduleName = "disclaimer" })
    logger:warn("Disclaimer declined. MCP server will remain disabled for this session.")
end

local function ShowDisclaimerDialog()
    timer.frame.delayOneFrame(function()
        tes3ui.showMessageMenu({
            header = disclaimer.header,
            message = disclaimer.text,
            buttons = {
                {
                    text = "Accept and Start Server",
                    callback = AcceptDisclaimer,
                },
                {
                    text = "Cancel",
                    callback = DeclineDisclaimer,
                },
            },
        })
    end)
end

---@param e initializedEventData
local function OnInitialized(e)
    local firstTime = config.disclaimer < disclaimer.version
    if firstTime then
        if HasAutomatedServerTestFlag() then
            local logger = require("morrowind-mcp.logger").Get({ moduleName = "disclaimer" })
            logger:debug("Disclaimer auto-accepted for automated server test session.")
            StartRuntime()
            return
        end

        ShowDisclaimerDialog()
        return
    end

    StartRuntime()
end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")


-- test runtime moved to morrowind-mcp.unittest
