local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local datetime = require("morrowind-mcp.util.datetime")
local player = require("morrowind-mcp.resources.memory.player")
local cellmemory = require("morrowind-mcp.resources.memory.cell")

--- Memory module for places the current player has entered during this loaded game.
---@class MCP.Resources.Memory.VisitedCells: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field cellsById table<string, MCP.AnyMap>
---@field cellChangedCallback fun(e: cellChangedEventData)?
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/player/visited-cells.json",
    "Player Visited Places Memory",
    "Places the player has entered, represented by TES3 cells."
)

local visitedCellsLink = document.Link(
    document.linkRel.visitedCells,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

--- Return a compact Tamriel timestamp suitable for repeated collection entries.
---@return string?
local function ObservedAt()
    return datetime.ToInGameShortText(datetime.InGameNow())
end

--- Sort exterior cells geographically and interior cells by stable display identity.
---@param left MCP.AnyMap
---@param right MCP.AnyMap
---@return boolean
local function IsBefore(left, right)
    if left.is_interior ~= right.is_interior then
        return left.is_interior ~= true
    end
    if left.is_interior then
        local leftName = left.display_name or left.id
        local rightName = right.display_name or right.id
        if leftName ~= rightName then
            return leftName < rightName
        end
        return left.id < right.id
    end
    if left.grid_y ~= right.grid_y then
        return left.grid_y > right.grid_y
    end
    if left.grid_x ~= right.grid_x then
        return left.grid_x < right.grid_x
    end
    return left.id < right.id
end

--- Create the player-child visited-place collection and its live resource entry.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.VisitedCells
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = player.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_visited_cells" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.VisitedCells
    instance.cellsById = {}
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ visitedCellsLink })
    return instance
end

--- Record a cell entry or update its last observation without retaining the MWSE cell object.
---@param cell tes3cell?
---@param countEntry boolean
---@return boolean changed
function this:ObserveCell(cell, countEntry)
    local serialized = cellmemory.Serialize(cell)
    if not serialized then
        return false
    end

    local observedAt = ObservedAt()
    local observed = self.cellsById[serialized.id]
    if not observed then
        serialized.first_observed_at = observedAt
        serialized.last_observed_at = observedAt
        serialized.entry_count = countEntry and 1 or 0
        self.cellsById[serialized.id] = serialized
        document.MarkDirty(self.entry)
        return true
    end

    observed.display_name = serialized.display_name
    observed.is_interior = serialized.is_interior
    observed.grid_x = serialized.grid_x
    observed.grid_y = serialized.grid_y
    observed.region = serialized.region
    observed.resting_is_illegal = serialized.resting_is_illegal
    observed.last_observed_at = observedAt
    if countEntry then
        observed.entry_count = (observed.entry_count or 0) + 1
    end
    document.MarkDirty(self.entry)
    return true
end

--- Build a sorted JSON array only when the live resource is read after an observation.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local cells = jsonrpc.array()
    for _, cell in pairs(self.cellsById) do
        table.insert(cells, cell)
    end
    table.sort(cells, IsBefore)
    local subjectType = document.SubjectTypeFromObject(tes3.player)
    return document.Document(
        document.documentType.collection,
        document.dataType.visitedCells,
        descriptor.title,
        jsonrpc.object({
            available = tes3.onMainMenu() ~= true and tes3.player ~= nil,
            cell_count = table.size(cells),
            cells = cells,
        }),
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.event, nil, "cellChanged", "Cells entered by the player during this loaded game."),
        }
    )
end

--- Reset this non-persistent collection and observe the cell occupied after loading.
---@param e loadedEventData?
function this:OnLoaded(e)
    self.cellsById = {}
    self:ObserveCell(tes3.dataHandler and tes3.dataHandler.currentCell or nil, false)
    base.OnLoaded(self, e)
end

--- Record a completed player cell transition.
---@param e cellChangedEventData?
function this:OnCellChanged(e)
    self:ObserveCell(e and e.cell or nil, true)
end

--- Register the player cell-transition event in addition to base loaded handling.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.cellChangedCallback then
        return
    end
    self.cellChangedCallback = function(e) self:OnCellChanged(e) end
    event.register(tes3.event.cellChanged, self.cellChangedCallback)
end

--- Unregister the player cell-transition callback before releasing the module.
function this:UnregisterEvent()
    if self.cellChangedCallback then
        event.unregister(tes3.event.cellChanged, self.cellChangedCallback)
        self.cellChangedCallback = nil
    end
    base.UnregisterEvent(self)
end

return this
