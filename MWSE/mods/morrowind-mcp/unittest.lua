local this = {}

local testlog = require("morrowind-mcp.logger").Get({ moduleName = "test_event" })
local maxInlineFields = 8

---@param targetSet table<string, boolean>?
local function LogTestTargets(targetSet)
    if targetSet == nil then
        testlog:info("Planned unit test targets: all test files")
        return
    end

    local targetList = {}
    for target in pairs(targetSet) do
        table.insert(targetList, target)
    end
    table.sort(targetList)

    testlog:info("Planned unit test targets: %s", table.concat(targetList, ", "))
end

---@param line string
---@return string?
local function NormalizeTestTarget(line)
    local target = line:gsub("^%s+", ""):gsub("%s+$", "")
    if target == "" or target:sub(1, 1) == "#" then
        return nil
    end

    target = target:match("[^/\\]+$") or target
    target = target:lower()
    if not string.endswith(target, ".lua") then
        target = target .. ".lua"
    end

    return target
end

---@param sentinelPath string
---@return boolean exists
---@return table<string, boolean>?
local function LoadTestTargets(sentinelPath)
    local file = io.open(sentinelPath, "r")
    if not file then
        return false, nil
    end

    local targetSet = {}
    for line in file:lines() do
        local target = NormalizeTestTarget(line)
        if target ~= nil then
            targetSet[target] = true
        end
    end
    file:close()

    if table.size(targetSet) == 0 then
        return true, nil
    end

    return true, targetSet
