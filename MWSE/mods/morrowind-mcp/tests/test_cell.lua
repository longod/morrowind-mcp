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

    unitwind:test("GetNearbyActiveCells returns only the current interior cell", function()
        local interior = { id = "Balmora", isInterior = true }
        local cells = cellutil.GetNearbyActiveCells(interior, { x = 0, y = 0 }, { interior })

        unitwind:expect(table.size(cells)).toBe(1)
        unitwind:expect(cells[1]).toBe(interior)
    end)

    unitwind:test("GetNearbyActiveCells includes loaded neighbours only near exterior boundaries", function()
        local current = { id = "Ascadian Isles", isInterior = false, gridX = 10, gridY = 20 }
        local east = { id = "Ascadian Isles", isInterior = false, gridX = 11, gridY = 20 }
        local north = { id = "Ascadian Isles", isInterior = false, gridX = 10, gridY = 21 }
        local northEast = { id = "Ascadian Isles", isInterior = false, gridX = 11, gridY = 21 }
        local cells = cellutil.GetNearbyActiveCells(current, {
            x = (10 + 0.9) * cellutil.exteriorCellSize,
            y = (20 + 0.9) * cellutil.exteriorCellSize,
        }, { current, east, north, northEast })

        unitwind:expect(table.size(cells)).toBe(4)
        unitwind:expect(cells[1]).toBe(current)
        unitwind:expect(cells[2]).toBe(east)
        unitwind:expect(cells[3]).toBe(north)
        unitwind:expect(cells[4]).toBe(northEast)
    end)

    unitwind:test("GetNearbyActiveCells returns the current exterior cell away from boundaries", function()
        local current = { id = "Ascadian Isles", isInterior = false, gridX = 10, gridY = 20 }
        local cells = cellutil.GetNearbyActiveCells(current, {
            x = (10 + 0.5) * cellutil.exteriorCellSize,
            y = (20 + 0.5) * cellutil.exteriorCellSize,
        }, { current })

        unitwind:expect(table.size(cells)).toBe(1)
        unitwind:expect(cells[1]).toBe(current)
    end)

    unitwind:test("GetNearbyActiveCells includes west and south neighbours near lower boundaries", function()
        local current = { id = "Ascadian Isles", isInterior = false, gridX = 10, gridY = 20 }
        local west = { id = "Ascadian Isles", isInterior = false, gridX = 9, gridY = 20 }
        local south = { id = "Ascadian Isles", isInterior = false, gridX = 10, gridY = 19 }
        local southWest = { id = "Ascadian Isles", isInterior = false, gridX = 9, gridY = 19 }
        local cells = cellutil.GetNearbyActiveCells(current, {
            x = (10 + 0.1) * cellutil.exteriorCellSize,
            y = (20 + 0.1) * cellutil.exteriorCellSize,
        }, { current, west, south, southWest })

        unitwind:expect(table.size(cells)).toBe(4)
        unitwind:expect(cells[1]).toBe(current)
        unitwind:expect(cells[2]).toBe(west)
        unitwind:expect(cells[3]).toBe(south)
        unitwind:expect(cells[4]).toBe(southWest)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
