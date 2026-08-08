local cellutil = require("morrowind-mcp.tes3.cell")
local builderModule = require("morrowind-mcp.navigation.terrain.builder")
local raycast = require("morrowind-mcp.navigation.terrain.raycast")
local quality = require("morrowind-mcp.navigation.terrain.quality")
local defaultParameters = require("morrowind-mcp.navigation.terrain.parameters")

local this = {}

---@alias MCP.TerrainGridAvailability "pending"|"ready"|"unavailable"
---@alias MCP.TerrainQualityState "idle"|"building"|"ready"|"failed"

---@class MCP.TerrainGridJob
---@field handle mwseSafeObjectHandle Safe handle for the active exterior cell.
---@field builder MCP.TerrainGridBuilder Resumable builder owned until completion or cancellation.

---@class MCP.TerrainQualityResolutionResult
---@field resolution integer Sampling interval in world units.
---@field samples integer Number of generated grid samples.
---@field elapsed_milliseconds number Builder work duration excluding queue wait.
---@field max_step_milliseconds number Longest measured per-frame builder step.
---@field memory_delta_kilobytes number Lua memory delta observed by the builder.
---@field height MCP.TerrainHeightMetrics? Height metrics populated after all resolutions finish.

---@alias MCP.TerrainQualityResultMap table<string, MCP.TerrainQualityResolutionResult>

---@class MCP.TerrainQualityComparison
---@field state "building"|"ready"|"failed"
---@field cellId MCP.CellIdentityKey?
---@field cellHandle mwseSafeObjectHandle?
---@field resolutions integer[] Ordered sampling intervals, finest first.
---@field resolutionIndex integer Index of the resolution currently being built.
---@field builder MCP.TerrainGridBuilder?
---@field grids table<string, MCP.TerrainGrid> Temporary completed grids keyed by interval text.
---@field results MCP.TerrainQualityResultMap
---@field error string?

---@class MCP.TerrainGridManagerStatus
---@field enabled boolean Whether lifecycle callbacks are registered.
---@field ready_count integer
---@field pending_count integer
---@field queued_count integer
---@field ready_cell_ids MCP.CellIdentityKey[]
---@field pending_cell_ids MCP.CellIdentityKey[]
---@field interval number
---@field budget_mode MCP.TerrainGridBudgetMode

---@class MCP.TerrainQualityStatus
---@field state MCP.TerrainQualityState
---@field cell_id MCP.CellIdentityKey?
---@field resolution_index integer?
---@field resolution_count integer?
---@field results MCP.TerrainQualityResultMap
---@field error string?

---@class MCP.TerrainFindPathOptions
---@field maxReroutes integer? Maximum static-obstacle edges learned before giving up.

---@class MCP.TerrainGridManagerParams
---@field parameters MCP.TerrainParameters? Internal terrain tuning override.
---@field builderFactory (fun(params: MCP.TerrainGridBuilderParams): MCP.TerrainGridBuilder)? Injectable builder constructor.
---@field segmentValidator (fun(start: MCP.PathfindingPosition, destination: MCP.PathfindingPosition, params: MCP.TerrainSegmentValidationParams?): MCP.TerrainSegmentValidationResult)? Injectable obstacle validator.
---@field qualityEvaluator (fun(referenceSampler: MCP.TerrainHeightSampler, grid: MCP.TerrainGrid, validationInterval: number): MCP.TerrainHeightMetrics)? Injectable quality evaluator.

---@class MCP.TerrainGridManager
---@field logger mwseLogger
---@field parameters MCP.TerrainParameters
---@field builderFactory fun(params: MCP.TerrainGridBuilderParams): MCP.TerrainGridBuilder
---@field segmentValidator fun(start: MCP.PathfindingPosition, destination: MCP.PathfindingPosition, params: MCP.TerrainSegmentValidationParams?): MCP.TerrainSegmentValidationResult
---@field qualityEvaluator fun(referenceSampler: MCP.TerrainHeightSampler, grid: MCP.TerrainGrid, validationInterval: number): MCP.TerrainHeightMetrics
---@field jobs table<MCP.CellIdentityKey, MCP.TerrainGridJob>
---@field grids table<MCP.CellIdentityKey, MCP.TerrainGrid>
---@field queue MCP.CellIdentityKey[]
---@field cellActivatedCallback fun(e: cellActivatedEventData)?
---@field cellDeactivatedCallback fun(e: cellDeactivatedEventData)?
---@field loadedCallback fun(e: loadedEventData)?
---@field simulateCallback fun(e: simulateEventData)?
---@field qualityComparison MCP.TerrainQualityComparison?
---@field QueueCell fun(self: MCP.TerrainGridManager, cell: tes3cell): boolean
---@field RemoveCell fun(self: MCP.TerrainGridManager, cellId: MCP.CellIdentityKey)
---@field Clear fun(self: MCP.TerrainGridManager)
---@field QueueActiveCells fun(self: MCP.TerrainGridManager)
---@field Step fun(self: MCP.TerrainGridManager)
---@field GetCellState fun(self: MCP.TerrainGridManager, cell: tes3cell?): string, MCP.TerrainGrid?
---@field FindPath fun(self: MCP.TerrainGridManager, start: MCP.PathfindingLocator, destination: MCP.PathfindingLocator, options: MCP.TerrainFindPathOptions?): MCP.TerrainGridAvailability, MCP.TerrainGridPath?
---@field RegisterEventHandlers fun(self: MCP.TerrainGridManager)
---@field Release fun(self: MCP.TerrainGridManager)
---@field GetStatus fun(self: MCP.TerrainGridManager): MCP.TerrainGridManagerStatus
---@field StartQualityComparison fun(self: MCP.TerrainGridManager, cell: tes3cell, resolutions: integer[]?): boolean, string?
---@field GetQualityStatus fun(self: MCP.TerrainGridManager): MCP.TerrainQualityStatus
---@field StepQualityComparison fun(self: MCP.TerrainGridManager)
---@field CancelQualityComparison fun(self: MCP.TerrainGridManager)

