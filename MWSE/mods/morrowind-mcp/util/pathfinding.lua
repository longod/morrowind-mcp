---@class MCP.PathfindingLocator
---@field cell tes3cell?
---@field marker tes3reference?
---@field position tes3vector3|MCP.PathfindingPosition?

---@class MCP.PathfindingPosition
---@field x number
---@field y number
---@field z number

---@class MCP.PathfindingNode
---@field id integer
---@field cellId string
---@field position MCP.PathfindingPosition

---@class MCP.PathfindingEdge
---@field id integer
---@field fromId integer
---@field toId integer
---@field kind string
---@field horizontalDistance number
---@field verticalDistance number
---@field surface string
---@field blocked boolean

---@class MCP.PathfindingCell
---@field id string
---@field isInterior boolean
---@field gridX integer?
---@field gridY integer?
---@field waterLevel number?
---@field borderNodeIds MCP.PathfindingBorderNodeIds

---@class MCP.PathfindingBorderNodeIds
---@field west MCP.PathfindingNodeIds
---@field east MCP.PathfindingNodeIds
---@field south MCP.PathfindingNodeIds
---@field north MCP.PathfindingNodeIds

---@class MCP.PathfindingParams
---@field exteriorCellSize number?
---@field stitchBorderMargin number?
---@field stitchMaxHorizontalDistance number?
---@field stitchMaxVerticalDistance number?

---@class MCP.PathfindingNearestWeights
---@field horizontal number?
---@field vertical number?

---@class MCP.PathfindingOptions
---@field nearestWeights MCP.PathfindingNearestWeights?
---@field horizontalWeight number?
---@field verticalWeight number?
---@field waterWeight number?
---@field waterWalking boolean?
---@field waterWalkingWeight number?
---@field useHeuristic boolean?

---@class MCP.PathfindingOpenEntry
---@field nodeId integer
---@field score number

---@class MCP.PathfindingPreviousEntry
---@field nodeId integer
---@field edgeId integer

---@class MCP.PathfindingResult
---@field nodeIds integer[]
---@field edgeIds integer[]
---@field cost number

---@alias MCP.PathfindingNodeIds integer[]
---@alias MCP.PathfindingNodes table<integer, MCP.PathfindingNode>
---@alias MCP.PathfindingEdges table<integer, MCP.PathfindingEdge>
---@alias MCP.PathfindingAdjacency table<integer, table<integer, integer>>
---@alias MCP.PathfindingGridCellIds table<integer, table<integer, string>>
---@alias MCP.PathfindingCosts table<integer, number>
---@alias MCP.PathfindingPrevious table<integer, MCP.PathfindingPreviousEntry>
---@alias MCP.PathfindingClosed table<integer, boolean>

---@class MCP.Pathfinding
---@field logger mwseLogger
---@field cells table<string, MCP.PathfindingCell>
---@field gridCellIdByPosition MCP.PathfindingGridCellIds
---@field nodes MCP.PathfindingNodes
---@field nodeIdsByCellId table<string, MCP.PathfindingNodeIds>
---@field edges MCP.PathfindingEdges
---@field edgeIdByNeighborId MCP.PathfindingAdjacency
---@field nextNodeId integer
---@field nextEdgeId integer
---@field exteriorCellSize number
---@field stitchBorderMargin number
---@field stitchMaxHorizontalDistance number
---@field stitchMaxVerticalDistance number
---@field cellActivatedCallback fun(e: cellActivatedEventData)?
local this = {}

local exteriorCellSize = 8192

--- Copy a vector because pathfinding snapshots must not retain MWSE userdata.
---@param position tes3vector3|MCP.PathfindingPosition
---@return MCP.PathfindingPosition
local function CopyPosition(position)
    return { x = position.x, y = position.y, z = position.z }
end

--- Return horizontal and vertical components of the distance between positions.
---@param first MCP.PathfindingPosition
---@param second MCP.PathfindingPosition
---@return number horizontalDistance
---@return number verticalDistance
local function Distances(first, second)
    local dx = first.x - second.x
    local dy = first.y - second.y
    return math.sqrt(dx * dx + dy * dy), math.abs(first.z - second.z)
end

--- Return a locator position from its direct position or marker position.
---@param locator MCP.PathfindingLocator
---@return (tes3vector3|MCP.PathfindingPosition)?
local function LocatorPosition(locator)
    if locator.position then
        return locator.position
    end
    if locator.marker then
        return locator.marker.position
    end
    return nil
