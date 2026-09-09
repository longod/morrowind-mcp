--- Renders read-only pathfinding and terrain snapshots as world-space debug geometry.
local meshBuilder = require("morrowind-mcp.navigation.visualization_mesh")
local cellutil = require("morrowind-mcp.tes3.cell")

local this = {}

---@alias MCP.NavigationVisualizerColor MCP.VisualizationColor

---@class MCP.NavigationVisualizerOptions
---@field enabled boolean
---@field graphEnabled boolean
---@field terrainEnabled boolean
---@field depthTest boolean
---@field graphWidth number
---@field graphOffset number
---@field graphPointSize number
---@field terrainWidth number
---@field terrainOffset number
---@field walkColor MCP.NavigationVisualizerColor
---@field nodeColor MCP.NavigationVisualizerColor
---@field blockedColor MCP.NavigationVisualizerColor
---@field travelColor MCP.NavigationVisualizerColor
---@field travelDoorColor MCP.NavigationVisualizerColor
---@field waterColor MCP.NavigationVisualizerColor
---@field terrainColor MCP.NavigationVisualizerColor

---@class MCP.NavigationVisualizer
---@field logger mwseLogger
---@field pathfinding MCP.Pathfinding
---@field terrainGridManager MCP.TerrainGridManager
---@field options MCP.NavigationVisualizerOptions
---@field root niNode?
---@field parent niNode?
---@field terrainRoot niNode?
---@field graphRoot niNode?
---@field graphRoots table<MCP.CellIdentityKey, niNode>
---@field terrainShapes table<MCP.CellIdentityKey, niTriShape>
---@field vertexColor niVertexColorProperty?
---@field stencil niStencilProperty?
---@field zBuffer niZBufferProperty?
---@field refreshCounter integer
---@field refreshRequested boolean
---@field graphRefreshRequested boolean
---@field graphRefreshAll boolean
---@field graphRefreshCellIds table<MCP.CellIdentityKey, boolean>
---@field terrainRefreshAll boolean
---@field terrainRefreshCellIds table<MCP.CellIdentityKey, boolean>
---@field Refresh fun(self: MCP.NavigationVisualizer)
---@field Tick fun(self: MCP.NavigationVisualizer)
---@field Remove fun(self: MCP.NavigationVisualizer)
---@field RequestRefresh fun(self: MCP.NavigationVisualizer, layer: "graph"|"terrain"?, cellId: MCP.CellIdentityKey?)
---@field SetEnabled fun(self: MCP.NavigationVisualizer, enabled: boolean)
---@field SetGraphEnabled fun(self: MCP.NavigationVisualizer, enabled: boolean)
---@field SetTerrainEnabled fun(self: MCP.NavigationVisualizer, enabled: boolean)

local defaultOptions = {
    enabled = true,
    graphEnabled = true,
    terrainEnabled = true,
    depthTest = true,
    graphWidth = 4,
    graphOffset = 4,
    graphPointSize = 16,
    terrainWidth = 4,
    terrainOffset = 4,
    walkColor = { r = 48, g = 224, b = 255, a = 255 },
    nodeColor = { r = 255, g = 64, b = 64, a = 255 },
    blockedColor = { r = 255, g = 72, b = 72, a = 255 },
    travelColor = { r = 255, g = 216, b = 72, a = 255 },
    travelDoorColor = { r = 255, g = 64, b = 224, a = 255 },
    waterColor = { r = 72, g = 128, b = 255, a = 255 },
    terrainColor = { r = 72, g = 255, b = 128, a = 255 },
}

