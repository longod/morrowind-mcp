local this = {}
---@diagnostic disable: missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local cellutil = require("morrowind-mcp.tes3.cell")

    unitwind:start("morrowind-mcp.tes3.cell")

    unitwind:test("GetIdentityKey namespaces interiors and distinguishes exterior grid positions", function()
        local interior = { id = "Balmora", isInterior = true }
        local west = { id = "West Gash", isInterior = false, gridX = 0, gridY = 0 }
        local east = { id = "West Gash", isInterior = false, gridX = 1, gridY = 0 }

        unitwind:expect(cellutil.GetIdentityKey(interior)).toBe("interior:Balmora")
        unitwind:expect(cellutil.GetIdentityKey(west)).toBe("exterior:West Gash:0,0")
        unitwind:expect(cellutil.GetIdentityKey(east)).toBe("exterior:West Gash:1,0")
    end)

    unitwind:test("GetIdentityKey rejects unavailable cells and exterior cells without a grid", function()
        unitwind:expect(cellutil.GetIdentityKey(nil)).toBe(nil)
        unitwind:expect(cellutil.GetIdentityKey({ isInterior = true })).toBe(nil)
        unitwind:expect(cellutil.GetIdentityKey({ id = "West Gash", isInterior = false, gridX = 0 })).toBe(nil)
        unitwind:expect(cellutil.GetIdentityKey({ id = "West Gash", isInterior = false, gridY = 0 })).toBe(nil)
    end)

    unitwind:test("ResolveOptionalId uses the fallback for missing IDs and resolves explicit IDs", function()
        local fallback = { id = "Current Cell", isInterior = true }
        local requested = { id = "Destination Cell", isInterior = true }
        unitwind:mock(tes3, "getCell", function(params)
            if params.id == "Destination Cell" then
                return requested
            end
            return nil
        end)

        unitwind:expect(cellutil.ResolveOptionalId(nil, fallback)).toBe(fallback)
        unitwind:expect(cellutil.ResolveOptionalId("   ", fallback)).toBe(fallback)
        unitwind:expect(cellutil.ResolveOptionalId("Destination Cell", fallback)).toBe(requested)
        unitwind:expect(cellutil.ResolveOptionalId("Missing Cell", fallback)).toBe(nil)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