end

--- Initialize an independent graph that only contains Lua snapshots.
---@param params MCP.PathfindingParams?
---@return MCP.Pathfinding
function this.new(params)
    ---@type MCP.Pathfinding
    local instance = {
        cells = {},
        gridCellIdByPosition = {},
        nodes = {},
        nodeIdsByCellId = {},
        edges = {},
        edgeIdByNeighborId = {},
        nextNodeId = 1,
        nextEdgeId = 1,
        exteriorCellSize = exteriorCellSize,
        stitchBorderMargin = 256,
        stitchMaxHorizontalDistance = 512,
        stitchMaxVerticalDistance = 256,
        cellActivatedCallback = nil,
        logger = require("morrowind-mcp.logger").Get({ moduleName = "pathfinding" }),
    }
    if params then
        -- Only configuration fields may override graph defaults.
        instance.exteriorCellSize = params.exteriorCellSize or instance.exteriorCellSize
        instance.stitchBorderMargin = params.stitchBorderMargin or instance.stitchBorderMargin
        instance.stitchMaxHorizontalDistance = params.stitchMaxHorizontalDistance or instance.stitchMaxHorizontalDistance
        instance.stitchMaxVerticalDistance = params.stitchMaxVerticalDistance or instance.stitchMaxVerticalDistance
    end
    setmetatable(instance, { __index = this })
    return instance
end

--- Remove an edge from the graph and both endpoint adjacency lists.
---@param edgeId integer
function this:RemoveEdge(edgeId)
    local edge = self.edges[edgeId]
    if not edge then
        return
    end
    self.edges[edgeId] = nil
    if self.edgeIdByNeighborId[edge.fromId] then
        self.edgeIdByNeighborId[edge.fromId][edge.toId] = nil
    end
    if self.edgeIdByNeighborId[edge.toId] then
        self.edgeIdByNeighborId[edge.toId][edge.fromId] = nil
    end
end

--- Connect two nodes with one undirected edge, replacing an existing matching edge.
---@param fromId integer
---@param toId integer
---@param kind string?
---@return MCP.PathfindingEdge?
function this:ConnectUndirected(fromId, toId, kind)
    local from = self.nodes[fromId]
    local to = self.nodes[toId]
    if not from or not to or fromId == toId then
        return nil
    end

    local horizontalDistance, verticalDistance = Distances(from.position, to.position)
    local existingEdgeId = self.edgeIdByNeighborId[fromId] and self.edgeIdByNeighborId[fromId][toId]
    if existingEdgeId then
        self:RemoveEdge(existingEdgeId)
    end
    local edgeId = self.nextEdgeId
    self.nextEdgeId = self.nextEdgeId + 1
    local edge = {
        id = edgeId,
        fromId = fromId,
        toId = toId,
        kind = kind or "walk",
        horizontalDistance = horizontalDistance,
        verticalDistance = verticalDistance,
        surface = "unknown",
        blocked = false,
    }
    self.edges[edgeId] = edge
    self.edgeIdByNeighborId[fromId] = self.edgeIdByNeighborId[fromId] or {}
    self.edgeIdByNeighborId[toId] = self.edgeIdByNeighborId[toId] or {}
    self.edgeIdByNeighborId[fromId][toId] = edgeId
    self.edgeIdByNeighborId[toId][fromId] = edgeId
    return edge
end

--- Remove a cell snapshot and every edge that references its nodes.
---@param cellId string
function this:RemoveCell(cellId)
    local nodeIds = self.nodeIdsByCellId[cellId]
    if not nodeIds then
        self.cells[cellId] = nil
        return
    end
    for _, nodeId in ipairs(nodeIds) do
        local removedEdgeIds = {}
        for _, edgeId in pairs(self.edgeIdByNeighborId[nodeId] or {}) do
            table.insert(removedEdgeIds, edgeId)
        end
        for _, edgeId in ipairs(removedEdgeIds) do
            self:RemoveEdge(edgeId)
        end
        self.nodes[nodeId] = nil
        self.edgeIdByNeighborId[nodeId] = nil
    end
    local cell = self.cells[cellId]
    if cell and not cell.isInterior and cell.gridX and cell.gridY and self.gridCellIdByPosition[cell.gridX] then
        self.gridCellIdByPosition[cell.gridX][cell.gridY] = nil
    end
    self.nodeIdsByCellId[cellId] = nil
    self.cells[cellId] = nil
