local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local originalEvent = event
    local originalTes3 = tes3
    local originalTimer = timer
    local originalTestContext = package.loaded["morrowind-mcp.util.test_context"]
    local originalSettings = package.loaded["morrowind-mcp.settings"]
    local integration = require("morrowind-mcp.util.server_integration")
    local originalWriteStatus = integration.WriteStatus
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
        afterEach = function()
            event = originalEvent
            tes3 = originalTes3
            timer = originalTimer
            package.loaded["morrowind-mcp.util.test_context"] = originalTestContext
            package.loaded["morrowind-mcp.settings"] = originalSettings
            rawset(integration, "WriteStatus", originalWriteStatus)
        end,
    })

    unitwind:start("morrowind-mcp.util.server_integration")
    unitwind:test("Accepts the requested saved-game loaded event", function()
        local matches, details = integration.ValidateLoadedSave("Initial0000", {
            filename = "initial0000",
            quickload = false,
            newGame = false,
            claim = false,
        })
        unitwind:expect(matches).toBe(true)
        unitwind:expect(details.loaded_filename).toBe("initial0000")
    end)

    unitwind:test("Rejects a different saved-game loaded event", function()
        local matches = integration.ValidateLoadedSave("initial0000", {
            filename = "other-save",
            quickload = false,
            newGame = false,
            claim = false,
        })
        unitwind:expect(matches).toBe(false)
    end)

    unitwind:test("Rejects quickload and quiksave loaded events", function()
        local quickload = integration.ValidateLoadedSave("initial0000", {
            filename = "initial0000",
            quickload = true,
            newGame = false,
            claim = false,
        })
        local quiksave = integration.ValidateLoadedSave("quiksave", {
            filename = "quiksave",
            quickload = false,
            newGame = false,
            claim = false,
        })
        unitwind:expect(quickload).toBe(false)
        unitwind:expect(quiksave).toBe(false)
    end)

    unitwind:test("Requests a configured save only once from the main menu", function()
        unitwind:expect(integration.CanRequestLoad(false, true, true)).toBe(true)
        unitwind:expect(integration.CanRequestLoad(true, true, true)).toBe(false)
        unitwind:expect(integration.CanRequestLoad(false, false, true)).toBe(false)
        unitwind:expect(integration.CanRequestLoad(false, true, false)).toBe(false)
    end)

    unitwind:test("Registers only enterFrame for a main-menu integration", function()
        local registrations = {}
        local unregistrations = {}
        event = {
            register = function(eventName, callback) registrations[#registrations + 1] = { eventName, callback } end,
            unregister = function(eventName, callback) unregistrations[#unregistrations + 1] = { eventName, callback } end,
        }
        tes3 = { event = { loaded = "loaded", enterFrame = "enterFrame" } }
        package.loaded["morrowind-mcp.util.test_context"] = { Load = function() return { serverIntegration = { runId = "run", saveName = nil } } end }
        package.loaded["morrowind-mcp.settings"] = { modDataDir = "tests\\" }
        rawset(integration, "WriteStatus", function() end)

        integration.Register()
        integration.Register()

        unitwind:expect(#registrations).toBe(2)
        unitwind:expect(registrations[1][1]).toBe("enterFrame")
        unitwind:expect(registrations[2][1]).toBe("enterFrame")
        unitwind:expect(#unregistrations).toBe(4)
    end)

    unitwind:test("Unregisters enterFrame after load request and loaded after completion", function()
        local unregistrations = {}
        local loadedSave = nil
        local states = {}
        event = {
            register = function() end,
            unregister = function(eventName, callback) unregistrations[#unregistrations + 1] = { eventName, callback } end,
        }
        tes3 = {
            event = { loaded = "loaded", enterFrame = "enterFrame" },
            onMainMenu = function() return true end,
            loadGame = function(saveName) loadedSave = saveName end,
        }
        timer = { frame = { delayOneFrame = function(callback) callback() end } }
        package.loaded["morrowind-mcp.util.test_context"] = { Load = function() return { serverIntegration = { runId = "run", saveName = "initial0000" } } end }
        package.loaded["morrowind-mcp.settings"] = { modDataDir = "tests\\" }
        rawset(integration, "WriteStatus", function(state) states[#states + 1] = state end)

        integration.Register()
        integration.OnEnterFrame({ menuMode = true, claim = false, delta = 0, timestamp = 0 })
        integration.OnLoaded({ filename = "initial0000", quickload = false, newGame = false, claim = false })

        unitwind:expect(loadedSave).toBe("initial0000")
        unitwind:expect(states[2]).toBe("loading")
        unitwind:expect(states[3]).toBe("ready")
        unitwind:expect(unregistrations[3][1]).toBe("enterFrame")
        unitwind:expect(unregistrations[4][1]).toBe("loaded")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
