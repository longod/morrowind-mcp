local cellutil = require("morrowind-mcp.tes3.cell")
local gridModule = require("morrowind-mcp.navigation.terrain.grid")
local sourceModule = require("morrowind-mcp.navigation.terrain.source")

local this = {}
local exteriorCellSize = 8192

---@alias MCP.TerrainGridBuilderState "queued"|"sampling"|"ready"|"cancelled"|"failed"
---@alias MCP.TerrainGridBudgetMode "time"|"samples"|"hybrid"

---@class MCP.TerrainGridBuildOptions
---@field mode MCP.TerrainGridBudgetMode? Per-step stopping policy.
---@field maxSamples integer? Maximum samples processed by samples or hybrid mode.
---@field maxMilliseconds number? Maximum elapsed milliseconds used by time or hybrid mode.
---@field timeCheckInterval integer? Samples processed between elapsed-time checks.

---@class MCP.TerrainGridBuilderParams
---@field cell tes3cell Active exterior cell being sampled.
---@field interval number? Distance in world units between samples.
---@field maxSlopeDegrees number? Steepest accepted walking slope.
---@field maxClimb number? Maximum accepted vertical step.
---@field samplerFactory (fun(cell: tes3cell, bucketSize: number?): MCP.TerrainSampler?, string?)? Injectable terrain source factory.
---@field clock (fun(): number)? Injectable monotonic clock used by tests.

---@class MCP.TerrainGridBuilder
---@field state MCP.TerrainGridBuilderState
---@field cell tes3cell?
---@field interval number
---@field grid MCP.TerrainGrid?
---@field sampler MCP.TerrainSampler?
---@field samplerFactory fun(cell: tes3cell, bucketSize: number?): MCP.TerrainSampler?, string?
---@field clock fun(): number
---@field nextSample integer
---@field processedSamples integer
---@field error string?
---@field memoryBefore number?
---@field elapsedMilliseconds number
---@field maxStepMilliseconds number
---@field memoryDeltaKilobytes number
---@field Step fun(self: MCP.TerrainGridBuilder, options: MCP.TerrainGridBuildOptions?): MCP.TerrainGridBuilderState
---@field Cancel fun(self: MCP.TerrainGridBuilder)

--- Create a resumable builder for one active exterior cell.
--- The grid is allocated immediately, while terrain source acquisition is deferred until the first step.
---@param params MCP.TerrainGridBuilderParams
---@return MCP.TerrainGridBuilder
function this.new(params)
    local cell = params.cell
    local interval = params.interval or 128
    local width = math.floor(exteriorCellSize / interval) + 1
    local instance = {
        state = "queued",
        cell = cell,
        interval = interval,
        samplerFactory = params.samplerFactory or sourceModule.CreateCellSampler,
        clock = params.clock or os.clock,
        nextSample = 1,
        processedSamples = 0,
        error = nil,
        memoryBefore = nil,
        elapsedMilliseconds = 0,
        maxStepMilliseconds = 0,
        memoryDeltaKilobytes = 0,
        grid = gridModule.new({
            cellId = cellutil.GetIdentityKey(cell),
            gridX = cell.gridX,
            gridY = cell.gridY,
            originX = cell.gridX * exteriorCellSize,
            originY = cell.gridY * exteriorCellSize,
            interval = interval,
            width = width,
            height = width,
            maxSlopeDegrees = params.maxSlopeDegrees or 46,
            maxClimb = params.maxClimb or 34,
            waterLevel = cell.waterLevel,
        }),
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Process a bounded batch and retain the next flat sample index for the following frame.
--- The selected mode may stop on sample count, elapsed time, or whichever hybrid limit occurs first.
---@param options MCP.TerrainGridBuildOptions?
---@return MCP.TerrainGridBuilderState state
function this:Step(options)
    options = options or {}
    if self.state ~= "queued" and self.state ~= "sampling" then
        return self.state
    end
    if not self.memoryBefore then
        self.memoryBefore = collectgarbage("count")
    end
    local stepStartedAt = self.clock()
    if self.state == "queued" then
        local sampler, errorMessage = self.samplerFactory(self.cell, math.min(self.interval, 128))
        if not sampler then
            self.state = "failed"
            self.error = errorMessage or "Terrain sampler creation failed."
            return self.state
        end
        self.sampler = sampler
        self.state = "sampling"
    end

    local mode = options.mode or "hybrid"
    local maxSamples = math.max(1, options.maxSamples or 64)
    local maxMilliseconds = math.max(0, options.maxMilliseconds or 2)
    local timeCheckInterval = math.max(1, options.timeCheckInterval or 16)
    local startedAt = self.clock()
    local processedThisStep = 0
    local sampleCount = self.grid.width * self.grid.height
    while self.nextSample <= sampleCount do
        local offset = self.nextSample - 1
        local column = offset % self.grid.width
        local row = math.floor(offset / self.grid.width)
        local x = self.grid.originX + column * self.interval
        local y = self.grid.originY + row * self.interval
        local height, normalZ = self.sampler:Sample(x, y)
        if height and normalZ then
            self.grid:SetSample(column, row, height, normalZ)
        else
            self.grid:SetUnavailable(column, row)
        end
        self.nextSample = self.nextSample + 1
        self.processedSamples = self.processedSamples + 1
        processedThisStep = processedThisStep + 1

        if (mode == "samples" or mode == "hybrid") and processedThisStep >= maxSamples then
            break
        end
        -- Clock checks are intentionally batched because checking every sample can dominate cheap mesh sampling.
        if (mode == "time" or mode == "hybrid") and processedThisStep % timeCheckInterval == 0
            and (self.clock() - startedAt) * 1000 >= maxMilliseconds then
            break
        end
    end
    if self.nextSample > sampleCount then
        self.sampler:Release()
        self.sampler = nil
        self.cell = nil
        self.state = "ready"
    end
    local stepMilliseconds = (self.clock() - stepStartedAt) * 1000
    self.maxStepMilliseconds = math.max(self.maxStepMilliseconds, stepMilliseconds)
    -- Accumulate only measured Step work so inter-frame queue delay cannot inflate build duration.
    self.elapsedMilliseconds = self.elapsedMilliseconds + stepMilliseconds
    self.memoryDeltaKilobytes = collectgarbage("count") - self.memoryBefore
    return self.state
end

--- Abandon an incomplete build and release all cell-owned sampling and grid data.
--- Ready grids are transferred to the manager and therefore are not released by this method.
function this:Cancel()
    if self.state == "ready" or self.state == "cancelled" then
        return
    end
    if self.sampler then
        self.sampler:Release()
        self.sampler = nil
    end
    if self.grid then
        self.grid:Release()
        self.grid = nil
    end
    self.cell = nil
    self.state = "cancelled"
end

return this