end

--- Return node IDs that are close enough to each exterior border to stitch.
---@param cell MCP.PathfindingCell
---@return MCP.PathfindingBorderNodeIds
function this:CollectBorderNodeIds(cell)
    local borderNodeIds = { west = {}, east = {}, south = {}, north = {} }
    if cell.isInterior then
        return borderNodeIds
    end
    for _, nodeId in ipairs(self.nodeIdsByCellId[cell.id]) do
        local position = self.nodes[nodeId].position
        if math.abs(position.x - cell.gridX * self.exteriorCellSize) <= self.stitchBorderMargin then
            table.insert(borderNodeIds.west, nodeId)
        end
        if math.abs(position.x - (cell.gridX + 1) * self.exteriorCellSize) <= self.stitchBorderMargin then
            table.insert(borderNodeIds.east, nodeId)
        end
        if math.abs(position.y - cell.gridY * self.exteriorCellSize) <= self.stitchBorderMargin then
            table.insert(borderNodeIds.south, nodeId)
        end
        if math.abs(position.y - (cell.gridY + 1) * self.exteriorCellSize) <= self.stitchBorderMargin then
            table.insert(borderNodeIds.north, nodeId)
        end
    end
    return borderNodeIds
end

--- Connect border nodes only when their remaining horizontal and vertical gaps are traversable.
---@param nodeIds MCP.PathfindingNodeIds
---@param neighborNodeIds MCP.PathfindingNodeIds
function this:StitchBorderNodeIds(nodeIds, neighborNodeIds)
    for _, nodeId in ipairs(nodeIds) do
        local node = self.nodes[nodeId]
        for _, neighborNodeId in ipairs(neighborNodeIds) do
            local neighborNode = self.nodes[neighborNodeId]
            local horizontalDistance, verticalDistance = Distances(node.position, neighborNode.position)
            if horizontalDistance <= self.stitchMaxHorizontalDistance and verticalDistance <= self.stitchMaxVerticalDistance then
                self:ConnectUndirected(nodeId, neighborNodeId, "walk")
            end
        end
    end
end

--- Add eligible cross-border walk edges using the exterior coordinate index.
---@param cellId string
function this:StitchExteriorCell(cellId)
    local cell = self.cells[cellId]
    if not cell or cell.isInterior then
        return
    end
    local westId = self.gridCellIdByPosition[cell.gridX - 1] and self.gridCellIdByPosition[cell.gridX - 1][cell.gridY]
    local eastId = self.gridCellIdByPosition[cell.gridX + 1] and self.gridCellIdByPosition[cell.gridX + 1][cell.gridY]
    local southId = self.gridCellIdByPosition[cell.gridX] and self.gridCellIdByPosition[cell.gridX][cell.gridY - 1]
    local northId = self.gridCellIdByPosition[cell.gridX] and self.gridCellIdByPosition[cell.gridX][cell.gridY + 1]
    if westId then
        self:StitchBorderNodeIds(cell.borderNodeIds.west, self.cells[westId].borderNodeIds.east)
    end
    if eastId then
        self:StitchBorderNodeIds(cell.borderNodeIds.east, self.cells[eastId].borderNodeIds.west)
    end
    if southId then
        self:StitchBorderNodeIds(cell.borderNodeIds.south, self.cells[southId].borderNodeIds.north)
    end
    if northId then
        self:StitchBorderNodeIds(cell.borderNodeIds.north, self.cells[northId].borderNodeIds.south)
    end
end

