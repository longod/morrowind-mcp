local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local distance = require("morrowind-mcp.util.distance")
    local epsilon = 1e-9

    unitwind:start("morrowind-mcp.util.distance")
    unitwind:test("Converts zero distance", function()
        unitwind:expect(distance.ToMeters(0)).toBe(0)
    end)

    unitwind:test("Converts one foot in game units to meters", function()
        unitwind:expect(distance.ToMeters(22.1)).toBe(0.3048)
    end)

    unitwind:test("Converts representative game distance", function()
        local actual = distance.ToMeters(1100)
        local expected = 1100 * 0.3048 / 22.1
        local diff = math.abs(actual - expected)
        unitwind:expect(diff < epsilon).toBe(true)
    end)

    unitwind:test("Converts zero meters", function()
        unitwind:expect(distance.ToUnits(0)).toBe(0)
    end)

    unitwind:test("Converts one international foot to game units", function()
        unitwind:expect(distance.ToUnits(0.3048)).toBe(22.1)
    end)

    unitwind:test("Converts representative meter distance", function()
        local actual = distance.ToUnits(15.17)
        local expected = 15.17 * 22.1 / 0.3048
        local diff = math.abs(actual - expected)
        unitwind:expect(diff < epsilon).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
