local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local distance = require("morrowind-mcp.util.distance")

    unitwind:start("morrowind-mcp.util.distance")
    unitwind:test("Converts zero distance", function()
        unitwind:expect(distance.ToMeters(0)).toBe(0)
    end)

    unitwind:test("Converts one foot in game units to meters", function()
        unitwind:expect(distance.ToMeters(22.1)).toBe(0.3048)
    end)

    unitwind:test("Converts representative game distance", function()
        unitwind:expect(distance.ToMeters(1100)).toBe(1100 * 0.3048 / 22.1)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
