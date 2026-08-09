--- Builds plain mesh descriptions for debug visualization without using MWSE scene graph objects.
local this = {}

---@class MCP.VisualizationPosition
---@field x number
---@field y number
---@field z number

---@class MCP.VisualizationColor
---@field r integer
---@field g integer
---@field b integer
---@field a integer

---@class MCP.VisualizationRibbon
---@field from MCP.VisualizationPosition
---@field to MCP.VisualizationPosition
---@field color MCP.VisualizationColor

---@class MCP.VisualizationMesh
---@field vertices MCP.VisualizationPosition[]
---@field colors MCP.VisualizationColor[]
---@field triangles niTriangle[]

--- Build camera-independent vertical ribbons for a batch of world-space edges.
--- Zero-length edges are skipped because they cannot define a horizontal width direction.
---@param ribbons MCP.VisualizationRibbon[]
---@param width number
---@param zOffset number?
---@return MCP.VisualizationMesh mesh
function this.BuildRibbonBatch(ribbons, width, zOffset)
    local ribbonCount = table.size(ribbons)
    local mesh = {
        vertices = table.new(ribbonCount * 4, 0),
        colors = table.new(ribbonCount * 4, 0),
        triangles = table.new(ribbonCount * 2, 0),
    }
    local halfWidth = width / 2
    local offset = zOffset or 0
    for _, ribbon in ipairs(ribbons) do
        local dx = ribbon.to.x - ribbon.from.x
        local dy = ribbon.to.y - ribbon.from.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0 then
            local perpendicularX = -dy / length * halfWidth
            local perpendicularY = dx / length * halfWidth
            local firstIndex = table.size(mesh.vertices)
            local fromZ = ribbon.from.z + offset
            local toZ = ribbon.to.z + offset
            table.insert(mesh.vertices, { x = ribbon.from.x + perpendicularX, y = ribbon.from.y + perpendicularY, z = fromZ })
            table.insert(mesh.vertices, { x = ribbon.from.x - perpendicularX, y = ribbon.from.y - perpendicularY, z = fromZ })
            table.insert(mesh.vertices, { x = ribbon.to.x - perpendicularX, y = ribbon.to.y - perpendicularY, z = toZ })
            table.insert(mesh.vertices, { x = ribbon.to.x + perpendicularX, y = ribbon.to.y + perpendicularY, z = toZ })
            for _ = 1, 4 do
                table.insert(mesh.colors, ribbon.color)
            end
            table.insert(mesh.triangles, { firstIndex, firstIndex + 1, firstIndex + 2 })
            table.insert(mesh.triangles, { firstIndex, firstIndex + 2, firstIndex + 3 })
        end
    end
    return mesh
end

--- Reuse matching position and color entries so connected ribbons need fewer vertices.
---@param mesh MCP.VisualizationMesh
---@return MCP.VisualizationMesh
function this.IndexSharedVertices(mesh)
    local triangleCount = table.size(mesh.triangles)
    local indexed = {
        vertices = table.new(table.size(mesh.vertices), 0),
        colors = table.new(table.size(mesh.colors), 0),
        triangles = table.new(triangleCount, 0),
    }
    local indicesByKey = table.new(0, table.size(mesh.vertices))
    for _, triangle in ipairs(mesh.triangles) do
        local indexedTriangle = table.new(3, 0)
        for _, sourceIndex in ipairs(triangle) do
            local vertex = mesh.vertices[sourceIndex + 1]
            local color = mesh.colors[sourceIndex + 1]
            local key = string.format("%.9g:%.9g:%.9g:%d:%d:%d:%d", vertex.x, vertex.y, vertex.z, color.r, color.g, color.b, color.a)
            local index = indicesByKey[key]
            if index == nil then
                index = table.size(indexed.vertices)
                indicesByKey[key] = index
                table.insert(indexed.vertices, vertex)
                table.insert(indexed.colors, color)
            end
            table.insert(indexedTriangle, index)
        end
        table.insert(indexed.triangles, indexedTriangle)
    end
    return indexed
end

--- Build one color-coded ribbon mesh from horizontal and vertical walkable grid connections.
--- Only positive coordinate directions are emitted so each undirected connection is rendered once.
---@param grid MCP.TerrainGrid
---@param color MCP.VisualizationColor
---@param zOffset number?
---@param width number?
---@return MCP.VisualizationMesh mesh
function this.BuildWalkableGridRibbonBatch(grid, color, zOffset, width)
    local maxRibbonCount = grid.width * (grid.height - 1) + grid.height * (grid.width - 1)
    local ribbons = table.new(maxRibbonCount, 0)
    for row = 0, grid.height - 1 do
        for column = 0, grid.width - 1 do
            local fromIndex = grid:Index(column, row)
            if grid:IsWalkable(fromIndex) then
                local rightIndex = grid:Index(column + 1, row)
                if rightIndex and grid:IsWalkable(rightIndex) then
                    table.insert(ribbons, {
                        from = grid:WorldPosition(fromIndex),
                        to = grid:WorldPosition(rightIndex),
                        color = color,
                    })
                end
                local northIndex = grid:Index(column, row + 1)
                if northIndex and grid:IsWalkable(northIndex) then
                    table.insert(ribbons, {
                        from = grid:WorldPosition(fromIndex),
                        to = grid:WorldPosition(northIndex),
                        color = color,
                    })
                end
            end
        end
    end
    return this.IndexSharedVertices(this.BuildRibbonBatch(ribbons, width or grid.interval * 0.06, zOffset))
end

--- Build horizontal quads for graph nodes without creating one scene object per node.
---@param points MCP.VisualizationPosition[]
---@param color MCP.VisualizationColor
---@param size number
---@param zOffset number?
---@return MCP.VisualizationMesh mesh
function this.BuildPointQuadBatch(points, color, size, zOffset)
    local pointCount = table.size(points)
    local mesh = {
        vertices = table.new(pointCount * 4, 0),
        colors = table.new(pointCount * 4, 0),
        triangles = table.new(pointCount * 2, 0),
    }
    local halfSize = size / 2
    local offset = zOffset or 0
    for _, point in ipairs(points) do
        local firstIndex = table.size(mesh.vertices)
        local z = point.z + offset
        table.insert(mesh.vertices, { x = point.x - halfSize, y = point.y - halfSize, z = z })
        table.insert(mesh.vertices, { x = point.x + halfSize, y = point.y - halfSize, z = z })
        table.insert(mesh.vertices, { x = point.x + halfSize, y = point.y + halfSize, z = z })
        table.insert(mesh.vertices, { x = point.x - halfSize, y = point.y + halfSize, z = z })
        for _ = 1, 4 do
            table.insert(mesh.colors, color)
        end
        table.insert(mesh.triangles, { firstIndex, firstIndex + 1, firstIndex + 2 })
        table.insert(mesh.triangles, { firstIndex, firstIndex + 2, firstIndex + 3 })
    end
    return mesh
end

return this
