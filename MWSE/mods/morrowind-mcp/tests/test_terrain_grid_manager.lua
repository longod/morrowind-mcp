local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local managerModule = require("morrowind-mcp.navigation.terrain.manager")

    unitwind:start("morrowind-mcp.navigation.terrain.manager")
    local releasedGridCount = 0
    local releasedIntervals = {}
    local builderParams = {}

    local function Cell(id, x, y)
        return { id = id, isInterior = false, gridX = x, gridY = y, valid = true }
    end

    local function Handle(object)
        return {
            valid = function() return object.valid end,
            getObject = function() return object end,
        }
    end

    local function Builder(params)
        table.insert(builderParams, params)
        return {
            state = "sampling",
            processedSamples = 0,
            samplerMetrics = {
                mode = "mesh",
                bucket_size = params.bucketSize,
                triangle_storage_mode = params.triangleStorageMode,
                triangle_count = params.interval,
            },
            grid = {
                interval = params.interval,
                Release = function()
                    releasedGridCount = releasedGridCount + 1
                    table.insert(releasedIntervals, params.interval)
                end,
                InterpolateHeight = function() return 0 end,
            },
            Step = function(self)
                self.processedSamples = self.processedSamples + 1
                self.state = "ready"
                return self.state
            end,
            Cancel = function(self)
                self.state = "cancelled"
                self.grid:Release()
            end,
        }
    end

    unitwind:test("Player cell is prioritized and completed grid becomes ready", function()
        local playerCell = Cell("player", 0, 0)
        local neighbor = Cell("neighbor", 1, 0)
        unitwind:mock(tes3, "player", { cell = playerCell })
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({
            builderFactory = Builder,
            qualityEvaluator = function() return { mae = 0 } end,
        })
        manager:QueueCell(neighbor)
        manager:QueueCell(playerCell)
        manager:Step()
        local state, grid = manager:GetCellState(playerCell)
        unitwind:expect(state).toBe("ready")
        unitwind:expect(grid ~= nil).toBe(true)
        unitwind:expect(builderParams[table.size(builderParams)].triangleStorageMode).toBe("soa")
        unitwind:expect(manager:GetCellState(neighbor)).toBe("pending")
    end)

    unitwind:test("Ready and removed grids notify observers", function()
        local cell = Cell("changes", 0, 0)
        local changes = 0
        unitwind:mock(tes3, "player", { cell = cell })
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({ builderFactory = Builder, onChanged = function() changes = changes + 1 end })
        manager:QueueCell(cell)
        manager:Step()
        manager:RemoveCell("exterior:changes:0,0")
        unitwind:expect(changes).toBe(2)
    end)

    unitwind:test("Removing a cell cancels its job and releases completed data", function()
        local releasesBefore = releasedGridCount
        local cell = Cell("remove", 0, 0)
        unitwind:mock(tes3, "player", { cell = cell })
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({ builderFactory = Builder })
        manager:QueueCell(cell)
        local builder = manager.jobs["exterior:remove:0,0"].builder
        manager:RemoveCell("exterior:remove:0,0")
        unitwind:expect(builder.state).toBe("cancelled")
        unitwind:expect(table.size(manager.queue)).toBe(0)

        manager:QueueCell(cell)
        manager:Step()
        manager:RemoveCell("exterior:remove:0,0")
        unitwind:expect(releasedGridCount - releasesBefore).toBe(2)
    end)

    unitwind:test("Event lifecycle queues, removes, rebuilds, and releases callbacks", function()
        local callbacks = {}
        local cell = Cell("events", 0, 0)
        unitwind:mock(tes3, "player", { cell = cell })
        unitwind:mock(tes3, "getActiveCells", function() return { cell } end)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        unitwind:mock(event, "register", function(eventId, callback) callbacks[eventId] = callback end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            if callbacks[eventId] == callback then callbacks[eventId] = nil end
        end)
        local manager = managerModule.new({ builderFactory = Builder })
        manager:RegisterEventHandlers()
        unitwind:expect(manager:GetCellState(cell)).toBe("pending")
        callbacks[tes3.event.cellDeactivated]({ cell = cell })
        unitwind:expect(manager:GetCellState(cell)).toBe("unavailable")
        callbacks[tes3.event.loaded]({})
        unitwind:expect(manager:GetCellState(cell)).toBe("pending")
        manager:Release()
        unitwind:expect(callbacks[tes3.event.simulate] == nil).toBe(true)
        unitwind:expect(table.size(manager.jobs)).toBe(0)
    end)

    unitwind:test("FindPath blocks a static edge and returns the replanned route", function()
        local cell = Cell("route", 0, 0)
        local calls = 0
        local blockedEdges = 0
        local grid = {
            FindPath = function()
                calls = calls + 1
                if calls == 1 then
                    return {
                        indices = { 1, 2 },
                        positions = { { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 } },
                    }
                end
                return {
                    indices = { 1, 3, 2 },
                    positions = {
                        { x = 0, y = 0, z = 0 },
                        { x = 5, y = 5, z = 0 },
                        { x = 10, y = 0, z = 0 },
                    },
                }
            end,
            SetEdgeBlocked = function()
                blockedEdges = blockedEdges + 1
            end,
        }
        local validationCalls = 0
        local manager = managerModule.new({
            segmentValidator = function()
                validationCalls = validationCalls + 1
                return { clear = validationCalls > 1 }
            end,
        })
        manager.grids["exterior:route:0,0"] = grid
        local state, path = manager:FindPath(
            { cell = cell, position = { x = 0, y = 0, z = 0 } },
            { cell = cell, position = { x = 10, y = 0, z = 0 } }
        )
        unitwind:expect(state).toBe("ready")
        ---@cast path MCP.TerrainGridPath
        unitwind:expect(blockedEdges).toBe(1)
        unitwind:expect(table.size(path.positions)).toBe(3)
    end)

    unitwind:test("FindPath distinguishes pending and unavailable cells and honors reroute limit", function()
        local cell = Cell("route-state", 0, 0)
        local manager = managerModule.new({ segmentValidator = function() return { clear = false } end })
        unitwind:expect(manager:FindPath(
            { cell = cell, position = { x = 0, y = 0, z = 0 } },
            { cell = cell, position = { x = 1, y = 0, z = 0 } }
        )).toBe("unavailable")
        local pendingJob = {}
        ---@cast pendingJob MCP.TerrainGridJob
        manager.jobs["exterior:route-state:0,0"] = pendingJob
        unitwind:expect(manager:FindPath(
            { cell = cell, position = { x = 0, y = 0, z = 0 } },
            { cell = cell, position = { x = 1, y = 0, z = 0 } }
        )).toBe("pending")

        local attempts = 0
        manager.jobs["exterior:route-state:0,0"] = nil
        local grid = {
            FindPath = function()
                attempts = attempts + 1
                return { indices = { 1, 2 }, positions = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 } } }
            end,
            SetEdgeBlocked = function() return true end,
        }
        ---@cast grid MCP.TerrainGrid
        manager.grids["exterior:route-state:0,0"] = grid
        unitwind:expect(manager:FindPath(
            { cell = cell, position = { x = 0, y = 0, z = 0 } },
            { cell = cell, position = { x = 1, y = 0, z = 0 } }, { maxReroutes = 2 }
        )).toBe("unavailable")
        unitwind:expect(attempts).toBe(2)
    end)

    ---@param warnings string[] Receives every formatted warning raised while a test runs.
    local function CapturingLogger(warnings)
        return {
            debug = function() end,
            warn = function(_, format, ...) table.insert(warnings, string.format(format, ...)) end,
        }
    end

    unitwind:test("Heightfield rejection is reported for the affected cell", function()
        local cell = Cell("fallback", 2, -3)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({
            builderFactory = function(params)
                local builder = Builder(params)
                builder.samplerMetrics.heightfield_fallback_reason = "Landscape height grid is incomplete."
                return builder
            end,
            qualityEvaluator = function() return { mae = 0 } end,
        })
        local warnings = {}
        manager.logger = CapturingLogger(warnings) ---@diagnostic disable-line: assign-type-mismatch, missing-fields
        manager:QueueCell(cell)
        manager:Step()
        unitwind:expect(table.size(warnings)).toBe(1)
        unitwind:expect(warnings[1]).toBe(
            "Terrain heightfield sampling rejected: cell=exterior:fallback:2,-3 reason=Landscape height grid is incomplete.")
    end)

    unitwind:test("Ready grids without a rejection reason stay silent", function()
        local cell = Cell("accepted", 0, 0)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({
            builderFactory = Builder,
            qualityEvaluator = function() return { mae = 0 } end,
        })
        local warnings = {}
        manager.logger = CapturingLogger(warnings) ---@diagnostic disable-line: assign-type-mismatch, missing-fields
        manager:QueueCell(cell)
        manager:Step()
        unitwind:expect(table.size(warnings)).toBe(0)
    end)

    unitwind:test("Quality comparison builds resolutions sequentially and releases temporary grids", function()        local cell = Cell("quality", 0, 0)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local evaluated = 0
        local manager = managerModule.new({
            builderFactory = Builder,
            qualityEvaluator = function(reference, grid, interval)
                evaluated = evaluated + 1
                return { mae = grid.interval - interval }
            end,
        })
        local started = manager:StartQualityComparison(cell, { 64, 128, 256 })
        unitwind:expect(started).toBe(true)
        manager:Step()
        manager:Step()
        manager:Step()
        local releaseCountBeforeEvaluation = releasedGridCount
        manager:Step()
        local status = manager:GetQualityStatus()
        unitwind:expect(status.state).toBe("ready")
        unitwind:expect(evaluated).toBe(3)
        unitwind:expect(status.results["128"].height.mae).toBe(64)
        unitwind:expect(status.results["128"].sampler.triangle_count).toBe(128)
        unitwind:expect(status.results["128"].sampler.triangle_storage_mode).toBe("soa")
        unitwind:expect(releasedGridCount - releaseCountBeforeEvaluation).toBe(3)
        unitwind:expect(releasedIntervals[releaseCountBeforeEvaluation + 1]).toBe(64)
        unitwind:expect(releasedIntervals[releaseCountBeforeEvaluation + 2]).toBe(128)
        unitwind:expect(releasedIntervals[releaseCountBeforeEvaluation + 3]).toBe(256)
    end)

    unitwind:test("Quality comparison retains distinct bucket-size cases at one resolution", function()
        local cell = Cell("quality-buckets", 0, 0)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({
            builderFactory = Builder,
            qualityEvaluator = function() return { mae = 0 } end,
        })
        local started = manager:StartQualityComparison(cell, {
            { key = "128-64", resolution = 128, bucketSize = 64, triangleStorageMode = "aos" },
            { key = "128-256", resolution = 128, bucketSize = 256, triangleStorageMode = "aos" },
        })
        unitwind:expect(started).toBe(true)
        manager:Step()
        manager:Step()
        manager:Step()
        local status = manager:GetQualityStatus()
        unitwind:expect(status.state).toBe("ready")
        unitwind:expect(status.results["128-64"].sampler.bucket_size).toBe(64)
        unitwind:expect(status.results["128-256"].sampler.bucket_size).toBe(256)
        unitwind:expect(table.size(status.case_keys)).toBe(2)
    end)

    unitwind:test("Quality comparison forwards its triangle storage mode", function()
        local cell = Cell("quality-soa", 0, 0)
        unitwind:mock(tes3, "makeSafeObjectHandle", Handle)
        local manager = managerModule.new({
            builderFactory = Builder,
            qualityEvaluator = function() return { mae = 0 } end,
        })
        manager:StartQualityComparison(cell, {
            { key = "128-soa", resolution = 128, bucketSize = 128, triangleStorageMode = "soa" },
        })
        manager:Step()
        manager:Step()
        local status = manager:GetQualityStatus()
        unitwind:expect(status.results["128-soa"].sampler.triangle_storage_mode).toBe("soa")
    end)

    local testsPassed, testsFailed = unitwind.testsPassed, unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
