local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local visualizationMesh = require("morrowind-mcp.navigation.visualization_mesh")

    unitwind:start("morrowind-mcp.navigation.visualization_mesh")

    unitwind:test("BuildRibbonBatch generates an offset two-triangle ribbon", function()
        local color = { r = 10, g = 20, b = 30, a = 255 }
        local mesh = visualizationMesh.BuildRibbonBatch({
            { from = { x = 0, y = 0, z = 4 }, to = { x = 10, y = 0, z = 8 }, color = color },
        }, 4, 2)

        unitwind:expect(table.size(mesh.vertices)).toBe(4)
        unitwind:expect(table.size(mesh.colors)).toBe(4)
        unitwind:expect(table.size(mesh.triangles)).toBe(2)
        unitwind:expect(mesh.vertices[1].x).toBe(0)
        unitwind:expect(mesh.vertices[1].y).toBe(2)
        unitwind:expect(mesh.vertices[1].z).toBe(6)
        unitwind:expect(mesh.vertices[3].x).toBe(10)
        unitwind:expect(mesh.vertices[3].y).toBe(-2)
        unitwind:expect(mesh.vertices[3].z).toBe(10)
        unitwind:expect(mesh.triangles[1][1]).toBe(0)
        unitwind:expect(mesh.triangles[2][3]).toBe(3)
    end)

    unitwind:test("BuildRibbonBatch skips zero-length edges", function()
        local mesh = visualizationMesh.BuildRibbonBatch({
            { from = { x = 1, y = 1, z = 1 }, to = { x = 1, y = 1, z = 1 }, color = { r = 1, g = 2, b = 3, a = 255 } },
        }, 8)

        unitwind:expect(table.size(mesh.vertices)).toBe(0)
        unitwind:expect(table.size(mesh.triangles)).toBe(0)
    end)

    unitwind:test("BuildWalkableGridRibbonBatch emits each walkable cardinal edge once", function()
        local grid = {
            width = 2,
            height = 2,
            interval = 100,
            Index = function(_, column, row)
                if column < 0 or row < 0 or column >= 2 or row >= 2 then
                    return nil
                end
                return row * 2 + column + 1
            end,
            IsWalkable = function(_, index)
                return index ~= 4
            end,
            WorldPosition = function(_, index)
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                return { x = column * 100, y = row * 100, z = 10 }
            end,
        }
        local mesh = visualizationMesh.BuildWalkableGridRibbonBatch(grid, { r = 1, g = 2, b = 3, a = 255 }, 5)

        unitwind:expect(table.size(mesh.vertices)).toBe(8)
        unitwind:expect(table.size(mesh.triangles)).toBe(4)
        unitwind:expect(mesh.vertices[1].z).toBe(15)
    end)

    unitwind:test("IndexSharedVertices preserves triangles while reusing matching vertices", function()
        local mesh = visualizationMesh.IndexSharedVertices({
            vertices = {
                { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 },
                { x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = -1, y = 0, z = 0 },
            },
            colors = {
                { r = 1, g = 2, b = 3, a = 255 }, { r = 1, g = 2, b = 3, a = 255 }, { r = 1, g = 2, b = 3, a = 255 },
                { r = 1, g = 2, b = 3, a = 255 }, { r = 1, g = 2, b = 3, a = 255 }, { r = 1, g = 2, b = 3, a = 255 },
            },
            triangles = { { 0, 1, 2 }, { 3, 4, 5 } },
        })
        unitwind:expect(table.size(mesh.vertices)).toBe(4)
        unitwind:expect(table.size(mesh.triangles)).toBe(2)
        unitwind:expect(mesh.triangles[2][1]).toBe(0)
        unitwind:expect(mesh.triangles[2][2]).toBe(2)
    end)

    unitwind:test("BuildPointQuadBatch batches one horizontal quad per point", function()
        local mesh = visualizationMesh.BuildPointQuadBatch({ { x = 10, y = 20, z = 30 } }, { r = 1, g = 2, b = 3, a = 255 }, 8, 4)

        unitwind:expect(table.size(mesh.vertices)).toBe(4)
        unitwind:expect(table.size(mesh.triangles)).toBe(2)
        unitwind:expect(mesh.vertices[1].x).toBe(6)
        unitwind:expect(mesh.vertices[3].y).toBe(24)
        unitwind:expect(mesh.vertices[1].z).toBe(34)
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this