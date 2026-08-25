local this = {}

local statusPath = nil
local integration = nil
local loadRequested = false
local finished = false


---Writes retained integration state through the same logical VFS directory as the test context.
---@param state string
---@param extra table?
function this.WriteStatus(state, extra)
    if integration == nil or statusPath == nil then
        return
    end
    local document = {
        run_id = integration.runId,
        state = state,
        save_name = integration.saveName,
    }
    if extra then
        for key, value in pairs(extra) do
            document[key] = value
        end
    end
    local json = require("dkjson")
    local file, errorMessage = io.open(statusPath, "w")
    if not file then
        local logger = require("morrowind-mcp.logger").Get({ moduleName = "server_integration" })
        logger:error("Failed to write integration status: %s", errorMessage or "unknown error")
        return
    end
    file:write(json.encode(document, { indent = true }))
    file:write("\n")
    file:close()
end

---Returns whether a loaded event matches the requested non-quicksave save stem.
---@param saveName string
---@param e loadedEventData
---@return boolean
---@return table
function this.ValidateLoadedSave(saveName, e)
    local actual = type(e.filename) == "string" and string.lower(e.filename) or ""
    local matches = not e.quickload and actual ~= "quicksave" and actual ~= "quiksave" and actual == string.lower(saveName)
    return matches, {
        loaded_filename = e.filename,
        quickload = e.quickload == true,
        new_game = e.newGame == true,
    }
end

---Returns whether the main-menu frame may request the configured save exactly once.
---@param alreadyRequested boolean
---@param onMainMenu boolean
---@param menuMode boolean
---@return boolean
function this.CanRequestLoad(alreadyRequested, onMainMenu, menuMode)
    return not alreadyRequested and onMainMenu and menuMode
end

---Completes a saved-game status and prevents later loaded events from overwriting it.
---@param state string
---@param extra table?
function this.FinishLoaded(state, extra)
    if finished then
        return
    end
    finished = true
    this.WriteStatus(state, extra)
    event.unregister(tes3.event.loaded, this.OnLoaded)
end

---Completes readiness after MWSE has finished its loaded-event callbacks for this frame.
---@param e loadedEventData
function this.OnLoaded(e)
    if finished or integration == nil or integration.saveName == nil then
        return
    end

    local matches, details = this.ValidateLoadedSave(integration.saveName, e)
    if not matches then
        details.error = "Loaded save did not match the requested non-quicksave save."
        this.FinishLoaded("failed", details)
        return
    end

    timer.frame.delayOneFrame(function()
        this.FinishLoaded("ready", details)
    end)
end

---Requests the configured save only once after the main menu is ready to accept a load.
---@param e enterFrameEventData
function this.OnEnterFrame(e)
    if finished or integration == nil or not this.CanRequestLoad(loadRequested, tes3.onMainMenu(), e.menuMode) then
        return
    end
    if integration.saveName == nil then
        finished = true
        this.WriteStatus("ready", { main_menu = true })
        event.unregister(tes3.event.enterFrame, this.OnEnterFrame)
        return
    end

    loadRequested = true
    this.WriteStatus("loading")
    event.unregister(tes3.event.enterFrame, this.OnEnterFrame)
    tes3.loadGame(integration.saveName)
end

---Registers the private test-only load controller when the shared context requests it.
function this.Register()
    local testContext = require("morrowind-mcp.util.test_context").Load()
    if testContext == nil or testContext.serverIntegration == nil then
        return
    end

    event.unregister(tes3.event.loaded, this.OnLoaded)
    event.unregister(tes3.event.enterFrame, this.OnEnterFrame)
    integration = testContext.serverIntegration
    loadRequested = false
    finished = false
    local settings = require("morrowind-mcp.settings")
    statusPath = settings.modDataDir .. "tests\\server-integration-status.json"
    this.WriteStatus("pending")
    if integration ~= nil and integration.saveName ~= nil then
        event.register(tes3.event.loaded, this.OnLoaded)
    end
    event.register(tes3.event.enterFrame, this.OnEnterFrame)
end

return this