--- Create the owner for terrain jobs, completed active-cell grids, and optional quality measurements.
--- Factories are injectable so lifecycle and scheduling can be tested without retaining MWSE userdata.
---@param params MCP.TerrainGridManagerParams?
---@return MCP.TerrainGridManager
function this.new(params)
    params = params or {}
    local instance = {
        logger = require("morrowind-mcp.logger").Get({ moduleName = "terrain_grid_manager" }),
        parameters = params.parameters or defaultParameters,
        builderFactory = params.builderFactory or builderModule.new,
        segmentValidator = params.segmentValidator or raycast.ValidateSegment,
        qualityEvaluator = params.qualityEvaluator or quality.EvaluateHeight,
        jobs = {},
        grids = {},
        queue = {},
        qualityComparison = nil,
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Queue one active exterior cell exactly once and prioritize the player's current cell.
--- A safe handle guards builder work that resumes after the activation event returns.
---@param cell tes3cell
---@return boolean
function this:QueueCell(cell)
    if not cell or cell.isInterior then
        return false
    end
    local cellId = cellutil.GetIdentityKey(cell)
    if not cellId or self.jobs[cellId] or self.grids[cellId] then
        return false
    end
    local handle = tes3.makeSafeObjectHandle(cell)
    local builder = self.builderFactory({
        cell = cell,
        interval = self.parameters.interval,
        maxSlopeDegrees = self.parameters.maxSlopeDegrees,
        maxClimb = self.parameters.maxClimb,
    })
    self.jobs[cellId] = { handle = handle, builder = builder }
    if tes3.player and tes3.player.cell == cell then
        table.insert(self.queue, 1, cellId)
    else
        table.insert(self.queue, cellId)
    end
    return true
end

--- Cancel and release every terrain object owned for one cell identity.
--- Queue entries are removed as well so a deactivated cell cannot resume on a later frame.
---@param cellId MCP.CellIdentityKey
function this:RemoveCell(cellId)
    local job = self.jobs[cellId]
    if job then
        job.builder:Cancel()
        self.jobs[cellId] = nil
    end
    local grid = self.grids[cellId]
    if grid then
        grid:Release()
        self.grids[cellId] = nil
    end
    for index = table.size(self.queue), 1, -1 do
        if self.queue[index] == cellId then
            table.remove(self.queue, index)
        end
    end
end

--- Release all active jobs and completed grids while preserving registered event callbacks.
function this:Clear()
    local cellIds = {}
    for cellId in pairs(self.jobs) do
        table.insert(cellIds, cellId)
    end
    for cellId in pairs(self.grids) do
        if not table.find(cellIds, cellId) then
            table.insert(cellIds, cellId)
        end
    end
    for _, cellId in ipairs(cellIds) do
        self:RemoveCell(cellId)
    end
    self.queue = {}
end

--- Discover the engine's current exterior active set and queue any missing grids.
function this:QueueActiveCells()
    for _, cell in ipairs(tes3.getActiveCells()) do
        self:QueueCell(cell)
    end
end

--- Spend one frame budget on the highest-priority cell build.
--- Quality comparison receives otherwise idle generation frames so gameplay grids always finish first.
function this:Step()
    local cellId = self.queue[1]
    local job = cellId and self.jobs[cellId] or nil
    if not job then
        if cellId then
            table.remove(self.queue, 1)
        end
        self:StepQualityComparison()
        return
    end
    if not job.handle:valid() then
        self:RemoveCell(cellId)
        return
    end
    local state = job.builder:Step({
        mode = self.parameters.budgetMode,
        maxSamples = self.parameters.maxSamplesPerFrame,
        maxMilliseconds = self.parameters.maxMillisecondsPerFrame,
        timeCheckInterval = self.parameters.timeCheckInterval,
    })
    if state == "ready" then
        self.grids[cellId] = job.builder.grid
        self.jobs[cellId] = nil
        table.remove(self.queue, 1)
        self.logger:debug(
            "Terrain grid ready: cell=%s samples=%d elapsedMilliseconds=%.3f maxStepMilliseconds=%.3f memoryDeltaKilobytes=%.3f",
            cellId, job.builder.processedSamples, job.builder.elapsedMilliseconds or 0,
            job.builder.maxStepMilliseconds or 0, job.builder.memoryDeltaKilobytes or 0)
    elseif state == "failed" or state == "cancelled" then
        self.logger:warn("Terrain grid build stopped: cell=%s state=%s error=%s", cellId, state,
            tostring(job.builder.error))
        self:RemoveCell(cellId)
    end
end

--- Start a sequential resolution comparison for one active exterior cell.
---@param cell tes3cell
---@param resolutions integer[]?
---@return boolean started
---@return string? errorMessage
function this:StartQualityComparison(cell, resolutions)
    if not cell or cell.isInterior then
        return false, "An active exterior cell is required."
    end
    self:CancelQualityComparison()
    self.qualityComparison = {
        state = "building",
        cellId = cellutil.GetIdentityKey(cell),
        cellHandle = tes3.makeSafeObjectHandle(cell),
        resolutions = resolutions or { 64, 128, 256 },
        resolutionIndex = 1,
        builder = nil,
        grids = {},
        results = {},
        error = nil,
    }
    return true, nil
end

--- Advance one benchmark builder step after normal active-cell generation work.
function this:StepQualityComparison()
    local comparison = self.qualityComparison
    if not comparison or comparison.state ~= "building" then
        return
    end
    if not comparison.cellHandle:valid() then
        comparison.state = "failed"
        comparison.error = "Benchmark cell became invalid."
        return
    end
    local resolution = comparison.resolutions[comparison.resolutionIndex]
    if not resolution then
        -- The finest completed grid acts as a stable temporary reference while coarser interpolation is measured.
        local referenceGrid = comparison.grids[tostring(comparison.resolutions[1])]
        local reference = {
            Sample = function(_, x, y)
                local height = referenceGrid:InterpolateHeight(x, y)
                return height, height and 1 or nil
            end,
        }
        for _, measuredResolution in ipairs(comparison.resolutions) do
            local key = tostring(measuredResolution)
            comparison.results[key].height = self.qualityEvaluator(reference, comparison.grids[key],
                comparison.resolutions[1])
        end
        -- The reference closure reads the finest grid while every coarser grid is evaluated.
        for _, measuredResolution in ipairs(comparison.resolutions) do
            comparison.grids[tostring(measuredResolution)]:Release()
        end
        comparison.grids = {}
        comparison.builder = nil
        comparison.cellHandle = nil
        comparison.state = "ready"
        return
    end
    if not comparison.builder then
        -- Only one comparison grid exists in a builder at a time to bound temporary memory usage.
        local cell = comparison.cellHandle:getObject()
        comparison.builder = self.builderFactory({
            cell = cell,
            interval = resolution,
            maxSlopeDegrees = self.parameters.maxSlopeDegrees,
            maxClimb = self.parameters.maxClimb,
        })
    end
    local builder = comparison.builder ---@type MCP.TerrainGridBuilder
    local state = builder:Step({
        mode = self.parameters.budgetMode,
        maxSamples = self.parameters.maxSamplesPerFrame,
        maxMilliseconds = self.parameters.maxMillisecondsPerFrame,
        timeCheckInterval = self.parameters.timeCheckInterval,
    })
    if state == "ready" then
        local key = tostring(resolution)
        comparison.grids[key] = builder.grid
        comparison.results[key] = {
            resolution = resolution,
            samples = builder.processedSamples,
            elapsed_milliseconds = builder.elapsedMilliseconds or 0,
            max_step_milliseconds = builder.maxStepMilliseconds or 0,
            memory_delta_kilobytes = builder.memoryDeltaKilobytes or 0,
        }
        comparison.builder = nil
        comparison.resolutionIndex = comparison.resolutionIndex + 1
    elseif state == "failed" or state == "cancelled" then
        comparison.state = "failed"
        comparison.error = builder.error or "Benchmark terrain build stopped."
    end
end

--- Release any in-progress or completed temporary benchmark grids.
function this:CancelQualityComparison()
    local comparison = self.qualityComparison
    if not comparison then
        return
    end
    if comparison.builder then
        local builder = comparison.builder ---@type MCP.TerrainGridBuilder
        builder:Cancel()
    end
    for _, grid in pairs(comparison.grids or {}) do
        grid:Release()
    end
    self.qualityComparison = nil
end

--- Return primitive comparison progress and completed metrics for debug-tool polling.
---@return MCP.TerrainQualityStatus
function this:GetQualityStatus()
    local comparison = self.qualityComparison
    if not comparison then
        return { state = "idle", results = {} }
    end
    return {
        state = comparison.state,
        cell_id = comparison.cellId,
        resolution_index = comparison.resolutionIndex,
        resolution_count = table.size(comparison.resolutions),
        results = comparison.results,
        error = comparison.error,
    }
end

--- Return whether a cell grid is still building, ready for queries, or not owned by this manager.
---@param cell tes3cell?
---@return MCP.TerrainGridAvailability
---@return MCP.TerrainGrid?
function this:GetCellState(cell)
    local cellId = cellutil.GetIdentityKey(cell)
    if not cellId then
        return "unavailable", nil
    end
    if self.grids[cellId] then
        return "ready", self.grids[cellId]
    end
    if self.jobs[cellId] then
        return "pending", nil
    end
    return "unavailable", nil
end

--- Return primitive lifecycle data suitable for diagnostics and integration tests.
---@return MCP.TerrainGridManagerStatus
function this:GetStatus()
    local readyCellIds = table.keys(self.grids, true)
    local pendingCellIds = table.keys(self.jobs, true)
    return {
        enabled = self.simulateCallback ~= nil,
        ready_count = table.size(readyCellIds),
        pending_count = table.size(pendingCellIds),
        queued_count = table.size(self.queue),
        ready_cell_ids = readyCellIds,
        pending_cell_ids = pendingCellIds,
        interval = self.parameters.interval,
        budget_mode = self.parameters.budgetMode,
    }
end

--- Find and validate a route within one completed terrain grid.
--- Static hits block the discovered edge and restart A*; actors and moving objects remain transient.
---@param start MCP.PathfindingLocator
---@param destination MCP.PathfindingLocator
---@param options MCP.TerrainFindPathOptions?
---@return MCP.TerrainGridAvailability state
---@return MCP.TerrainGridPath? path
function this:FindPath(start, destination, options)
    local startCellId = cellutil.GetIdentityKey(start.cell)
    local destinationCellId = cellutil.GetIdentityKey(destination.cell)
    if not startCellId or startCellId ~= destinationCellId or not start.position or not destination.position then
        return "unavailable", nil
    end
    local state, grid = self:GetCellState(start.cell)
    if state ~= "ready" or not grid then
        return state, nil
    end
    options = options or {}
    local maxReroutes = options.maxReroutes or 8
    for _ = 1, maxReroutes do
        local path = grid:FindPath(start.position, destination.position)
        if not path then
            return "unavailable", nil
        end
        local blocked = false
        for index = 1, table.size(path.indices) - 1 do
            local validation = self.segmentValidator(path.positions[index], path.positions[index + 1], {
                ignore = tes3.player and { tes3.player } or nil,
            })
            if not validation.clear then
                -- Only the first obstruction is learned per attempt; rerunning A* may avoid all later segments.
                grid:SetEdgeBlocked(path.indices[index], path.indices[index + 1], true)
                blocked = true
                break
            end
        end
        if not blocked then
            return "ready", path
        end
    end
    return "unavailable", nil
end

--- Register active-cell and simulation callbacks, then bootstrap cells already active at server start.
function this:RegisterEventHandlers()
    self.cellActivatedCallback = function(e) self:QueueCell(e.cell) end
    self.cellDeactivatedCallback = function(e)
        local cellId = cellutil.GetIdentityKey(e.cell)
        if cellId then
            self:RemoveCell(cellId)
        end
    end
    self.loadedCallback = function()
        self:Clear()
        self:QueueActiveCells()
    end
    self.simulateCallback = function() self:Step() end
    event.register(tes3.event.cellActivated, self.cellActivatedCallback)
    event.register(tes3.event.cellDeactivated, self.cellDeactivatedCallback)
    event.register(tes3.event.loaded, self.loadedCallback)
    event.register(tes3.event.simulate, self.simulateCallback)
    self:QueueActiveCells()
end

--- Unregister callbacks and release quality, job, and grid state owned by the server instance.
function this:Release()
    if self.cellActivatedCallback then
        event.unregister(tes3.event.cellActivated, self.cellActivatedCallback)
    end
    if self.cellDeactivatedCallback then
        event.unregister(tes3.event.cellDeactivated, self.cellDeactivatedCallback)
    end
    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
    end
    if self.simulateCallback then
        event.unregister(tes3.event.simulate, self.simulateCallback)
    end
    self.cellActivatedCallback = nil
    self.cellDeactivatedCallback = nil
    self.loadedCallback = nil
    self.simulateCallback = nil
    self:CancelQualityComparison()
    self:Clear()
end

return this