--- Snapshot a loaded cell pathgrid without retaining any MWSE object references.
---@param cell tes3cell
---@return boolean updated
function this:UpdateCell(cell)
    if not cell or not cell.id or not cell.pathGrid or not cell.pathGrid.isLoaded then
        self.logger:debug("Skipping pathgrid snapshot because the cell is unavailable or unloaded.")
        return false
    end
    if self.cells[cell.id] then
        self.logger:debug("Skipping pathgrid reconstruction because the cell is already snapshotted: cell=%s", cell.id)
        return true
    end
    self.cells[cell.id] = {
        id = cell.id,
        isInterior = cell.isInterior,
        gridX = cell.gridX,
        gridY = cell.gridY,
        waterLevel = cell.waterLevel,
        borderNodeIds = { west = {}, east = {}, south = {}, north = {} },
    }
    self.nodeIdsByCellId[cell.id] = {}

    ---@type table<tes3pathGridNode, integer>
    local nodeIdsByPathgridNode = {}
    for index, pathgridNode in ipairs(cell.pathGrid.nodes) do
        local nodeId = self.nextNodeId
        self.nextNodeId = self.nextNodeId + 1
        self.nodes[nodeId] = { id = nodeId, cellId = cell.id, position = CopyPosition(pathgridNode.position) }
        self.edgeIdByNeighborId[nodeId] = {}
        self.nodeIdsByCellId[cell.id][index] = nodeId
        nodeIdsByPathgridNode[pathgridNode] = nodeId
    end
    for _, pathgridNode in ipairs(cell.pathGrid.nodes) do
        for _, connectedNode in ipairs(pathgridNode.connectedNodes) do
            local toId = nodeIdsByPathgridNode[connectedNode]
            if toId then
                self:ConnectUndirected(nodeIdsByPathgridNode[pathgridNode], toId, "walk")
            end
        end
    end
    local cellSnapshot = self.cells[cell.id]
    cellSnapshot.borderNodeIds = self:CollectBorderNodeIds(cellSnapshot)
    if not cellSnapshot.isInterior then
        self.gridCellIdByPosition[cellSnapshot.gridX] = self.gridCellIdByPosition[cellSnapshot.gridX] or {}
        self.gridCellIdByPosition[cellSnapshot.gridX][cellSnapshot.gridY] = cellSnapshot.id
    end
    self:StitchExteriorCell(cell.id)
    self.logger:debug("Snapshotted pathgrid: cell=%s nodes=%d edges=%d", cell.id, table.size(self.nodeIdsByCellId[cell.id]), table.size(self.edges))
    return true
end

--- Find the nearest stored node in the locator's cell using a cheap brute-force scan.
---@param locator MCP.PathfindingLocator
---@param weights MCP.PathfindingNearestWeights?
---@return MCP.PathfindingNode?
function this:FindNearestNode(locator, weights)
    if not locator.cell or not locator.cell.id then
        return nil
    end
    local position = LocatorPosition(locator)
    if not position then
        return nil
    end
    weights = weights or {}
    local horizontalWeight = weights.horizontal or 1
    local verticalWeight = weights.vertical or 1
    local nearestNode = nil
    local nearestScore = nil
    for _, nodeId in ipairs(self.nodeIdsByCellId[locator.cell.id] or {}) do
        local node = self.nodes[nodeId]
        local dx = node.position.x - position.x
        local dy = node.position.y - position.y
        local dz = node.position.z - position.z
        local score = (dx * dx + dy * dy) * horizontalWeight + dz * dz * verticalWeight
        if not nearestScore or score < nearestScore then
            nearestNode = node
            nearestScore = score
        end
    end
    return nearestNode
end

--- Change learned terrain information without modifying the immutable pathgrid snapshot.
---@param edgeId integer
---@param surface string
---@return boolean updated
function this:SetEdgeSurface(edgeId, surface)
    local edge = self.edges[edgeId]
    if not edge then
        return false
    end
    edge.surface = surface
    self.logger:debug("Updated pathfinding edge surface: edgeId=%d surface=%s", edgeId, surface)
    return true
end

--- Block or restore an edge after runtime movement discovers an obstruction.
---@param edgeId integer
---@param blocked boolean
---@return boolean updated
function this:SetEdgeBlocked(edgeId, blocked)
    local edge = self.edges[edgeId]
    if not edge then
        return false
    end
    edge.blocked = blocked
    self.logger:debug("Updated pathfinding edge blockage: edgeId=%d blocked=%s", edgeId, tostring(blocked))
    return true
end

--- Calculate traversal cost using distance weights and current movement abilities.
---@param edge MCP.PathfindingEdge
---@param options MCP.PathfindingOptions?
---@return number
function this:EdgeCost(edge, options)
    options = options or {}
    local surfaceWeight = 1
    if edge.surface == "water" then
        surfaceWeight = options.waterWalking and (options.waterWalkingWeight or 1) or (options.waterWeight or 2)
    end
    return (edge.horizontalDistance * (options.horizontalWeight or 1) + edge.verticalDistance * (options.verticalWeight or 1)) * surfaceWeight
