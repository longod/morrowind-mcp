local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local visualizerModule = require("morrowind-mcp.navigation.visualizer")

    unitwind:start("morrowind-mcp.navigation.visualizer")

    unitwind:test("Layer toggles request one deferred refresh", function()
        local graph = { edges = {}, nodes = {} } ---@cast graph MCP.Pathfinding
        local terrain = { grids = {} } ---@cast terrain MCP.TerrainGridManager
        local visualizer = visualizerModule.new(graph, terrain)
        visualizer.refreshRequested = false
        visualizer.graphRefreshRequested = false
        visualizer.terrainRefreshAll = false
        visualizer:SetGraphEnabled(false)
        unitwind:expect(visualizer.options.graphEnabled).toBe(false)
        unitwind:expect(visualizer.refreshRequested).toBe(true)
        unitwind:expect(visualizer.graphRefreshRequested).toBe(true)
        unitwind:expect(visualizer.terrainRefreshAll).toBe(false)
        visualizer.refreshRequested = false
        visualizer.graphRefreshRequested = false
        visualizer:SetTerrainEnabled(false)
        unitwind:expect(visualizer.options.terrainEnabled).toBe(false)
        unitwind:expect(visualizer.refreshRequested).toBe(true)
        unitwind:expect(visualizer.graphRefreshRequested).toBe(false)
        unitwind:expect(visualizer.terrainRefreshAll).toBe(true)
    end)

    unitwind:test("Global disable requests cleanup refresh", function()
        local graph = { edges = {}, nodes = {} } ---@cast graph MCP.Pathfinding
        local terrain = { grids = {} } ---@cast terrain MCP.TerrainGridManager
        local visualizer = visualizerModule.new(graph, terrain)
        visualizer.refreshRequested = false
        visualizer:SetEnabled(false)
        unitwind:expect(visualizer.options.enabled).toBe(false)
        unitwind:expect(visualizer.refreshRequested).toBe(true)
    end)

    unitwind:test("Graph refresh includes cells connected to the changed cell", function()
        local graph = {
            nodes = {
                [1] = { id = 1, cellId = "source", position = { x = 0, y = 0, z = 0 } },
                [2] = { id = 2, cellId = "neighbor", position = { x = 100, y = 0, z = 0 } },
            },
            edges = {
                [10] = { id = 10, fromId = 1, toId = 2 },
            },
            nodeIdsByCellId = { source = { 1 }, neighbor = { 2 } },
            edgeIdByNeighborId = { [1] = { [2] = 10 }, [2] = { [1] = 10 } },
        } ---@cast graph MCP.Pathfinding
        local affectedCellIds = visualizerModule.GetGraphRefreshCellIds(graph, "source")

        unitwind:expect(affectedCellIds.source).toBe(true)
        unitwind:expect(affectedCellIds.neighbor).toBe(true)
        unitwind:expect(table.size(affectedCellIds)).toBe(2)
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this