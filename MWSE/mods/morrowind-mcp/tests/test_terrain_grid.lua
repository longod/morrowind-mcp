local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local gridModule = require("morrowind-mcp.navigation.terrain.grid")
    local quality = require("morrowind-mcp.navigation.terrain.quality")
    local raycast = require("morrowind-mcp.navigation.terrain.raycast")

    unitwind:start("morrowind-mcp.navigation.terrain.grid")

    ---@return MCP.TerrainGrid
    local function Grid(width, height, interval)
        return gridModule.new({
            cellId = "exterior:test:0,0",
            gridX = 0,
            gridY = 0,
            originX = 0,
            originY = 0,
            interval = interval or 128,
            width = width,
            height = height,
            maxSlopeDegrees = 46,
            maxClimb = 34,
            waterLevel = 0,
        })
    end

    unitwind:test("A-Star routes around unavailable terrain", function()
        local grid = Grid(3, 3)
        for row = 0, 2 do
            for column = 0, 2 do
                grid:SetSample(column, row, 10, 1)
            end
        end
        grid:SetUnavailable(1, 1)
        local path = grid:FindPath({ x = 0, y = 128, z = 10 }, { x = 256, y = 128, z = 10 })
        unitwind:expect(path ~= nil).toBe(true)
        ---@cast path table
        unitwind:expect(table.size(path.indices)).toBe(5)
        unitwind:expect(table.find(path.indices, grid:Index(1, 1)) == nil).toBe(true)
    end)

    unitwind:test("Diagonal traversal does not cut an unavailable corner", function()
        local grid = Grid(2, 2)
        grid:SetSample(0, 0, 10, 1)
        grid:SetSample(1, 1, 10, 1)
        grid:SetUnavailable(1, 0)
        grid:SetSample(0, 1, 10, 1)
        unitwind:expect(grid:CanTraverse(grid:Index(0, 0), gridModule.directions[5])).toBe(false)
    end)

    unitwind:test("Water and steep samples are not walkable", function()
        local grid = Grid(3, 1)
        grid:SetSample(0, 0, -1, 1)
        grid:SetSample(1, 0, 1, 0.5)
        grid:SetSample(2, 0, 1, 1)
        unitwind:expect(grid:IsWalkable(grid:Index(0, 0))).toBe(false)
        unitwind:expect(grid:IsWalkable(grid:Index(1, 0))).toBe(false)
        unitwind:expect(grid:IsWalkable(grid:Index(2, 0))).toBe(true)
    end)

    unitwind:test("Path lookup returns nil when no sample is walkable", function()
        local grid = Grid(2, 1)
        grid:SetUnavailable(0, 0)
        grid:SetUnavailable(1, 0)
        unitwind:expect(grid:FindNearestWalkable({ x = 0, y = 0, z = 0 })).toBe(nil)
        unitwind:expect(grid:FindPath({ x = 0, y = 0, z = 0 }, { x = 128, y = 0, z = 0 })).toBe(nil)
    end)

    unitwind:test("Blocked edge mask removes and restores traversal", function()
        local grid = Grid(2, 1)
        grid:SetSample(0, 0, 10, 1)
        grid:SetSample(1, 0, 10, 1)
        local first, second = grid:Index(0, 0), grid:Index(1, 0)
        unitwind:expect(grid:SetEdgeBlocked(first, second, true)).toBe(true)
        unitwind:expect(grid:CanTraverse(first, gridModule.directions[1])).toBe(false)
        grid:SetEdgeBlocked(first, second, false)
        unitwind:expect(grid:CanTraverse(first, gridModule.directions[1])).toBe(true)
    end)

    unitwind:test("Traversal independently enforces climb and slope limits", function()
        local climbGrid = Grid(2, 1, 128)
        climbGrid:SetSample(0, 0, 0, 1)
        climbGrid:SetSample(1, 0, 35, 1)
        unitwind:expect(climbGrid:CanTraverse(climbGrid:Index(0, 0), gridModule.directions[1])).toBe(false)

        local slopeGrid = Grid(2, 1, 128)
        slopeGrid.maxClimb = 1000
        slopeGrid:SetSample(0, 0, 0, 1)
        slopeGrid:SetSample(1, 0, 133, 1)
        unitwind:expect(slopeGrid:CanTraverse(slopeGrid:Index(0, 0), gridModule.directions[1])).toBe(false)
    end)

    unitwind:test("Quality evaluator reports interpolation error", function()
        local grid = Grid(2, 2, 10)
        grid:SetSample(0, 0, 0, 1)
        grid:SetSample(1, 0, 10, 1)
        grid:SetSample(0, 1, 0, 1)
        grid:SetSample(1, 1, 10, 1)
        local reference = { Sample = function(_, x) return x + 2, 1 end }
        local metrics = quality.EvaluateHeight(reference, grid, 5)
        unitwind:expect(metrics.compared).toBe(9)
        unitwind:expect(metrics.mae).toBe(2)
        unitwind:expect(metrics.rmse).toBe(2)
        unitwind:expect(metrics.max_error).toBe(2)
    end)

    unitwind:test("Ray volume offsets derive width and height from actor bounds", function()
        local offsets = raycast.BuildVolumeOffsets({ x = 60, y = 40 }, 120)
        unitwind:expect(table.size(offsets)).toBe(9)
        unitwind:expect(offsets[1].lateral).toBe(-30)
        unitwind:expect(offsets[3].lateral).toBe(30)
        unitwind:expect(offsets[8].vertical).toBe(112)
    end)

    unitwind:test("Ray segment ignores actors but rejects static hits", function()
        local actor = { object = { objectType = tes3.objectType.npc } }
        local static = { object = { objectType = tes3.objectType.static } }
        local current = actor
        unitwind:mock(tes3, "rayTest", function() return { reference = current, distance = 10 } end)
        local params = {
            boundSize2D = { x = 10, y = 10 },
            height = 20,
            roots = { { name = "test", node = {} } },
        }
        local clear = raycast.ValidateSegment({ x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }, params)
        unitwind:expect(clear.clear).toBe(true)
        current = static
        local blocked = raycast.ValidateSegment({ x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }, params)
        unitwind:expect(blocked.clear).toBe(false)
        unitwind:expect(blocked.classification).toBe("static")
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
