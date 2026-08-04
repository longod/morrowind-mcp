local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local pathfinding = require("morrowind-mcp.util.pathfinding")
    local cellutil = require("morrowind-mcp.tes3.cell")

    --- Return the shared graph key used by the pathfinding implementation.
    ---@param cell tes3cell
    ---@return string
    local function CellKey(cell)
        return cellutil.GetIdentityKey(cell)
    end

    --- Build a pathgrid node mock with a plain position table.
    local function Node(x, y, z)
        return { position = { x = x, y = y, z = z }, connectedNodes = {} }
    end

    --- Build the minimal active-cell shape consumed by UpdateCell.
    local function Cell(id, gridX, gridY, nodes, isInterior)
        local cell = { id = id, isInterior = isInterior ~= false, gridX = gridX, gridY = gridY, waterLevel = 0, pathGrid = { isLoaded = true, nodes = nodes }, references = {}, valid = true }
        function cell:isValid()
            return self.valid ~= false
        end
        function cell:iterateReferences(filter, yieldDisabled)
            local index = 0
            return function()
                index = index + 1
                return self.references[index]
            end
        end
        return cell
    end

    --- Build a valid teleport-door reference with copied-position test data.
    local function Door(position, destinationCell, markerPosition)
        local door = {
            position = position,
            destination = { cell = destinationCell, marker = { position = markerPosition } },
        }
        function door:isValid()
            return true
        end
        return door
    end

    local function InvalidDoor()
        return {
            isValid = function()
                return false
            end,
        }
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
        unitwind:expect(graph.nodes[graph.nodeIdsByCellId[CellKey(cell)][1]].position.x).toBe(10)
    end)

    unitwind:test("UpdateCell resolves copied connectedNodes by position", function()
        local first, second = Node(10, 20, 30), Node(110, 20, 30)
        -- MWSE generates independent node values for connectedNodes instead of returning the original grid node.
        first.connectedNodes = { Node(110, 20, 30) }
        local graph, cell = pathfinding.new(), Cell("copied-connections", 0, 0, { first, second })
        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(table.size(graph.edges)).toBe(1)
        local firstNodeId = graph.nodeIdsByCellId[CellKey(cell)][1]
        local secondNodeId = graph.nodeIdsByCellId[CellKey(cell)][2]
        unitwind:expect(graph.edgeIdByNeighborId[firstNodeId][secondNodeId] == nil).toBe(false)
    end)

    unitwind:test("UpdateCell resolves copied nodes with negative fractional coordinates", function()
        local first, second = Node(-123.5, 8192.25, -0.5), Node(10.75, -2.5, 3.125)
        first.connectedNodes = { Node(10.75, -2.5, 3.125) }
        local graph, cell = pathfinding.new(), Cell("fractional-connections", 0, 0, { first, second })
        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(table.size(graph.edges)).toBe(1)
    end)

    unitwind:test("UpdateCell counts copied connections without a matching node", function()
        local first = Node(10, 20, 30)
        first.connectedNodes = { Node(110, 20, 30) }
        local graph, cell = pathfinding.new(), Cell("unresolved-connections", 0, 0, { first })
        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(table.size(graph.edges)).toBe(0)
        unitwind:expect(graph.cells[CellKey(cell)].unresolvedConnectionCount).toBe(1)
    end)

    unitwind:test("UpdateCell does not guess between nodes at the same position", function()
        local source = Node(0, 0, 0)
        local firstDuplicate = Node(100, 0, 0)
        local secondDuplicate = Node(100, 0, 0)
        source.connectedNodes = { Node(100, 0, 0) }
        local graph, cell = pathfinding.new(), Cell("ambiguous-connections", 0, 0,
            { source, firstDuplicate, secondDuplicate })
        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(table.size(graph.edges)).toBe(0)
        unitwind:expect(graph.cells[CellKey(cell)].unresolvedConnectionCount).toBe(0)
        unitwind:expect(graph.cells[CellKey(cell)].ambiguousConnectionCount).toBe(1)
    end)

    unitwind:test("FindPath uses A-Star and reroutes around a blocked edge", function()
        local first, second, third, detour = Node(0, 0, 0), Node(100, 0, 0), Node(200, 0, 0), Node(100, 100, 0)
        first.connectedNodes, second.connectedNodes, third.connectedNodes, detour.connectedNodes = { second, detour }, { first, third }, { second, detour }, { first, third }
        local graph, cell = pathfinding.new(), Cell("route", 0, 0, { first, second, third, detour })
        graph:UpdateCell(cell)
        local start, destination = { cell = cell, position = { x = 0, y = 0, z = 0 } }, { cell = cell, position = { x = 200, y = 0, z = 0 } }
        unitwind:expect(table.size(graph:FindPath(start, destination).nodeIds)).toBe(3)
        local secondNodeId = graph.nodeIdsByCellId[CellKey(cell)][2]
        local thirdNodeId = graph.nodeIdsByCellId[CellKey(cell)][3]
        unitwind:expect(graph:SetEdgeBlocked(graph.edgeIdByNeighborId[secondNodeId][thirdNodeId], true)).toBe(true)
        unitwind:expect(graph:FindPath(start, destination).nodeIds[2]).toBe(graph.nodeIdsByCellId[CellKey(cell)][4])
    end)

    unitwind:test("FindNearestNode is limited to the requested cell and applies vertical weight", function()
        local low, high, foreign = Node(0, 0, 0), Node(10, 0, 100), Node(1, 0, 0)
        local graph, cell, other = pathfinding.new(), Cell("near", 0, 0, { low, high }), Cell("other", 1, 0, { foreign })
        graph:UpdateCell(cell)
        graph:UpdateCell(other)
        local locator = { cell = cell, position = { x = 9, y = 0, z = 0 } }
        unitwind:expect(graph:FindNearestNode(locator).id).toBe(graph.nodeIdsByCellId[CellKey(cell)][1])
        unitwind:expect(graph:FindNearestNode(locator, { vertical = 0 }).id).toBe(graph.nodeIdsByCellId[CellKey(cell)][2])
    end)

    unitwind:test("Exterior neighbors stitch nodes near their shared 8192-unit border", function()
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }, false), Cell("east", 1, 0, { Node(8200, 100, 0) }, false)
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        local westNodeId = graph.nodeIdsByCellId[CellKey(west)][1]
        local eastNodeId = graph.nodeIdsByCellId[CellKey(east)][1]
        unitwind:expect(graph.cells[CellKey(west)].borderNodeIds.east[1]).toBe(westNodeId)
        unitwind:expect(graph.gridCellIdByPosition[1][0]).toBe(CellKey(east))
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId] == nil).toBe(false)
    end)

    unitwind:test("Exterior cells with the same region ID retain distinct grid snapshots", function()
        local graph = pathfinding.new()
        local west = Cell("shared region", 0, 0, { Node(0, 0, 0) }, false)
        local east = Cell("shared region", 1, 0, { Node(8192, 0, 0) }, false)
        west.references = { Door({ x = 0, y = 0, z = 0 }, east, { x = 8192, y = 0, z = 0 }) }
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        local westNodeId = graph.nodeIdsByCellId[CellKey(west)][1]
        local eastNodeId = graph.nodeIdsByCellId[CellKey(east)][1]
        unitwind:expect(table.size(graph.cells)).toBe(2)
        unitwind:expect(graph.nodes[graph.nodeIdsByCellId[CellKey(west)][1]].cellId).toBe(CellKey(west))
        unitwind:expect(graph.nodes[graph.nodeIdsByCellId[CellKey(east)][1]].cellId).toBe(CellKey(east))
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId] == nil).toBe(false)
    end)

    unitwind:test("Water surface cost responds to water walking without changing graph topology", function()
        local first, second = Node(0, 0, 0), Node(100, 0, 0)
        first.connectedNodes = { second }
        local graph = pathfinding.new()
        local cell = Cell("water", 0, 0, { first, second })
        graph:UpdateCell(cell)
        local edgeId = graph.edgeIdByNeighborId[graph.nodeIdsByCellId[CellKey(cell)][1]][graph.nodeIdsByCellId[CellKey(cell)][2]]
        graph:SetEdgeSurface(edgeId, pathfinding.edgeSurface.water)
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
        local firstNodeId = graph.nodeIdsByCellId[CellKey(cell)][1]
        local secondNodeId = graph.nodeIdsByCellId[CellKey(cell)][2]
        local edgeId = graph.edgeIdByNeighborId[firstNodeId][secondNodeId]
        graph:SetEdgeBlocked(edgeId, true)
        graph:SetEdgeSurface(edgeId, pathfinding.edgeSurface.water)
        first.position.x = 999

        unitwind:expect(graph:UpdateCell(cell)).toBe(true)
        unitwind:expect(graph.nodes[firstNodeId].position.x).toBe(0)
        unitwind:expect(graph.edges[edgeId].blocked).toBe(true)
        unitwind:expect(graph.edges[edgeId].surface).toBe(pathfinding.edgeSurface.water)
    end)

    unitwind:test("UpdateCell preserves cross-cell stitching when a snapshotted cell is revisited", function()
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }, false), Cell("east", 1, 0, { Node(8200, 100, 0) }, false)
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        local westNodeId = graph.nodeIdsByCellId[CellKey(west)][1]
        local eastNodeId = graph.nodeIdsByCellId[CellKey(east)][1]
        local stitchEdgeId = graph.edgeIdByNeighborId[westNodeId][eastNodeId]
        graph:UpdateCell(west)
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId]).toBe(stitchEdgeId)
    end)

    unitwind:test("Exterior stitching connects north-south neighbors but skips diagonals", function()
        -- gridY-axis coverage plus a diagonal (1,1) that must never share an edge with (0,0).
        local graph = pathfinding.new({ stitchBorderMargin = 32, stitchMaxHorizontalDistance = 64 })
        local south = Cell("south", 0, 0, { Node(100, 8180, 0) }, false)
        local north = Cell("north", 0, 1, { Node(100, 8200, 0) }, false)
        local diagonal = Cell("diagonal", 1, 1, { Node(8200, 8200, 0) }, false)
        graph:UpdateCell(south)
        graph:UpdateCell(north)
        graph:UpdateCell(diagonal)
        local southNodeId = graph.nodeIdsByCellId[CellKey(south)][1]
        local northNodeId = graph.nodeIdsByCellId[CellKey(north)][1]
        local diagonalNodeId = graph.nodeIdsByCellId[CellKey(diagonal)][1]
        unitwind:expect(graph.edgeIdByNeighborId[southNodeId][northNodeId] == nil).toBe(false)
        unitwind:expect(graph.edgeIdByNeighborId[southNodeId][diagonalNodeId] == nil).toBe(true)
    end)

    unitwind:test("pathfinding.new applies caller-provided stitching parameters", function()
        -- Border margin 1 must forbid the 8180/8200 stitch that the defaults would accept.
        local graph = pathfinding.new({ stitchBorderMargin = 1 })
        local west, east = Cell("west", 0, 0, { Node(8180, 100, 0) }, false), Cell("east", 1, 0, { Node(8200, 100, 0) }, false)
        graph:UpdateCell(west)
        graph:UpdateCell(east)
        unitwind:expect(graph.stitchBorderMargin).toBe(1)
        local westNodeId = graph.nodeIdsByCellId[CellKey(west)][1]
        local eastNodeId = graph.nodeIdsByCellId[CellKey(east)][1]
        unitwind:expect(graph.edgeIdByNeighborId[westNodeId][eastNodeId] == nil).toBe(true)
    end)

    unitwind:test("Teleport doors create directed travel edges after both active cells are snapshotted", function()
        local sourceStart, sourceDoor = Node(0, 0, 0), Node(100, 0, 0)
        sourceStart.connectedNodes = { sourceDoor }
        local source = Cell("interior", 0, 0, { sourceStart, sourceDoor })
        source.isInterior = true
        local destinationMarker, destinationGoal = Node(10000, 0, 0), Node(10100, 0, 0)
        destinationMarker.connectedNodes = { destinationGoal }
        local destination = Cell("exterior", 1, 0, { destinationMarker, destinationGoal })
        source.references = { Door({ x = 100, y = 0, z = 0 }, destination, { x = 10000, y = 0, z = 0 }) }
        local graph = pathfinding.new()

        graph:UpdateCell(source)
        local sourceNodeId = graph.nodeIdsByCellId[CellKey(source)][2]
        unitwind:expect(table.size(graph.edges)).toBe(1)
        graph:UpdateCell(destination)
        unitwind:expect(table.size(graph.travelDestinationsByCellId[CellKey(source)])).toBe(1)
        unitwind:expect(graph.travelEdgeCount).toBe(1)

        local destinationNodeId = graph.nodeIdsByCellId[CellKey(destination)][1]
        local edgeId = graph.edgeIdByNeighborId[sourceNodeId][destinationNodeId]
        local edge = graph.edges[edgeId]
        unitwind:expect(edge.kind).toBe(pathfinding.edgeKind.travel)
        unitwind:expect(edge.horizontalDistance).toBe(0)
        unitwind:expect(edge.doorPosition.x).toBe(100)
        unitwind:expect(graph.edgeIdByNeighborId[destinationNodeId][sourceNodeId] == nil).toBe(true)
        unitwind:expect(graph:FindPath({ cell = source, position = { x = 0, y = 0, z = 0 } }, { cell = destination, position = { x = 10100, y = 0, z = 0 } }).cost).toBe(200)
    end)

    unitwind:test("Invalid door references are skipped during travel destination collection", function()
        local cell = Cell("invalid-door", 0, 0, { Node(0, 0, 0) })
        cell.references = { InvalidDoor() }
        local graph = pathfinding.new()
        graph:UpdateCell(cell)
        unitwind:expect(table.size(graph.travelDestinationsByCellId[CellKey(cell)])).toBe(0)
    end)

    unitwind:test("Travel destinations without an exterior grid are skipped", function()
        local source = Cell("source-without-grid", 0, 0, { Node(0, 0, 0) }, false)
        local destination = Cell("missing-grid", nil, nil, { Node(100, 0, 0) }, false)
        source.references = { Door({ x = 0, y = 0, z = 0 }, destination, { x = 100, y = 0, z = 0 }) }
        local graph = pathfinding.new()
        graph:UpdateCell(source)
        unitwind:expect(table.size(graph.travelDestinationsByCellId[CellKey(source)])).toBe(0)
    end)

    unitwind:test("Travel edges disable the geometric heuristic and respect blockage", function()
        local source = Cell("source-heuristic", 0, 0, { Node(0, 0, 0) })
        local destination = Cell("destination-heuristic", 1, 0, { Node(10000, 0, 0) })
        source.references = { Door({ x = 0, y = 0, z = 0 }, destination, { x = 10000, y = 0, z = 0 }) }
        local graph = pathfinding.new()
        graph:UpdateCell(source)
        graph:UpdateCell(destination)
        local sourceNodeId = graph.nodeIdsByCellId[CellKey(source)][1]
        local destinationNodeId = graph.nodeIdsByCellId[CellKey(destination)][1]
        local edgeId = graph.edgeIdByNeighborId[sourceNodeId][destinationNodeId]
        unitwind:expect(graph:Heuristic(graph.nodes[sourceNodeId], graph.nodes[destinationNodeId])).toBe(0)
        graph:SetEdgeBlocked(edgeId, true)
        unitwind:expect(graph:FindPath({ cell = source, position = { x = 0, y = 0, z = 0 } }, { cell = destination, position = { x = 10000, y = 0, z = 0 } })).toBe(nil)
    end)

    unitwind:test("OnLoaded refreshes the player cell without a pending poll", function()
        local playerCell = Cell("player-loaded", 0, 0, { Node(0, 0, 0) })
        unitwind:mock(tes3, "player", { cell = playerCell })
        local graph = pathfinding.new()
        graph:OnLoaded()
        unitwind:expect(graph.cells[CellKey(playerCell)] == nil).toBe(false)
    end)

    unitwind:test("Reactivating a cell replaces travel destinations and removes stale edges", function()
        local source = Cell("source", 0, 0, { Node(0, 0, 0) })
        local firstDestination = Cell("first", 1, 0, { Node(1000, 0, 0) })
        local secondDestination = Cell("second", 2, 0, { Node(2000, 0, 0) })
        source.references = { Door({ x = 0, y = 0, z = 0 }, firstDestination, { x = 1000, y = 0, z = 0 }) }
        local graph = pathfinding.new()
        graph:UpdateCell(source)
        graph:UpdateCell(firstDestination)
        graph:UpdateCell(secondDestination)
        local sourceNodeId = graph.nodeIdsByCellId[CellKey(source)][1]
        local firstNodeId = graph.nodeIdsByCellId[CellKey(firstDestination)][1]
        local secondNodeId = graph.nodeIdsByCellId[CellKey(secondDestination)][1]
        unitwind:expect(graph.edgeIdByNeighborId[sourceNodeId][firstNodeId] == nil).toBe(false)

        source.references = { Door({ x = 0, y = 0, z = 0 }, secondDestination, { x = 2000, y = 0, z = 0 }) }
        graph:UpdateCell(source)
        unitwind:expect(graph.edgeIdByNeighborId[sourceNodeId][firstNodeId] == nil).toBe(true)
        unitwind:expect(graph.edgeIdByNeighborId[sourceNodeId][secondNodeId] == nil).toBe(false)
        unitwind:expect(graph.travelEdgeCount).toBe(1)
    end)

    unitwind:test("Pathgrid polling follows cell, load, and shutdown lifecycles", function()
        local registeredCallbacks = {}
        local startedTimers = {}
        unitwind:mock(tes3, "player", nil)
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
        unitwind:expect(graph.pendingPathgridPolls[CellKey(replacementCell)].cellHandle:getObject()).toBe(replacementCell)
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
        unitwind:expect(graph.cells[CellKey(polledCell)] == nil).toBe(false)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local loadedCell = Cell("loaded", 2, 0, { Node(0, 0, 0) })
        loadedCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = loadedCell })
        -- MWSE cancels active timers immediately before firing loaded.
        startedTimers[5].instance.cancelled = true
        loadedCell.pathGrid.isLoaded = true
        registeredCallbacks[tes3.event.loaded]({})
        unitwind:expect(graph.cells[CellKey(loadedCell)] == nil).toBe(false)
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
        unitwind:mock(tes3, "player", nil)
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
        unitwind:expect(graph.cells["interior:invalidated-polling"] == nil).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        local loadedCell = Cell("invalidated-loaded", 1, 0, { Node(0, 0, 0) })
        loadedCell.pathGrid.isLoaded = false
        registeredCallbacks[tes3.event.cellActivated]({ cell = loadedCell })
        startedTimers[2].instance.cancelled = true
        loadedCell.valid = false
        loadedCell.pathGrid = nil
        loadedCell.id = nil
        registeredCallbacks[tes3.event.loaded]({})
        unitwind:expect(graph.cells["interior:invalidated-loaded"] == nil).toBe(true)
        unitwind:expect(table.size(graph.pendingPathgridPolls)).toBe(0)

        graph:UnregisterEventHandlers()
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
