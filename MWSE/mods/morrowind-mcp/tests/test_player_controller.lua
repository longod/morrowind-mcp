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

    unitwind:test("SetLookAngles applies degrees and converts upward pitch for MWSE", function()
        local player = { position = { x = 0, y = 0, z = 0 }, facing = 0 }
        local animationController = {}
        unitwind:mock(tes3, "player", player)
        unitwind:mock(tes3, "mobilePlayer", { animationController = animationController })

        local instance = controller.new()
        local ok, yaw, pitch = instance:SetLookAngles(90, 45)

        unitwind:expect(ok).toBe(true)
        unitwind:expect(yaw).toBe(90)
        unitwind:expect(pitch).toBe(45)
        unitwind:expect(player.facing).toBe(math.pi / 2)
        unitwind:expect(math.abs(animationController.verticalRotation:toEulerXYZ().x + math.pi / 4) < 0.001).toBe(true)
    end)

    unitwind:test("SetLookAngles normalizes yaw and clamps pitch", function()
        local player = { position = { x = 0, y = 0, z = 0 }, facing = 0 }
        local animationController = {}
        unitwind:mock(tes3, "player", player)
        unitwind:mock(tes3, "mobilePlayer", { animationController = animationController })

        local instance = controller.new()
        local ok, yaw, pitch = instance:SetLookAngles(270, 120)

        unitwind:expect(ok).toBe(true)
        unitwind:expect(yaw).toBe(-90)
        unitwind:expect(pitch).toBe(89)
        unitwind:expect(math.abs(animationController.verticalRotation:toEulerXYZ().x + math.rad(89)) < 0.001).toBe(true)
    end)

    unitwind:test("LookAtPoint calculates an upward pitch from the player eye position", function()
        local player = { position = { x = 0, y = 0, z = 0 }, facing = 0 }
        unitwind:mock(tes3, "player", player)
        unitwind:mock(tes3, "mobilePlayer", { animationController = {} })
        unitwind:mock(tes3, "getPlayerEyePosition", function() return { x = 0, y = 0, z = 10 } end)

        local instance = controller.new()
        local ok, yaw, pitch = instance:LookAtPoint({ x = 0, y = 10, z = 20 })

        unitwind:expect(ok).toBe(true)
        unitwind:expect(yaw).toBe(0)
        unitwind:expect(pitch).toBe(45)
    end)

    unitwind:test("LookAtPoint rejects the current player eye position", function()
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, facing = 0 })
        unitwind:mock(tes3, "mobilePlayer", { animationController = {} })
        unitwind:mock(tes3, "getPlayerEyePosition", function() return { x = 1, y = 2, z = 3 } end)

        local instance = controller.new()
        local ok = instance:LookAtPoint({ x = 1, y = 2, z = 3 })

        unitwind:expect(ok).toBe(false)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
