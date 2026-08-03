local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local pathfinding = require("morrowind-mcp.util.pathfinding")

    --- Build a pathgrid node mock with a plain position table.
    local function Node(x, y, z)
        return { position = { x = x, y = y, z = z }, connectedNodes = {} }
    end

    --- Build the minimal loaded-cell shape consumed by UpdateCell.
    local function Cell(id, gridX, gridY, nodes)
        local cell = { id = id, isInterior = false, gridX = gridX, gridY = gridY, waterLevel = 0, pathGrid = { isLoaded = true, nodes = nodes }, valid = true }
        function cell:isValid()
            return self.valid ~= false
        end
        return cell
    end

    --- Mirror the safe-handle validity boundary used by MWSE timer callbacks.
    local function SafeObjectHandle(object)
        return {
            valid = function()
                return object:isValid()
            end,
            getObject = function()
                if object:isValid() then
                    return object
                end
                return nil
            end,
        }
    end

    unitwind:start("morrowind-mcp.util.pathfinding")

    unitwind:test("UpdateCell snapshots an undirected pathgrid without retaining positions", function()
        local first, second = Node(10, 20, 30), Node(110, 20, 30)
        first.connectedNodes = { second }
        local graph, cell = pathfinding.new(), Cell("0,0", 0, 0, { first, second })
        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(table.size(graph.nodes)).toBe(2)
        unitwind:expect(table.size(graph.edges)).toBe(1)
        first.position.x = 999
        unitwind:expect(graph.nodes[graph.nodeIdsByCellId[cell.id][1]].position.x).toBe(10)
    end)

    unitwind:test("FindPath uses A-Star and reroutes around a blocked edge", function()
        local first, second, third, detour = Node(0, 0, 0), Node(100, 0, 0), Node(200, 0, 0), Node(100, 100, 0)
        first.connectedNodes, second.connectedNodes, third.connectedNodes, detour.connectedNodes = { second, detour }, { first, third }, { second, detour }, { first, third }
        local graph, cell = pathfinding.new(), Cell("route", 0, 0, { first, second, third, detour })
        graph:UpdateCell(cell)
        local start, destination = { cell = cell, position = { x = 0, y = 0, z = 0 } }, { cell = cell, position = { x = 200, y = 0, z = 0 } }
        unitwind:expect(table.size(graph:FindPath(start, destination).nodeIds)).toBe(3)
        local secondNodeId = graph.nodeIdsByCellId[cell.id][2]
        local thirdNodeId = graph.nodeIdsByCellId[cell.id][3]
        unitwind:expect(graph:SetEdgeBlocked(graph.edgeIdByNeighborId[secondNodeId][thirdNodeId], true)).toBe(true)
        unitwind:expect(graph:FindPath(start, destination).nodeIds[2]).toBe(graph.nodeIdsByCellId[cell.id][4])
    end)

    unitwind:test("FindNearestNode is limited to the requested cell and applies vertical weight", function()
        local low, high, foreign = Node(0, 0, 0), Node(10, 0, 100), Node(1, 0, 0)
        local graph, cell, other = pathfinding.new(), Cell("near", 0, 0, { low, high }), Cell("other", 1, 0, { foreign })
        graph:UpdateCell(cell)
        graph:UpdateCell(other)
        local locator = { cell = cell, position = { x = 9, y = 0, z = 0 } }
        unitwind:expect(graph:FindNearestNode(locator).id).toBe(graph.nodeIdsByCellId[cell.id][1])
        unitwind:expect(graph:FindNearestNode(locator, { vertical = 0 }).id).toBe(graph.nodeIdsByCellId[cell.id][2])
    end)

    unitwind:test("Exterior neighbors stitch nodes near their shared 8192-unit border", function()
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }), Cell("east", 1, 0, { Node(8200, 100, 0) })
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        local westNodeId = graph.nodeIdsByCellId[west.id][1]
        local eastNodeId = graph.nodeIdsByCellId[east.id][1]
        unitwind:expect(graph.cells[west.id].borderNodeIds.east[1]).toBe(westNodeId)
        unitwind:expect(graph.gridCellIdByPosition[1][0]).toBe(east.id)
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId] == nil).toBe(false)
    end)

    unitwind:test("Water surface cost responds to water walking without changing graph topology", function()
        local first, second = Node(0, 0, 0), Node(100, 0, 0)
        first.connectedNodes = { second }
        local graph = pathfinding.new()
        local cell = Cell("water", 0, 0, { first, second })
        graph:UpdateCell(cell)
        local edgeId = graph.edgeIdByNeighborId[graph.nodeIdsByCellId[cell.id][1]][graph.nodeIdsByCellId[cell.id][2]]
        graph:SetEdgeSurface(edgeId, "water")
        local edge = graph.edges[edgeId]
        unitwind:expect(graph:EdgeCost(edge, { waterWeight = 3 })).toBe(300)
        unitwind:expect(graph:EdgeCost(edge, { waterWalking = true, waterWalkingWeight = 1 })).toBe(100)
        unitwind:expect(table.size(graph.edges)).toBe(1)
    end)

    unitwind:test("UpdateCell preserves learned edge state for an existing cell snapshot", function()
        local first, second = Node(0, 0, 0), Node(100, 0, 0)
        first.connectedNodes = { second }
        local graph = pathfinding.new()
        local cell = Cell("persisted", 0, 0, { first, second })
        graph:UpdateCell(cell)
        local firstNodeId = graph.nodeIdsByCellId[cell.id][1]
        local secondNodeId = graph.nodeIdsByCellId[cell.id][2]
        local edgeId = graph.edgeIdByNeighborId[firstNodeId][secondNodeId]
        graph:SetEdgeBlocked(edgeId, true)
        graph:SetEdgeSurface(edgeId, "water")
        first.position.x = 999

        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(graph.nodes[firstNodeId].position.x).toBe(0)
        unitwind:expect(graph.edges[edgeId].blocked).toBe(true)
        unitwind:expect(graph.edges[edgeId].surface).toBe("water")
    end)

    unitwind:test("UpdateCell preserves cross-cell stitching when a snapshotted cell is revisited", function()
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }), Cell("east", 1, 0, { Node(8200, 100, 0) })
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        local westNodeId = graph.nodeIdsByCellId[west.id][1]
        local eastNodeId = graph.nodeIdsByCellId[east.id][1]
        local stitchEdgeId = graph.edgeIdByNeighborId[westNodeId][eastNodeId]
        graph:UpdateCell(west)
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId]).toBe(stitchEdgeId)
    end)

    unitwind:test("Exterior stitching connects north-south neighbors but skips diagonals", function()
        -- gridY-axis coverage plus a diagonal (1,1) that must never share an edge with (0,0).
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local south = Cell("south", 0, 0, { Node(100, 8180, 0) })
        local north = Cell("north", 0, 1, { Node(100, 8200, 0) })
        local diagonal = Cell("diagonal", 1, 1, { Node(8200, 8200, 0) })
        graph:UpdateCell(south)
        graph:UpdateCell(north)
        graph:UpdateCell(diagonal)
        local southNodeId = graph.nodeIdsByCellId[south.id][1]
        local northNodeId = graph.nodeIdsByCellId[north.id][1]
        local diagonalNodeId = graph.nodeIdsByCellId[diagonal.id][1]
        unitwind:expect(graph.edgeIdByNeighborId[southNodeId][northNodeId] == nil).toBe(false)
        unitwind:expect(graph.edgeIdByNeighborId[southNodeId][diagonalNodeId] == nil).toBe(true)
    end)

    unitwind:test("pathfinding.new applies caller-provided stitching parameters", function()
        -- Border margin 1 must forbid the 8180/8200 stitch that the defaults would accept.
        local graph = pathfinding.new({ stitchBorderMargin = 1 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }), Cell("east", 1, 0, { Node(8200, 100, 0) })
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        unitwind:expect(graph.stitchBorderMargin).toBe(1)
        local westNodeId = graph.nodeIdsByCellId[west.id][1]
        local eastNodeId = graph.nodeIdsByCellId[east.id][1]
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId] == nil).toBe(true)
    end)

    unitwind:test("Pathgrid polling follows cell, load, and shutdown lifecycles", function()
        local registeredCallbacks = {}
        local startedTimers = {}
        unitwind:mock(tes3, "makeSafeObjectHandle", SafeObjectHandle)
        unitwind:mock(event, "register", function(eventId, callback)
            registeredCallbacks[eventId] = callback
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            if registeredCallbacks[eventId] == callback then
                registeredCallbacks[eventId] = nil
            end
        end)
        unitwind:mock(timer, "start", function(params)
            local timerInstance = { cancelled = false, timing = params.duration }
            function timerInstance:cancel()
                self.cancelled = true
            end
            table.insert(startedTimers, { params = params, instance = timerInstance })
            return timerInstance
        end)

        local graph = pathfinding.new({ pathgridPollInterval = 0.25, pathgridPollDeadline = 5 })
        graph:RegisterEventHandlers()
        unitwind:expect(registeredCallbacks[tes3.event.cellActivated] == nil).toBe(false)
        unitwind:expect(registeredCallbacks[tes3.event.cellDeactivated] == nil).toBe(false)
        unitwind:expect(registeredCallbacks[tes3.event.loaded] == nil).toBe(false)

        local originalCell = Cell("reactivated", 0, 0, { Node(0, 0, 0) })
        originalCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = originalCell })
        registeredCallbacks[tes3.event.cellActivated]({ cell = originalCell })
        unitwind:expect(table.size(startedTimers)).toBe(1)
        unitwind:expect(startedTimers[1].instance.cancelled).toBe(false)

        local replacementCell = Cell("reactivated", 0, 0, { Node(0, 0, 0) })
        replacementCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = replacementCell })
        unitwind:expect(startedTimers[1].instance.cancelled).toBe(true)
        unitwind:expect(table.size(startedTimers)).toBe(2)
        unitwind:expect(graph.pendingPathgridPolls[replacementCell.id].cellHandle:getObject()).toBe(replacementCell)
        registeredCallbacks[tes3.event.cellDeactivated]({ cell = replacementCell })
        unitwind:expect(startedTimers[2].instance.cancelled).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local deactivatedCell = Cell("deactivated", 0, 0, { Node(0, 0, 0) })
        deactivatedCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = deactivatedCell })
        unitwind:expect(startedTimers[3].params.type).toBe(timer.real)
        unitwind:expect(startedTimers[3].params.duration).toBe(0.25)
        unitwind:expect(startedTimers[3].params.iterations).toBe(-1)
        unitwind:expect(startedTimers[3].params.persist).toBe(false)
        registeredCallbacks[tes3.event.cellDeactivated]({ cell = deactivatedCell })
        unitwind:expect(startedTimers[3].instance.cancelled).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local polledCell = Cell("polled", 1, 0, { Node(0, 0, 0) })
        polledCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = polledCell })
        polledCell.pathGrid.isLoaded = true
        startedTimers[4].params.callback()
        unitwind:expect(startedTimers[4].instance.cancelled).toBe(true)
        unitwind:expect(graph.cells[polledCell.id] == nil).toBe(false)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local loadedCell = Cell("loaded", 2, 0, { Node(0, 0, 0) })
        loadedCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = loadedCell })
        -- MWSE cancels active timers immediately before firing loaded.
        startedTimers[5].instance.cancelled = true
        loadedCell.pathGrid.isLoaded = true
        registeredCallbacks[tes3.event.loaded]({})
        unitwind:expect(graph.cells[loadedCell.id] == nil).toBe(false)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local deadlineCell = Cell("deadline", 3, 0, { Node(0, 0, 0) })
        deadlineCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = deadlineCell })
        startedTimers[6].instance.timing = 5.25
        startedTimers[6].params.callback()
        unitwind:expect(startedTimers[6].instance.cancelled).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local shutdownCell = Cell("shutdown", 3, 0, { Node(0, 0, 0) })
        shutdownCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = shutdownCell })
        graph:UnregisterEventHandlers()
        unitwind:expect(startedTimers[7].instance.cancelled).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)
        unitwind:expect(registeredCallbacks[tes3.event.cellActivated] == nil).toBe(true)
        unitwind:expect(registeredCallbacks[tes3.event.cellDeactivated] == nil).toBe(true)
        unitwind:expect(registeredCallbacks[tes3.event.loaded] == nil).toBe(true)
    end)

    unitwind:test("Pathgrid polling drops invalidated cells before touching pathgrid state", function()
        local registeredCallbacks = {}
        local startedTimers = {}
        unitwind:mock(tes3, "makeSafeObjectHandle", SafeObjectHandle)
        unitwind:mock(event, "register", function(eventId, callback)
            registeredCallbacks[eventId] = callback
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            if registeredCallbacks[eventId] == callback then
                registeredCallbacks[eventId] = nil
            end
        end)
        unitwind:mock(timer, "start", function(params)
            local timerInstance = { cancelled = false, timing = params.duration }
            function timerInstance:cancel()
                self.cancelled = true
            end
            table.insert(startedTimers, { params = params, instance = timerInstance })
            return timerInstance
        end)

        local graph = pathfinding.new({ pathgridPollInterval = 0.1, pathgridPollDeadline = 5 })
        graph:RegisterEventHandlers()

        local pollingCell = Cell("invalidated-polling", 0, 0, { Node(0, 0, 0) })
        pollingCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = pollingCell })
        pollingCell.valid = false
        pollingCell.pathGrid = nil
        -- An invalid MWSE cell can no longer safely expose properties such as id.
        pollingCell.id = nil
        startedTimers[1].params.callback()
        unitwind:expect(startedTimers[1].instance.cancelled).toBe(true)
        unitwind:expect(graph.cells["invalidated-polling"] == nil).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local loadedCell = Cell("invalidated-loaded", 1, 0, { Node(0, 0, 0) })
        loadedCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = loadedCell })
        startedTimers[2].instance.cancelled = true
        loadedCell.valid = false
        loadedCell.pathGrid = nil
        loadedCell.id = nil
        registeredCallbacks[tes3.event.loaded]({})
        unitwind:expect(graph.cells["invalidated-loaded"] == nil).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        graph:UnregisterEventHandlers()
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
