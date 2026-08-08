local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local builderModule = require("morrowind-mcp.navigation.terrain.builder")

    unitwind:start("morrowind-mcp.navigation.terrain.builder")

    local function Cell()
        return { id = "test", isInterior = false, gridX = 0, gridY = 0, waterLevel = -100 }
    end

    local function SamplerFactory()
        return {
            Sample = function(_, x, y) return x + y, 1 end,
            Release = function(self) self.released = true end,
        }
    end

    unitwind:test("Sample budget resumes across steps", function()
        local builder = builderModule.new({ cell = Cell(), interval = 4096, samplerFactory = SamplerFactory })
        unitwind:expect(builder:Step({ mode = "samples", maxSamples = 2 })).toBe("sampling")
        unitwind:expect(builder.processedSamples).toBe(2)
        unitwind:expect(builder:Step({ mode = "samples", maxSamples = 20 })).toBe("ready")
        unitwind:expect(builder.processedSamples).toBe(9)
        unitwind:expect(builder.cell).toBe(nil)
    end)

    unitwind:test("Time budget stops after the configured clock interval", function()
        local clockValue = 0
        local builder = builderModule.new({
            cell = Cell(),
            interval = 2048,
            samplerFactory = SamplerFactory,
            clock = function()
                clockValue = clockValue + 0.001
                return clockValue
            end,
        })
        unitwind:expect(builder:Step({ mode = "time", maxMilliseconds = 1, timeCheckInterval = 1 })).toBe("sampling")
        unitwind:expect(builder.processedSamples).toBe(1)
    end)

    unitwind:test("Elapsed duration excludes time between builder steps", function()
        local clockValue = 0
        local clockCalls = 0
        local builder = builderModule.new({
            cell = Cell(),
            interval = 2048,
            samplerFactory = SamplerFactory,
            clock = function()
                clockCalls = clockCalls + 1
                if clockCalls % 3 == 0 then
                    clockValue = clockValue + 0.001
                end
                return clockValue
            end,
        })
        builder:Step({ mode = "samples", maxSamples = 1 })
        clockValue = clockValue + 10
        builder:Step({ mode = "samples", maxSamples = 1 })
        unitwind:expect(math.floor(builder.elapsedMilliseconds + 0.5)).toBe(2)
    end)

    unitwind:test("Cancel releases incomplete sampler and grid", function()
        local sampler = SamplerFactory()
        local builder = builderModule.new({ cell = Cell(), interval = 2048, samplerFactory = function() return sampler end })
        builder:Step({ mode = "samples", maxSamples = 1 })
        builder:Cancel()
        unitwind:expect(builder.state).toBe("cancelled")
        unitwind:expect(sampler.released).toBe(true)
        unitwind:expect(builder.grid).toBe(nil)
    end)

    unitwind:test("Unavailable sampler produces a terminal state", function()
        local builder = builderModule.new({ cell = Cell(), interval = 128, samplerFactory = function() return nil, "missing" end })
        unitwind:expect(builder:Step()).toBe("failed")
        unitwind:expect(builder.error).toBe("missing")
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
