local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local tool = require("morrowind-mcp.tools.player_navigate")

    unitwind:start("morrowind-mcp.tools.player_navigate")

    unitwind:test("cancel_navigation does not require a destination and invokes the cancel service", function()
        local instance = tool.new()
        local arguments = { action = "cancel_navigation" }
        local validation = instance:Validate({ name = "mw-player-navigate", arguments = arguments })
        local cancelled = false
        local result = instance:Execute(arguments, {
            NotifyProgress = function() return false end,
            NavigatePlayer = function() return false, "unused" end,
            CancelPlayerNavigation = function()
                cancelled = true
                return true
            end,
            HasActivePlayerNavigation = function() return true end,
        })

        unitwind:expect(validation.valid).toBe(true)
        unitwind:expect(cancelled).toBe(true)
        unitwind:expect(result.isError).toBe(false)
        unitwind:expect(result.content[1].text).toBe("Player navigation cancelled.")
        unitwind:expect(result.structuredContent ~= nil).toBe(true)
    end)

    unitwind:test("cancel_navigation explains when no navigation is active", function()
        local instance = tool.new()
        local canExecute, unavailable = instance:CanExecute({ action = "cancel_navigation" }, {
            NotifyProgress = function() return false end,
            NavigatePlayer = function() return false, "unused" end,
            CancelPlayerNavigation = function() return false end,
            HasActivePlayerNavigation = function() return false end,
        })

        unitwind:expect(canExecute).toBe(false)
        unitwind:expect(unavailable ~= nil).toBe(true)
        if unavailable then
            unitwind:expect(unavailable.reason).toBe("no_active_navigation")
            unitwind:expect(unavailable.guidance).toBe("There is no active navigation to cancel.")
        end
    end)

    unitwind:test("cancel_navigation remains available when the player is unavailable", function()
        unitwind:mock(tes3, "onMainMenu", function() return true end)
        unitwind:mock(tes3, "player", nil)
        local instance = tool.new()
        local canExecute = instance:CanExecute({ action = "cancel_navigation" }, {
            NotifyProgress = function() return false end,
            NavigatePlayer = function() return false, "unused" end,
            CancelPlayerNavigation = function() return false end,
            HasActivePlayerNavigation = function() return true end,
        })

        unitwind:expect(canExecute).toBe(true)
    end)

    unitwind:test("navigate requires all destination coordinates", function()
        local instance = tool.new()
        local validation = instance:Validate({
            name = "mw-player-navigate",
            arguments = { action = "navigate", position_x = 1 },
        })

        unitwind:expect(validation.valid).toBe(false)
        unitwind:expect(table.size(validation.errors)).toBe(2)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
