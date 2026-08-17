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

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