end

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
    ---@param e addSoundEventData
    local function addSoundCallback(e)
        testlog:trace("addSound %s", FormatEventData(e))
    end
    event.register(tes3.event.addSound, addSoundCallback)

    ---@param e addTempSoundEventData
    local function addTempSoundCallback(e)
        testlog:trace("addTempSound %s", FormatEventData(e))
    end
    event.register(tes3.event.addTempSound, addTempSoundCallback)

    ---@param e attackHitEventData
    local function attackHitCallback(e)
        testlog:trace("attackHit %s", FormatEventData(e))
    end
    event.register(tes3.event.attackHit, attackHitCallback)

    ---@param e barterOfferEventData
    local function barterOfferCallback(e)
        testlog:trace("barterOffer %s", FormatEventData(e))
    end
    event.register(tes3.event.barterOffer, barterOfferCallback)

    ---@param e bookGetTextEventData
    local function bookGetTextCallback(e)
        testlog:trace("bookGetText %s", FormatEventData(e))
    end
    event.register(tes3.event.bookGetText, bookGetTextCallback)

    ---@param e charGenFinishedEventData
    local function charGenFinishedCallback(e)
        testlog:trace("charGenFinished %s", FormatEventData(e))
    end
    event.register(tes3.event.charGenFinished, charGenFinishedCallback)

    ---@param e combatStartedEventData
    local function combatStartedCallback(e)
        testlog:trace("combatStarted %s", FormatEventData(e))
    end
    event.register(tes3.event.combatStarted, combatStartedCallback)

    ---@param e combatStoppedEventData
    local function combatStoppedCallback(e)
        testlog:trace("combatStopped %s", FormatEventData(e))
    end
    event.register(tes3.event.combatStopped, combatStoppedCallback)

    ---@param e damagedEventData
    local function damagedCallback(e)
        testlog:trace("damaged %s", FormatEventData(e))
    end
    event.register(tes3.event.damaged, damagedCallback)

    ---@param e damagedHandToHandEventData
    local function damagedHandToHandCallback(e)
        testlog:trace("damagedHandToHand %s", FormatEventData(e))
    end
    event.register(tes3.event.damagedHandToHand, damagedHandToHandCallback)

    ---@param e deathEventData
    local function deathCallback(e)
        testlog:trace("death %s", FormatEventData(e))
    end
    event.register(tes3.event.death, deathCallback)

    ---@param e determinedActionEventData
    local function determinedActionCallback(e)
        testlog:trace("determinedAction %s", FormatEventData(e))
    end
    event.register(tes3.event.determinedAction, determinedActionCallback)

    ---@param e dialogueFilteredEventData
    local function dialogueFilteredCallback(e)
        testlog:trace("dialogueFiltered %s", FormatEventData(e))
    end
    event.register(tes3.event.dialogueFiltered, dialogueFilteredCallback)

    ---@param e itemDroppedEventData
    local function itemDroppedCallback(e)
        testlog:trace("itemDropped %s", FormatEventData(e))
    end
    event.register(tes3.event.itemDropped, itemDroppedCallback)

    ---@param e itemTileUpdatedEventData
    local function itemTileUpdatedCallback(e)
        testlog:trace("itemTileUpdated %s", FormatEventData(e))
    end
    event.register(tes3.event.itemTileUpdated, itemTileUpdatedCallback)

    ---@param e pickpocketEventData
    local function pickpocketCallback(e)
        testlog:trace("pickpocket %s", FormatEventData(e))
    end
    event.register(tes3.event.pickpocket, pickpocketCallback)

    ---@param e savedEventData
    local function savedCallback(e)
        testlog:trace("saved %s", FormatEventData(e))
    end
    event.register(tes3.event.saved, savedCallback)

    ---@param e topicAddedEventData
    local function topicAddedCallback(e)
        testlog:trace("topicAdded %s", FormatEventData(e))
    end
    event.register(tes3.event.topicAdded, topicAddedCallback)

    ---@param e topicsListUpdatedEventData
    local function topicsListUpdatedCallback(e)
        testlog:trace("topicsListUpdated %s", FormatEventData(e))
    end
    event.register(tes3.event.topicsListUpdated, topicsListUpdatedCallback)

    ---@param e uiActivatedEventData
    local function uiActivatedCallback(e)
        testlog:trace("uiActivated %s", FormatEventData(e))
    end
    event.register(tes3.event.uiActivated, uiActivatedCallback)

    ---@param e uiObjectTooltipEventData
    local function uiObjectTooltipCallback(e)
        testlog:trace("uiObjectTooltip %s", FormatEventData(e))
    end
    event.register(tes3.event.uiObjectTooltip, uiObjectTooltipCallback)

    ---@param e weatherTransitionStartedEventData
    local function weatherTransitionStartedCallback(e)
        testlog:trace("weatherTransitionStarted %s", FormatEventData(e))
    end
    event.register(tes3.event.weatherTransitionStarted, weatherTransitionStartedCallback)

    ---@param e weatherTransitionFinishedEventData
    local function weatherTransitionFinishedCallback(e)
        testlog:trace("weatherTransitionFinished %s", FormatEventData(e))
    end
    event.register(tes3.event.weatherTransitionFinished, weatherTransitionFinishedCallback)
end

local function HasAutomatedServerTestFlag()
    local settings = require("morrowind-mcp.settings")
    local flagPath = settings.modDir .. ".server-test-running"
    return lfs.attributes(flagPath, "mode") == "file"
end

function this.Run()
    if HasAutomatedServerTestFlag() then
        return
    end

    local settings = require("morrowind-mcp.settings")
    local sentinelPath = settings.modDir .. ".unit-test-targets"
    local hasTestSentinel, testTargets = LoadTestTargets(sentinelPath)

    -- Log the planned targets before any test module starts executing.
    LogTestTargets(testTargets)

    -- Suppress logging for tests to avoid cluttering the test output.
    if hasTestSentinel then
        local config = require("morrowind-mcp.config")
        config.development.logLevel = mwse.logLevel.info
        config.development.logToConsole = false
        local loggerFactory = require("morrowind-mcp.logger")
        loggerFactory.ApplyConfigToAll({ level = config.development.logLevel, logToConsole = config.development.logToConsole })
    end

    local dir = settings.modDir .. "tests"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local normalizedFile = file:lower()
            -- An empty sentinel means run the full suite; otherwise only run the listed files.
            if testTargets == nil or testTargets[normalizedFile] then
                local test = dofile(dir .. "\\" .. file)
                if test then
                    pcall(test.Test)
                end
            end
        end
    end

    if hasTestSentinel then
        os.exit(0)
    end
end

RegisterTestEvents()

return this
