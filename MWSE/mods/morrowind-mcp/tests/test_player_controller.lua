local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local controller = require("morrowind-mcp.util.player_controller")
    local inputAction = require("morrowind-mcp.util.input_action")

    unitwind:start("morrowind-mcp.util.player_controller")

    unitwind:test("StartForward owns one keyboard press and Release frees it", function()
        local pushes = 0
        local releases = 0
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(inputAction, "KeyboardPush", function() pushes = pushes + 1 return true end)
        unitwind:mock(inputAction, "KeyboardRelease", function() releases = releases + 1 return true end)

        local instance = controller.new()
        unitwind:expect(instance:StartForward()).toBe(true)
        unitwind:expect(instance:StartForward()).toBe(true)
        instance:Release()
        instance:Release()

        unitwind:expect(pushes).toBe(1)
        unitwind:expect(releases).toBe(1)
        unitwind:expect(instance.isForwarding).toBe(false)
    end)

    unitwind:test("LookAtHorizontal changes yaw without requiring vertical rotation", function()
        local player = { position = { x = 0, y = 0, z = 0 }, facing = 0 }
        unitwind:mock(tes3, "player", player)
        local instance = controller.new()

        unitwind:expect(instance:LookAtHorizontal({ x = 10, y = 0, z = 100 })).toBe(true)
        unitwind:expect(player.facing).toBe(math.pi / 2)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
