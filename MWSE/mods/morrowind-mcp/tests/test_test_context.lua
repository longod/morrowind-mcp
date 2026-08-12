local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local testContext = require("morrowind-mcp.util.test_context")

    unitwind:start("morrowind-mcp.util.test_context")
    unitwind:test("Parses a unit test context", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":true,"accept_disclaimer":true,"unit_test":{"mode":"run-and-exit","targets":["test_distance.lua"]}}]])
        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(context ~= nil).toBe(true)
        if context ~= nil then
            unitwind:expect(context.suppressAutoContinue).toBe(true)
            unitwind:expect(context.acceptDisclaimer).toBe(true)
            unitwind:expect(context.unitTest.mode).toBe("run-and-exit")
            unitwind:expect(context.unitTest.targets[1]).toBe("test_distance.lua")
        end
    end)

    unitwind:test("Rejects malformed JSON", function()
        local context, errorMessage = testContext.Parse("{")
        unitwind:expect(context).toBe(nil)
        unitwind:expect(type(errorMessage)).toBe("string")
    end)

    unitwind:test("Rejects an unsupported version", function()
        local context, errorMessage = testContext.Parse([[{"version":2,"suppress_auto_continue":true,"accept_disclaimer":false,"unit_test":{"mode":"skip","targets":[]}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("Unsupported or missing context version.")
    end)

    unitwind:test("Rejects a non-boolean auto continue flag", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":"true","accept_disclaimer":false,"unit_test":{"mode":"skip","targets":[]}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("suppress_auto_continue must be a boolean.")
    end)

    unitwind:test("Rejects an unknown unit test mode", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":true,"accept_disclaimer":false,"unit_test":{"mode":"unknown","targets":[]}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("unit_test.mode is invalid.")
    end)

    unitwind:test("Rejects non-array targets", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":true,"accept_disclaimer":false,"unit_test":{"mode":"skip","targets":"test_distance.lua"}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("unit_test.targets must be an array.")
    end)

    unitwind:test("Rejects non-string target entries", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":true,"accept_disclaimer":false,"unit_test":{"mode":"skip","targets":[1]}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("unit_test.targets must contain only strings.")
    end)

    unitwind:test("Parses each supported unit test mode", function()
        for _, mode in ipairs({ "run", "run-and-exit", "skip" }) do
            local context, errorMessage = testContext.Parse(string.format([[{"version":1,"suppress_auto_continue":false,"accept_disclaimer":false,"unit_test":{"mode":"%s","targets":[]}}]], mode))
            unitwind:expect(errorMessage).toBe(nil)
            unitwind:expect(context ~= nil).toBe(true)
        end
    end)

    unitwind:test("Rejects a non-boolean disclaimer flag", function()
        local context, errorMessage = testContext.Parse([[{"version":1,"suppress_auto_continue":true,"accept_disclaimer":"true","unit_test":{"mode":"skip","targets":[]}}]])
        unitwind:expect(context).toBe(nil)
        unitwind:expect(errorMessage).toBe("accept_disclaimer must be a boolean.")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
