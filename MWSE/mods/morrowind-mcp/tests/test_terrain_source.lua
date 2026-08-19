local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local source = require("morrowind-mcp.navigation.terrain.source")

    unitwind:start("morrowind-mcp.navigation.terrain.source")

    unitwind:test("Triangle coefficients preserve known heights and mark degeneracy", function()
        local coefficients = source.CreateTriangleCoefficients(0, 0, 0, 10, 0, 10, 0, 10, 20)
        unitwind:expect(coefficients.inverseDenominator).toBe(0.01)
        unitwind:expect(coefficients.heightX * 2 + coefficients.heightY * 3 + coefficients.heightOffset).toBe(8)
        local degenerate = source.CreateTriangleCoefficients(0, 0, 0, 10, 0, 10, 20, 0, 20)
        unitwind:expect(degenerate.inverseDenominator).toBe(0)
    end)

    unitwind:test("Multi-value coefficients match the table form", function()
        local firstWeightX, firstWeightY, firstWeightOffset,
        secondWeightX, secondWeightY, secondWeightOffset,
        heightX, heightY, heightOffset, inverseDenominator =
            source.CalculateTriangleCoefficients(0, 0, 0, 10, 0, 10, 0, 10, 20)
        local expected = source.CreateTriangleCoefficients(0, 0, 0, 10, 0, 10, 0, 10, 20)
        unitwind:expect(firstWeightX).toBe(expected.firstWeightX)
        unitwind:expect(firstWeightY).toBe(expected.firstWeightY)
        unitwind:expect(firstWeightOffset).toBe(expected.firstWeightOffset)
        unitwind:expect(secondWeightX).toBe(expected.secondWeightX)
        unitwind:expect(secondWeightY).toBe(expected.secondWeightY)
        unitwind:expect(secondWeightOffset).toBe(expected.secondWeightOffset)
        unitwind:expect(heightX).toBe(expected.heightX)
        unitwind:expect(heightY).toBe(expected.heightY)
        unitwind:expect(heightOffset).toBe(expected.heightOffset)
        unitwind:expect(inverseDenominator).toBe(expected.inverseDenominator)
        unitwind:expect(expected.normalZSquared).toBe(0)
    end)

    ---@param rows number[][] Rotation matrix rows in row-major order.
    ---@param translation number[]
    ---@param scale number
    local function TransformNode(rows, translation, scale)
        return {
            worldTransform = {
                rotation = {
                    x = { x = rows[1][1], y = rows[1][2], z = rows[1][3] },
                    y = { x = rows[2][1], y = rows[2][2], z = rows[2][3] },
                    z = { x = rows[3][1], y = rows[3][2], z = rows[3][3] },
                },
                translation = { x = translation[1], y = translation[2], z = translation[3] },
                scale = scale,
            },
        }
    end

    local identityRows = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

    unitwind:test("World transform flattening detects the translation-only fast path", function()
        local transform = source.ResolveWorldTransformScalars(TransformNode(identityRows, { 8192, -256, 12 }, 1))
        unitwind:expect(transform.isIdentity).toBe(true)
        unitwind:expect(transform.tx).toBe(8192)
        unitwind:expect(transform.ty).toBe(-256)
        unitwind:expect(transform.tz).toBe(12)
        unitwind:expect(transform.scale).toBe(1)
    end)

    unitwind:test("World transform flattening rejects rotated or scaled nodes", function()
        local scaled = source.ResolveWorldTransformScalars(TransformNode(identityRows, { 0, 0, 0 }, 2))
        unitwind:expect(scaled.isIdentity).toBe(false)
        -- Quarter turn about Z expressed as row-major rows.
        local rotated = source.ResolveWorldTransformScalars(
            TransformNode({ { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 } }, { 0, 0, 0 }, 1))
        unitwind:expect(rotated.isIdentity).toBe(false)
        unitwind:expect(rotated.r01).toBe(-1)
        unitwind:expect(rotated.r10).toBe(1)
    end)

    local function Sampler(layout)
        local sampler = {
            mode = "mesh",
            originX = 0,
            originY = 0,
            bucketSize = 16,
            bucketCount = 1,
            buckets = { { 1 } },
            triangleStorageMode = layout,
        }
        if layout == "soa" then
            sampler.triangleStore = {
                firstWeightX = { 0.1 }, firstWeightY = { 0 }, firstWeightOffset = { 0 },
                secondWeightX = { 0 }, secondWeightY = { 0.1 }, secondWeightOffset = { 0 },
                heightX = { 1 }, heightY = { 2 }, heightOffset = { 0 }, inverseDenominator = { 0.01 },
                normalZSquared = { 1 },
            }
        else
            sampler.triangles = {
                { firstWeightX = 0.1, firstWeightY = 0, firstWeightOffset = 0, secondWeightX = 0, secondWeightY = 0.1, secondWeightOffset = 0, heightX = 1, heightY = 2, heightOffset = 0, inverseDenominator = 0.01, normalZSquared = 1 },
            }
        end
        return setmetatable(sampler, { __index = source })
    end

    unitwind:test("AoS and SoA samplers interpolate the same terrain", function()
        local aos = Sampler("aos")
        local soa = Sampler("soa")
        local aosHeight, aosNormal = aos:Sample(2, 3)
        local soaHeight, soaNormal = soa:Sample(2, 3)
        unitwind:expect(aosHeight).toBe(8)
        unitwind:expect(soaHeight).toBe(aosHeight)
        unitwind:expect(soaNormal).toBe(aosNormal)
        unitwind:expect(aos:Sample(0, 0)).toBe(0)
        unitwind:expect(soa:Sample(0, 0)).toBe(0)
    end)

    unitwind:test("AoS and SoA samplers reject the same outside and degenerate points", function()
        local aos = Sampler("aos")
        local soa = Sampler("soa")
        unitwind:expect(aos:Sample(10, 10)).toBe(nil)
        unitwind:expect(soa:Sample(10, 10)).toBe(nil)
        aos.triangles[1].inverseDenominator = 0
        soa.triangleStore.inverseDenominator[1] = 0
        unitwind:expect(aos:Sample(2, 3)).toBe(nil)
        unitwind:expect(soa:Sample(2, 3)).toBe(nil)
    end)

    unitwind:test("Samplers return nothing for coordinates without a registered bucket", function()
        for _, layout in ipairs({ "aos", "soa" }) do
            local sampler = Sampler(layout)
            sampler.buckets = {}
            local height, normalZSquared = sampler:Sample(2, 3)
            unitwind:expect(height).toBe(nil)
            unitwind:expect(normalZSquared).toBe(nil)
        end
    end)

    unitwind:test("Quad diagonal classification resolves both land triangle splits", function()
        -- Both triangles of the quad at (4, 7) split from its lower-left corner to its upper-right corner.
        local diagonal, quadColumn, quadRow = source.ClassifyQuadDiagonal(4, 7, 5, 7, 5, 8)
        unitwind:expect(diagonal).toBe(source.mainDiagonal)
        unitwind:expect(quadColumn).toBe(4)
        unitwind:expect(quadRow).toBe(7)
        unitwind:expect(source.ClassifyQuadDiagonal(4, 7, 5, 8, 4, 8)).toBe(source.mainDiagonal)
        unitwind:expect(source.ClassifyQuadDiagonal(4, 7, 5, 7, 4, 8)).toBe(source.antiDiagonal)
        unitwind:expect(source.ClassifyQuadDiagonal(5, 7, 5, 8, 4, 8)).toBe(source.antiDiagonal)
    end)

    unitwind:test("Quad diagonal classification rejects triangles outside one grid quad", function()
        -- Spans two quads along one axis.
        unitwind:expect(source.ClassifyQuadDiagonal(0, 0, 2, 0, 2, 1)).toBe(nil)
        -- Degenerate strip with no vertical extent.
        unitwind:expect(source.ClassifyQuadDiagonal(0, 0, 1, 0, 0, 0)).toBe(nil)
    end)

    unitwind:test("Quad diagonals follow a checkerboard rule", function()
        unitwind:expect(source.QuadDiagonalForPosition(0, 0)).toBe(source.mainDiagonal)
        unitwind:expect(source.QuadDiagonalForPosition(1, 1)).toBe(source.mainDiagonal)
        unitwind:expect(source.QuadDiagonalForPosition(1, 0)).toBe(source.antiDiagonal)
        unitwind:expect(source.QuadDiagonalForPosition(0, 1)).toBe(source.antiDiagonal)
    end)

    ---@param heights number[] Row-major elevations for a `width` by `width` grid.
    ---@param width integer
    local function HeightfieldSampler(heights, width)
        return setmetatable({
            mode = "heightfield",
            originX = 0,
            originY = 0,
            heights = heights,
            landInterval = 128,
            landWidth = width,
            quadWidth = width - 1,
        }, { __index = source })
    end

    unitwind:test("Heightfield sampling reproduces a constant slope and its face normal", function()
        -- Every row climbs 128 units per 128-unit step, so the surface is a uniform 45 degree ramp.
        local sampler = HeightfieldSampler({ 0, 128, 256, 0, 128, 256, 0, 128, 256 }, 3)
        local height, normalZSquared = sampler:Sample(64, 64)
        unitwind:expect(height).toBe(64)
        unitwind:expect(normalZSquared).toBe(0.5)
        unitwind:expect(sampler:Sample(0, 0)).toBe(0)
        unitwind:expect(sampler:Sample(192, 64)).toBe(192)
        unitwind:expect(sampler:Sample(224, 96)).toBe(224)
        -- The far cell edge still resolves through the last quad instead of falling outside the grid.
        unitwind:expect(sampler:Sample(256, 0)).toBe(256)
    end)

    unitwind:test("Heightfield sampling selects the triangle named by the quad checkerboard", function()
        -- Only the centre grid point is raised, so the two diagonal choices disagree at the probed offsets.
        local sampler = HeightfieldSampler({ 0, 0, 0, 0, 128, 0, 0, 0, 0 }, 3)
        -- Quad (0,0) is a main diagonal split; the anti split would report 32 here.
        unitwind:expect(sampler:Sample(96, 64)).toBe(64)
        -- Quad (1,0) is an anti diagonal split; the main split would report 0 here.
        unitwind:expect(sampler:Sample(224, 64)).toBe(32)
    end)

    unitwind:test("Heightfield sampling rejects coordinates outside the cell", function()
        local sampler = HeightfieldSampler({ 0, 128, 256, 0, 128, 256, 0, 128, 256 }, 3)
        local height, normalZSquared = sampler:Sample(-1, 0)
        unitwind:expect(height).toBe(nil)
        unitwind:expect(normalZSquared).toBe(nil)
        unitwind:expect(sampler:Sample(0, 257)).toBe(nil)
    end)

    unitwind:test("Heightfield sampling reports nothing for an incomplete quad", function()
        local heights = { 0, 128, 256, 0, 128, 256, 0, 128, 256 }
        heights[5] = nil
        local sampler = HeightfieldSampler(heights, 3)
        unitwind:expect(sampler:Sample(64, 64)).toBe(nil)
    end)

    --- Build a fake exterior cell whose single land patch spans the full land height grid.
    --- Each option breaks one heightfield precondition so the automatic mesh fallback can be observed.
    ---@param options { dropLastVertex: boolean?, breakDiagonal: boolean? }
    local function LandCell(options)
        local width = 65
        local interval = 128
        local vertices = {}
        local vertexCount = 0
        for row = 0, width - 1 do
            for column = 0, width - 1 do
                local index = row * width + column + 1
                -- Dropping the final corner leaves the grid uncovered without disturbing vertex ordering.
                if not (options.dropLastVertex and index == width * width) then
                    vertices[index] = { x = column * interval, y = row * interval, z = 0 }
                    vertexCount = index
                end
            end
        end

        --- Return both land triangles of one quad, using 0-based vertex indices like MWSE does.
        ---@param quadColumn integer
        ---@param quadRow integer
        ---@param isAnti boolean True splits from the lower-right corner to the upper-left corner.
        local function QuadTriangles(quadColumn, quadRow, isAnti)
            local lowerLeft = quadRow * width + quadColumn
            local lowerRight = lowerLeft + 1
            local upperLeft = lowerLeft + width
            local upperRight = upperLeft + 1
            if isAnti then
                return { vertices = { lowerLeft, lowerRight, upperLeft } },
                    { vertices = { lowerRight, upperRight, upperLeft } }
            end
            return { vertices = { lowerLeft, lowerRight, upperRight } },
                { vertices = { lowerLeft, upperRight, upperLeft } }
        end

        -- Construction verifies only the leading triangles of each patch, so two quads are enough to drive it.
        local triangles = {}
        triangles[1], triangles[2] = QuadTriangles(0, 0, options.breakDiagonal == true)
        triangles[3], triangles[4] = QuadTriangles(1, 0, true)

        local node = {
            worldTransform = {
                rotation = {
                    x = { x = 1, y = 0, z = 0 },
                    y = { x = 0, y = 1, z = 0 },
                    z = { x = 0, y = 0, z = 1 },
                },
                translation = { x = 0, y = 0, z = 0 },
                scale = 1,
            },
            data = {
                vertexCount = vertexCount,
                vertices = vertices,
                activeTriangleCount = 4,
                triangles = triangles,
            },
        }
        local cell = {
            isInterior = false,
            gridX = 0,
            gridY = 0,
            landscape = {
                sceneNode = {
                    traverse = function()
                        local visited = false
                        return function()
                            if visited then
                                return nil
                            end
                            visited = true
                            return node
                        end
                    end,
                },
            },
        }
        ---@cast cell tes3cell
        return cell
    end

    unitwind:test("Conforming land data produces a heightfield sampler", function()
        local sampler = source.CreateCellSampler(LandCell({}))
        unitwind:expect(sampler ~= nil).toBe(true)
        ---@cast sampler -nil
        unitwind:expect(sampler.mode).toBe("heightfield")
        unitwind:expect(sampler.metrics.heightfield_fallback_reason).toBe(nil)
        unitwind:expect(sampler.metrics.verified_triangle_count).toBe(2)
    end)

    unitwind:test("An incomplete height grid falls back to mesh sampling with a reason", function()
        local sampler = source.CreateCellSampler(LandCell({ dropLastVertex = true }))
        unitwind:expect(sampler ~= nil).toBe(true)
        ---@cast sampler -nil
        unitwind:expect(sampler.mode).toBe("mesh")
        unitwind:expect(sampler.metrics.heightfield_fallback_reason)
            .toBe("Landscape height grid is incomplete.")
    end)

    unitwind:test("A quad breaking the checkerboard split falls back to mesh sampling with a reason", function()
        local sampler = source.CreateCellSampler(LandCell({ breakDiagonal = true }))
        unitwind:expect(sampler ~= nil).toBe(true)
        ---@cast sampler -nil
        unitwind:expect(sampler.mode).toBe("mesh")
        unitwind:expect(sampler.metrics.heightfield_fallback_reason)
            .toBe("Landscape quads do not follow the checkerboard diagonal split.")
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
