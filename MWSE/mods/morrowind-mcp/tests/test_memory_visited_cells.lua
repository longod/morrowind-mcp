local this = {}
---@diagnostic disable: missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end

    local visitedCells = require("morrowind-mcp.resources.memory.visited_cells")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.visited_cells")

    --- Create a compact test cell that matches the fields used by the Memory serializer.
    ---@param id string
    ---@param interior boolean
    ---@param gridX number?
    ---@param gridY number?
    ---@return tes3cell
    local function Cell(id, interior, gridX, gridY)
        return {
            id = id,
            displayName = id,
            isInterior = interior,
            gridX = gridX,
            gridY = gridY,
            restingIsIllegal = id == "Forbidden Inn",
            region = interior and nil or { id = "west gash", name = "West Gash" },
        }
    end

    --- Create a module with a fixed player and loaded-game scope.
    ---@return MCP.Resources.Memory.VisitedCells
    local function CreateModule()
        local resource = {
            PublishResource = function(self, entry) return entry.descriptor.uri end,
            UnpublishResource = function(self, uri) return true end,
        }
        local manager = {
            GetScope = function(self) return document.Scope(1) end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        return visitedCells.new({ resource = resource, manager = manager })
    end

    --- Read the authoritative cached document from the live resource.
    ---@param module MCP.Resources.Memory.VisitedCells
    ---@return MCP.MemoryDocument
    local function ReadDocument(module)
        module.entry.handler(module.entry.descriptor)
        return module.entry.cache.cached_document
    end

    unitwind:test("Visited Cells records the loaded current cell and resets on the next load", function()
        local balmora = Cell("Balmora", false, -3, -2)
        local seydaNeen = Cell("Seyda Neen", false, -2, -9)
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", { objectType = tes3.objectType.npc })
        unitwind:mock(tes3, "dataHandler", { currentCell = balmora })
        unitwind:mock(datetime, "InGameNow", function() return { year = 427, month = 8, day = 16, hour = 13.5 } end)

        local module = CreateModule()
        module:OnLoaded({ newGame = false })
        local firstDocument = ReadDocument(module)
        local firstCell = firstDocument.data.cells[1]

        unitwind:expect(firstDocument.data_type).toBe("visited_cells")
        unitwind:expect(firstDocument.data.cell_count).toBe(1)
        unitwind:expect(firstCell.id).toBe("Balmora")
        unitwind:expect(firstCell.entry_count).toBe(0)
        unitwind:expect(firstCell.first_observed_at.in_game_time_text).toBe("3E 427-08-16 13:30")

        tes3.dataHandler.currentCell = seydaNeen
        module:OnLoaded({ newGame = false })
        local secondDocument = ReadDocument(module)
        unitwind:expect(secondDocument.data.cell_count).toBe(1)
        unitwind:expect(secondDocument.data.cells[1].id).toBe("Seyda Neen")
    end)

    unitwind:test("Visited Cells updates an id-keyed entry and sorts exterior cells geographically", function()
        local balmora = Cell("Balmora", false, -3, -2)
        local seydaNeen = Cell("Seyda Neen", false, -2, -9)
        local forbiddenInn = Cell("Forbidden Inn", true)
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", { objectType = tes3.objectType.npc })
        unitwind:mock(tes3, "dataHandler", { currentCell = balmora })
        unitwind:mock(datetime, "InGameNow", function() return { year = 427, month = 8, day = 16, hour = 13.5 } end)

        local module = CreateModule()
        module:OnLoaded({})
        module:OnCellChanged({ cell = seydaNeen })
        module:OnCellChanged({ cell = balmora })
        module:OnCellChanged({ cell = forbiddenInn })
        local documentValue = ReadDocument(module)
        local cells = documentValue.data.cells

        unitwind:expect(documentValue.data.cell_count).toBe(3)
        unitwind:expect(module.cellsById["Balmora"].entry_count).toBe(1)
        unitwind:expect(module.cellsById["Balmora"].last_observed_at.in_game_time_text).toBe("3E 427-08-16 13:30")
        unitwind:expect(cells[1].id).toBe("Balmora")
        unitwind:expect(cells[1].grid_x).toBe(-3)
        unitwind:expect(cells[1].grid_y).toBe(-2)
        unitwind:expect(cells[1].region.id).toBe("west gash")
        unitwind:expect(cells[1].region.name).toBe("West Gash")
        unitwind:expect(cells[2].id).toBe("Seyda Neen")
        unitwind:expect(cells[3].id).toBe("Forbidden Inn")
        unitwind:expect(cells[3].resting_is_illegal).toBe(true)
        unitwind:expect(cells[3].grid_x == nil).toBe(true)
        unitwind:expect(cells[3].grid_y == nil).toBe(true)
    end)

    unitwind:test("Visited Cells ignores unavailable cells and registers cell transitions", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback) registered[eventId] = true end)
        unitwind:mock(event, "unregister", function(eventId, callback) unregistered[eventId] = true end)
        local module = CreateModule()
        module:OnCellChanged({})
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(table.size(module.cellsById)).toBe(0)
        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.cellChanged]).toBe(true)
        unitwind:expect(unregistered[tes3.event.loaded]).toBe(true)
        unitwind:expect(unregistered[tes3.event.cellChanged]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