--- Return graph cells affected by a source-cell change, including every directly connected neighbor.
--- The graph stores adjacency by node, which avoids a full edge-table scan when scheduling a refresh.
---@param pathfinding MCP.Pathfinding
---@param cellId MCP.CellIdentityKey
---@return table<MCP.CellIdentityKey, boolean>
function this.GetGraphRefreshCellIds(pathfinding, cellId)
    local nodeIds = pathfinding.nodeIdsByCellId[cellId] or {}
    local cellIds = table.new(0, table.size(nodeIds) + 1)
    cellIds[cellId] = true
    for _, nodeId in ipairs(nodeIds) do
        for _, edgeId in pairs(pathfinding.edgeIdByNeighborId[nodeId] or {}) do
            local edge = pathfinding.edges[edgeId]
            if edge then
                local from = pathfinding.nodes[edge.fromId]
                local destination = pathfinding.nodes[edge.toId]
                if from then
                    cellIds[from.cellId] = true
                end
                if destination then
                    cellIds[destination.cellId] = true
                end
            end
        end
    end
    return cellIds
end

--- Merge persisted scalar settings with complete render defaults, including colors not exposed in the config file.
---@param options MCP.NavigationVisualizerOptions?
---@return MCP.NavigationVisualizerOptions
local function MergeOptions(options)
    local merged = {}
    for key, value in pairs(defaultOptions) do
        merged[key] = value
    end
    for key, value in pairs(options or {}) do
        merged[key] = value
    end
    return merged
end

