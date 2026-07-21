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


-- test events
local maxInlineFields = 8

---@param value any
---@param field string
---@return any
local function SafeGetField(value, field)
    local ok, result = pcall(function()
        return value[field]
    end)
    if not ok then
        return nil
    end
    return result
end

---@param value any
---@return any, any
local function GetIdAndName(value)
    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "userdata" then
        return nil, nil
    end
    return SafeGetField(value, "id"), SafeGetField(value, "name")
end

---@param value any
---@param depth integer
---@param visited table<any, boolean>
---@return string
local function FormatTraceValue(value, depth, visited)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    end
    if valueType == "boolean" or valueType == "number" then
        return tostring(value)
    end
    if valueType == "string" then
        return string.format("%q", value)
    end

    local id, name = GetIdAndName(value)
    if id ~= nil or name ~= nil then
        return string.format("{id=%s, name=%s}", tostring(id), tostring(name))
    end

    if valueType == "userdata" then
        return "<userdata>"
    end

    if valueType ~= "table" then
        return string.format("<%s>", valueType)
    end

    if visited[value] then
        return "<cycle>"
    end

    if depth >= 1 then
        return "{...}"
    end

    visited[value] = true
    local parts = {}
    local fieldCount = 0
    for key, innerValue in pairs(value) do
        fieldCount = fieldCount + 1
        if fieldCount > maxInlineFields then
            parts[fieldCount] = "..."
            break
        end
        local keyText = tostring(key)
        parts[fieldCount] = string.format("%s=%s", keyText, FormatTraceValue(innerValue, depth + 1, visited))
    end
    visited[value] = nil

    if table.size(parts) == 0 then
        return "{}"
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

---@param e table
---@return string
local function FormatEventData(e)
    local parts = {}
    local fieldCount = 0
    for key, value in pairs(e) do
        fieldCount = fieldCount + 1
        if fieldCount > maxInlineFields then
            parts[fieldCount] = "..."
            break
        end
        parts[fieldCount] = string.format("e.%s=%s", tostring(key), FormatTraceValue(value, 0, {}))
    end

    if table.size(parts) == 0 then
        return "e={}"
    end
    return table.concat(parts, ", ")
end

local function RegisterTestEvents()
    local logger = require("morrowind-mcp.logger").Get({ moduleName = "test_event" })

    ---@param e addSoundEventData
    local function addSoundCallback(e)
        logger:trace("addSound %s", FormatEventData(e))
    end
    event.register(tes3.event.addSound, addSoundCallback)

    ---@param e addTempSoundEventData
    local function addTempSoundCallback(e)
        logger:trace("addTempSound %s", FormatEventData(e))
    end
    event.register(tes3.event.addTempSound, addTempSoundCallback)

    ---@param e attackHitEventData
    local function attackHitCallback(e)
        logger:trace("attackHit %s", FormatEventData(e))
    end
    event.register(tes3.event.attackHit, attackHitCallback)

    ---@param e barterOfferEventData
    local function barterOfferCallback(e)
        logger:trace("barterOffer %s", FormatEventData(e))
    end
    event.register(tes3.event.barterOffer, barterOfferCallback)

    ---@param e bookGetTextEventData
    local function bookGetTextCallback(e)
        logger:trace("bookGetText %s", FormatEventData(e))
    end
    event.register(tes3.event.bookGetText, bookGetTextCallback)

    ---@param e charGenFinishedEventData
    local function charGenFinishedCallback(e)
        logger:trace("charGenFinished %s", FormatEventData(e))
    end
    event.register(tes3.event.charGenFinished, charGenFinishedCallback)

    ---@param e combatStartedEventData
    local function combatStartedCallback(e)
        logger:trace("combatStarted %s", FormatEventData(e))
    end
    event.register(tes3.event.combatStarted, combatStartedCallback)

    ---@param e combatStoppedEventData
    local function combatStoppedCallback(e)
        logger:trace("combatStopped %s", FormatEventData(e))
    end
    event.register(tes3.event.combatStopped, combatStoppedCallback)

    ---@param e damagedEventData
    local function damagedCallback(e)
        logger:trace("damaged %s", FormatEventData(e))
    end
    event.register(tes3.event.damaged, damagedCallback)

    ---@param e damagedHandToHandEventData
    local function damagedHandToHandCallback(e)
        logger:trace("damagedHandToHand %s", FormatEventData(e))
    end
    event.register(tes3.event.damagedHandToHand, damagedHandToHandCallback)

    ---@param e deathEventData
    local function deathCallback(e)
        logger:trace("death %s", FormatEventData(e))
    end
    event.register(tes3.event.death, deathCallback)

    ---@param e determinedActionEventData
    local function determinedActionCallback(e)
        logger:trace("determinedAction %s", FormatEventData(e))
    end
    event.register(tes3.event.determinedAction, determinedActionCallback)

    ---@param e dialogueFilteredEventData
    local function dialogueFilteredCallback(e)
        logger:trace("dialogueFiltered %s", FormatEventData(e))
    end
    event.register(tes3.event.dialogueFiltered, dialogueFilteredCallback)

    ---@param e itemDroppedEventData
    local function itemDroppedCallback(e)
        logger:trace("itemDropped %s", FormatEventData(e))
    end
    event.register(tes3.event.itemDropped, itemDroppedCallback)

    ---@param e itemTileUpdatedEventData
    local function itemTileUpdatedCallback(e)
        logger:trace("itemTileUpdated %s", FormatEventData(e))
    end
    event.register(tes3.event.itemTileUpdated, itemTileUpdatedCallback)

    ---@param e pickpocketEventData
    local function pickpocketCallback(e)
        logger:trace("pickpocket %s", FormatEventData(e))
    end
    event.register(tes3.event.pickpocket, pickpocketCallback)

    ---@param e savedEventData
    local function savedCallback(e)
        logger:trace("saved %s", FormatEventData(e))
    end
    event.register(tes3.event.saved, savedCallback)

    ---@param e topicAddedEventData
    local function topicAddedCallback(e)
        logger:trace("topicAdded %s", FormatEventData(e))
    end
    event.register(tes3.event.topicAdded, topicAddedCallback)

    ---@param e topicsListUpdatedEventData
    local function topicsListUpdatedCallback(e)
        logger:trace("topicsListUpdated %s", FormatEventData(e))
    end
    event.register(tes3.event.topicsListUpdated, topicsListUpdatedCallback)

    ---@param e uiActivatedEventData
    local function uiActivatedCallback(e)
        logger:trace("uiActivated %s", FormatEventData(e))
    end
    event.register(tes3.event.uiActivated, uiActivatedCallback)

    ---@param e uiObjectTooltipEventData
    local function uiObjectTooltipCallback(e)
        logger:trace("uiObjectTooltip %s", FormatEventData(e))
    end
    event.register(tes3.event.uiObjectTooltip, uiObjectTooltipCallback)

    ---@param e weatherTransitionStartedEventData
    local function weatherTransitionStartedCallback(e)
        logger:trace("weatherTransitionStarted %s", FormatEventData(e))
    end
    event.register(tes3.event.weatherTransitionStarted, weatherTransitionStartedCallback)

    ---@param e weatherTransitionFinishedEventData
    local function weatherTransitionFinishedCallback(e)
        logger:trace("weatherTransitionFinished %s", FormatEventData(e))
    end
    event.register(tes3.event.weatherTransitionFinished, weatherTransitionFinishedCallback)
end

RegisterTestEvents()

-- missing annotations

---@class tes3scriptVariables
---@class tes3keyframeDefinition
---@class tes3mapController
---@class HINSTANCE
---@class HWND