end

--- Return a distance-only heuristic; shortcut edges can disable it to retain optimality.
---@param node MCP.PathfindingNode
---@param destination MCP.PathfindingNode
---@param options MCP.PathfindingOptions?
---@return number
function this:Heuristic(node, destination, options)
    options = options or {}
    if options.useHeuristic == false then
        return 0
    end
    local horizontalDistance, verticalDistance = Distances(node.position, destination.position)
    return horizontalDistance * (options.horizontalWeight or 1) + verticalDistance * (options.verticalWeight or 1)
end

--- Find a route over the stored graph with A*, returning nil when no route is known.
---@param start MCP.PathfindingLocator
---@param destination MCP.PathfindingLocator
---@param options MCP.PathfindingOptions?
---@return MCP.PathfindingResult?
function this:FindPath(start, destination, options)
    local startNode = self:FindNearestNode(start, options and options.nearestWeights)
    local destinationNode = self:FindNearestNode(destination, options and options.nearestWeights)
    if not startNode or not destinationNode then
        self.logger:debug("Pathfinding skipped because a start or destination node is unavailable.")
        return nil
    end
    ---@type MCP.PathfindingOpenEntry[]
    local open = { { nodeId = startNode.id, score = self:Heuristic(startNode, destinationNode, options) } }
    ---@type MCP.PathfindingCosts
    local costs = { [startNode.id] = 0 }
    ---@type MCP.PathfindingPrevious
    local previous = {}
    ---@type MCP.PathfindingClosed
    local closed = {}
    while table.size(open) > 0 do
        local bestIndex = 1
        for index = 2, #open do
            if open[index].score < open[bestIndex].score then
                bestIndex = index
            end
        end
        local current = table.remove(open, bestIndex)
        if not closed[current.nodeId] then
            closed[current.nodeId] = true
            if current.nodeId == destinationNode.id then
                ---@type integer[]
                local nodeIds = {}
                ---@type integer[]
                local edgeIds = {}
                local nodeId = destinationNode.id ---@type integer?
                while nodeId do
                    table.insert(nodeIds, 1, nodeId)
                    local prior = previous[nodeId]
                    if prior then
                        table.insert(edgeIds, 1, prior.edgeId)
                        nodeId = prior.nodeId
                    else
                        nodeId = nil
                    end
                end
                local result = { nodeIds = nodeIds, edgeIds = edgeIds, cost = costs[destinationNode.id] }
                self.logger:debug("Path found: startNodeId=%d destinationNodeId=%d nodes=%d cost=%.2f", startNode.id, destinationNode.id, table.size(result.nodeIds), result.cost)
                return result
            end
            for neighborId, edgeId in pairs(self.edgeIdByNeighborId[current.nodeId] or {}) do
                local edge = self.edges[edgeId]
                if edge and not edge.blocked then
                    if not closed[neighborId] then
                        local nextCost = costs[current.nodeId] + self:EdgeCost(edge, options)
                        if not costs[neighborId] or nextCost < costs[neighborId] then
                            costs[neighborId] = nextCost
                            previous[neighborId] = { nodeId = current.nodeId, edgeId = edgeId }
                            table.insert(open, { nodeId = neighborId, score = nextCost + self:Heuristic(self.nodes[neighborId], destinationNode, options) })
                        end
                    end
                end
            end
        end
    end
    self.logger:debug("No path found: startNodeId=%d destinationNodeId=%d", startNode.id, destinationNode.id)
    return nil
end

--- Register cell activation updates and retain the callback for server shutdown.
function this:RegisterEventHandlers()
    self.cellActivatedCallback = function(e)
        self:UpdateCell(e.cell)
    end
    event.register(tes3.event.cellActivated, self.cellActivatedCallback)
    self.logger:debug("Registered pathfinding cell activation handler.")
end

--- Unregister the activation callback before the server instance is discarded.
function this:UnregisterEventHandlers()
    if not self.cellActivatedCallback then
        return
    end
    event.unregister(tes3.event.cellActivated, self.cellActivatedCallback)
    self.cellActivatedCallback = nil
    self.logger:debug("Unregistered pathfinding cell activation handler.")
end

return this