--- Create a debug-only visualizer that never owns or mutates navigation source data.
---@param pathfinding MCP.Pathfinding
---@param terrainGridManager MCP.TerrainGridManager
---@param options MCP.NavigationVisualizerOptions?
---@return MCP.NavigationVisualizer
function this.new(pathfinding, terrainGridManager, options)
    local instance = {
        logger = require("morrowind-mcp.logger").Get({ moduleName = "navigation_visualizer" }),
        pathfinding = pathfinding,
        terrainGridManager = terrainGridManager,
        options = MergeOptions(options),
        root = nil,
        parent = nil,
        terrainRoot = nil,
        graphRoot = nil,
        graphRoots = {},
        terrainShapes = {},
        vertexColor = nil,
        stencil = nil,
        zBuffer = nil,
        refreshRequested = true,
        graphRefreshRequested = true,
        graphRefreshAll = true,
        graphRefreshCellIds = {},
        terrainRefreshAll = true,
        terrainRefreshCellIds = {},
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Create shared opaque render states for every shape owned by this visualizer.
---@param self MCP.NavigationVisualizer
local function EnsureRenderStates(self)
    if not self.vertexColor then
        self.vertexColor = niVertexColorProperty.new()
        self.vertexColor.lighting = ni.lightingMode.emissive
        self.vertexColor.source = ni.sourceVertexMode.emissive
    end
    if not self.stencil then
        self.stencil = niStencilProperty.new()
        self.stencil.enabled = true
        self.stencil.testFunc = ni.stencilTestFunction.always
        self.stencil.failAction = ni.stencilTestAction.keep
        self.stencil.passAction = ni.stencilTestAction.keep
        self.stencil.zFailAction = ni.stencilTestAction.keep
        self.stencil.drawMode = ni.stencilDrawMode.both
    end
    if not self.zBuffer then
        self.zBuffer = niZBufferProperty.new()
        self.zBuffer.testFunction = ni.zBufferPropertyTestFunction.lessEqual
    end
    -- NiZBufferProperty uses flag zero for testing and flag one for depth writes.
    -- Preserve the world's depth buffer while allowing settings to switch occlusion on or off.
    self.zBuffer:setFlag(self.options.depthTest, 0)
    self.zBuffer:setFlag(false, 1)
end

--- Convert one plain mesh description into an emissive, double-sided world-space shape.
---@param self MCP.NavigationVisualizer
---@param name string
---@param mesh MCP.VisualizationMesh
---@return niTriShape?
local function CreateShape(self, name, mesh)
    if table.size(mesh.vertices) == 0 or table.size(mesh.triangles) == 0 then
        return nil
    end
    local shape = niTriShape.new(table.size(mesh.vertices), false, true, 0, table.size(mesh.triangles))
    shape.name = name
    for index, vertex in ipairs(mesh.vertices) do
        shape.data.vertices[index] = tes3vector3.new(vertex.x, vertex.y, vertex.z)
        local color = mesh.colors[index]
        shape.data.colors[index] = niPackedColor.new(color.r, color.g, color.b, color.a)
    end
    for index, triangle in ipairs(mesh.triangles) do
        shape.data.triangles[index] = niTriangle.new(triangle[1], triangle[2], triangle[3])
    end
    shape.data.activeTriangleCount = table.size(mesh.triangles)
    shape.data:markAsChanged()
    shape.data:updateModelBound()
    shape.vertexColorProperty = self.vertexColor
    shape.stencilProperty = self.stencil
    shape.zBufferProperty = self.zBuffer
    return shape
end

---@return table<MCP.CellIdentityKey, boolean>
local function GetActiveCellIds()
    local activeCells = tes3.getActiveCells()
    local activeCellIds = table.new(0, table.size(activeCells))
    for _, cell in ipairs(activeCells) do
        local cellId = cellutil.GetIdentityKey(cell)
        if cellId then
            activeCellIds[cellId] = true
        end
    end
    return activeCellIds
end

--- Build graph edge batches for one active source cell.
---@param self MCP.NavigationVisualizer
---@param cellId MCP.CellIdentityKey
---@param activeCellIds table<MCP.CellIdentityKey, boolean>
---@return table<string, MCP.VisualizationMesh>
local function BuildGraphMeshes(self, cellId, activeCellIds)
    local ribbonsByKind = { walk = {}, blocked = {}, travel = {}, water = {} }
    local travelDoorPoints = {}
    for _, nodeId in ipairs(self.pathfinding.nodeIdsByCellId[cellId] or {}) do
        for _, edgeId in pairs(self.pathfinding.edgeIdByNeighborId[nodeId] or {}) do
            local edge = self.pathfinding.edges[edgeId]
            local from = edge and self.pathfinding.nodes[edge.fromId] or nil
            local destination = edge and self.pathfinding.nodes[edge.toId] or nil
            -- An undirected edge is present in both node adjacency maps; emit it from its canonical source once.
            if edge and edge.kind ~= self.pathfinding.edgeKind.travel and edge.fromId == nodeId and from and destination
                and activeCellIds[destination.cellId] then
                local key = "walk"
                local color = self.options.walkColor
                if edge.blocked then
                    key, color = "blocked", self.options.blockedColor
                elseif edge.surface == self.pathfinding.edgeSurface.water then
                    key, color = "water", self.options.waterColor
                end
                table.insert(ribbonsByKind[key], { from = from.position, to = destination.position, color = color })
            end
        end
    end
    for _, travelDestination in ipairs(self.pathfinding.travelDestinationsByCellId[cellId] or {}) do
        local sourceNode = self.pathfinding:FindNearestNodeByPosition(cellId, travelDestination.doorPosition)
        if sourceNode then
            table.insert(ribbonsByKind.travel, {
                from = sourceNode.position,
                to = travelDestination.doorPosition,
                color = self.options.travelColor,
            })
            table.insert(travelDoorPoints, travelDestination.doorPosition)
        end
    end
    local meshes = {}
    for key, ribbons in pairs(ribbonsByKind) do
        meshes[key] = meshBuilder.BuildRibbonBatch(ribbons, self.options.graphWidth, self.options.graphOffset)
    end
    meshes.travelDoors = meshBuilder.BuildPointQuadBatch(
        travelDoorPoints, self.options.travelDoorColor, self.options.graphPointSize, self.options.graphOffset)
    return meshes
end

--- Build one batched quad marker for nodes belonging to one active cell.
---@param self MCP.NavigationVisualizer
---@param cellId MCP.CellIdentityKey
---@return MCP.VisualizationMesh mesh
local function BuildGraphPointMesh(self, cellId)
    local nodeIds = self.pathfinding.nodeIdsByCellId[cellId] or {}
    local points = table.new(table.size(nodeIds), 0)
    for _, nodeId in ipairs(nodeIds) do
        local node = self.pathfinding.nodes[nodeId]
        if node then
            table.insert(points, node.position)
        end
    end
    return meshBuilder.BuildPointQuadBatch(points, self.options.nodeColor, self.options.graphPointSize, self.options.graphOffset)
end

--- Attach the dedicated root below the game world root after it becomes available.
---@param self MCP.NavigationVisualizer
---@return boolean attached
local function EnsureRoot(self)
    if self.root and self.parent then
        return true
    end
    local parent = tes3.game and tes3.game.worldRoot or nil
    if not parent then
        return false
    end
    self.root = niNode.new()
    self.root.name = "MorrowindMCP:NavigationVisualizer"
    self.terrainRoot = niNode.new()
    self.terrainRoot.name = "MorrowindMCP:NavigationVisualizer:Terrain"
    self.graphRoot = niNode.new()
    self.graphRoot.name = "MorrowindMCP:NavigationVisualizer:Graph"
    self.root:attachChild(self.terrainRoot)
    self.root:attachChild(self.graphRoot)
    self.parent = parent
    parent:attachChild(self.root)
    parent:update()
    return true
end

--- Detach all generated shapes while retaining the dedicated root for a later refresh.
---@param self MCP.NavigationVisualizer
local function ClearTerrainShapes(self)
    if self.terrainRoot then
        self.terrainRoot:detachAllChildren()
    end
    self.terrainShapes = {}
end

---@param self MCP.NavigationVisualizer
---@param cellId MCP.CellIdentityKey
local function RemoveGraphCell(self, cellId)
    local root = self.graphRoots[cellId]
    if root and self.graphRoot then
        self.graphRoot:detachChild(root)
    end
    self.graphRoots[cellId] = nil
end

---@param self MCP.NavigationVisualizer
local function ClearGraphCells(self)
    if self.graphRoot then
        self.graphRoot:detachAllChildren()
    end
    self.graphRoots = {}
end

---@param self MCP.NavigationVisualizer
---@param cellId MCP.CellIdentityKey
---@param activeCellIds table<MCP.CellIdentityKey, boolean>
local function RefreshGraphCell(self, cellId, activeCellIds)
    RemoveGraphCell(self, cellId)
    if not self.options.graphEnabled or not activeCellIds[cellId] or not self.graphRoot then
        return
    end
    local root = niNode.new()
    root.name = "MorrowindMCP:Graph:" .. cellId
    local graphMeshes = BuildGraphMeshes(self, cellId, activeCellIds)
    for _, key in ipairs({ "walk", "water", "travel", "blocked" }) do
        local shape = CreateShape(self, "MorrowindMCP:Graph:" .. cellId .. ":" .. key, graphMeshes[key])
        if shape then
            root:attachChild(shape)
        end
    end
    local travelDoorShape = CreateShape(self, "MorrowindMCP:Graph:" .. cellId .. ":travelDoors", graphMeshes.travelDoors)
    if travelDoorShape then
        root:attachChild(travelDoorShape)
    end
    local pointShape = CreateShape(self, "MorrowindMCP:Graph:" .. cellId .. ":points", BuildGraphPointMesh(self, cellId))
    if pointShape then
        root:attachChild(pointShape)
    end
    self.graphRoot:attachChild(root)
    self.graphRoots[cellId] = root
end

---@param self MCP.NavigationVisualizer
---@param cellId MCP.CellIdentityKey
local function RefreshTerrainCell(self, cellId)
    local existing = self.terrainShapes[cellId]
    if existing and self.terrainRoot then
        self.terrainRoot:detachChild(existing)
    end
    self.terrainShapes[cellId] = nil
    local grid = self.terrainGridManager.grids[cellId]
    if grid and self.options.terrainEnabled and self.terrainRoot then
        local mesh = meshBuilder.BuildWalkableGridRibbonBatch(grid, self.options.terrainColor, self.options.terrainOffset, self.options.terrainWidth)
        local shape = CreateShape(self, "MorrowindMCP:Terrain:" .. cellId, mesh)
        if shape then
            self.terrainRoot:attachChild(shape)
            self.terrainShapes[cellId] = shape
        end
    end
end

--- Rebuild the complete read-only scene representation after its source signature changes.
---@param self MCP.NavigationVisualizer
function this:Refresh()
    if not self.options.enabled or (not self.options.graphEnabled and not self.options.terrainEnabled) then
        self:Remove()
        return
    end
    if not EnsureRoot(self) then
        return
    end
    EnsureRenderStates(self)
    if not self.options.terrainEnabled then
        ClearTerrainShapes(self)
    elseif self.terrainRefreshAll then
        ClearTerrainShapes(self)
        for cellId in pairs(self.terrainGridManager.grids) do
            RefreshTerrainCell(self, cellId)
        end
    else
        for cellId in pairs(self.terrainRefreshCellIds) do
            RefreshTerrainCell(self, cellId)
        end
    end
    if not self.options.graphEnabled then
        ClearGraphCells(self)
    elseif self.graphRefreshRequested then
        local activeCellIds = GetActiveCellIds()
        if self.graphRefreshAll then
            ClearGraphCells(self)
            for cellId in pairs(activeCellIds) do
                RefreshGraphCell(self, cellId, activeCellIds)
            end
        else
            for cellId in pairs(self.graphRefreshCellIds) do
                RefreshGraphCell(self, cellId, activeCellIds)
            end
        end
    end
    self.root:update()
    self.parent:update()
    self.graphRefreshRequested = false
    self.graphRefreshAll = false
    self.graphRefreshCellIds = {}
    self.terrainRefreshAll = false
    self.terrainRefreshCellIds = {}
    self.refreshRequested = false
    self.logger:debug("Rebuilt navigation visualization: graphEdges=%d terrainCells=%d", table.size(self.pathfinding.edges), table.size(self.terrainGridManager.grids))
end

--- Schedule a layer refresh after navigation source state changes.
---@param layer "graph"|"terrain"?
---@param cellId MCP.CellIdentityKey?
function this:RequestRefresh(layer, cellId)
    if layer == "graph" then
        self.graphRefreshRequested = true
        if cellId then
            for affectedCellId in pairs(this.GetGraphRefreshCellIds(self.pathfinding, cellId)) do
                self.graphRefreshCellIds[affectedCellId] = true
            end
        else
            self.graphRefreshAll = true
        end
    elseif layer == "terrain" then
        if cellId then
            self.terrainRefreshCellIds[cellId] = true
        else
            self.terrainRefreshAll = true
        end
    else
        self.graphRefreshRequested = true
        self.graphRefreshAll = true
        self.terrainRefreshAll = true
    end
    self.refreshRequested = true
end

--- Enable or disable every visualization layer without retaining stale scene geometry.
---@param enabled boolean
function this:SetEnabled(enabled)
    if self.options.enabled ~= enabled then
        self.options.enabled = enabled
        self:RequestRefresh()
    end
end

--- Enable or hide the pathfinding layer without changing pathfinding source data.
---@param enabled boolean
function this:SetGraphEnabled(enabled)
    if self.options.graphEnabled ~= enabled then
        self.options.graphEnabled = enabled
        self:RequestRefresh("graph")
    end
end

--- Enable or hide the terrain-grid layer without changing terrain source data.
---@param enabled boolean
function this:SetTerrainEnabled(enabled)
    if self.options.terrainEnabled ~= enabled then
        self.options.terrainEnabled = enabled
        self:RequestRefresh("terrain")
    end
end

--- Check for source changes at a bounded cadence instead of rebuilding every render frame.
---@param self MCP.NavigationVisualizer
function this:Tick()
    if self.refreshRequested then
        self:Refresh()
    end
end

--- Detach every visualizer object before the game replaces the world root or the server shuts down.
---@param self MCP.NavigationVisualizer
function this:Remove()
    if self.root and self.parent then
        self.parent:detachChild(self.root)
        self.parent:update()
    end
    self.root = nil
    self.parent = nil
    self.refreshRequested = false
    self.graphRefreshRequested = true
    self.graphRefreshAll = true
    self.graphRefreshCellIds = {}
    self.terrainRefreshAll = true
    self.terrainRefreshCellIds = {}
    self.terrainShapes = {}
    self.terrainRoot = nil
    self.graphRoot = nil
    self.graphRoots = {}
end

return this
