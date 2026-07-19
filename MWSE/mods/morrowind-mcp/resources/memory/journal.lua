local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local journal = require("morrowind-mcp.resources.journal")

--- Memory module for the current player's journal entries.
---@class MCP.Resources.Memory.Journal: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field journalCallback fun(e : journalEventData)?
local this = {}
setmetatable(this, { __index = base })

local relativePath = "memory/player/journal.json"
local descriptor = document.Descriptor(
    relativePath,
    "Player Journal Memory",
    "Memory collection of current player journal entries."
)

this.link = document.Link(document.linkRel.journal, descriptor.uri, descriptor.title, descriptor.description)

--- Create a player-child journal module that becomes visible after a loaded game exists.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Journal
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = "morrowind://memory/player/index.json"
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Journal
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ this.link })
    return instance
end

--- Build a Memory journal document from the current Journal.htm-derived state.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local entries = jsonrpc.array()
    if not tes3.onMainMenu() then
        entries = journal.ReadJournal() or entries
    end
    local subjectType = document.SubjectTypeFromObject(tes3.player)

    return document.Document(
        document.documentType.collection,
        document.dataType.journalEntries,
        descriptor.title,
        jsonrpc.object({
            entries = entries,
        }),
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current Journal.htm parsed on demand."),
        }
    )
end

--- Register journal-specific Memory invalidation events.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.journalCallback then
        return
    end

    self.journalCallback = function(e)
        self:OnJournalUpdated(e)
    end
    event.register(tes3.event.journal, self.journalCallback)
end

--- Unregister journal-specific Memory invalidation events.
function this:UnregisterEvent()
    if self.journalCallback then
        event.unregister(tes3.event.journal, self.journalCallback)
        self.journalCallback = nil
    end
    base.UnregisterEvent(self)
end

--- Hide stale journal memory for a new game; otherwise publish after loading a save.
---@param e loadedEventData
function this:OnLoaded(e)
    if e.newGame then
        self:Unpublish()
        return
    end
    base.OnLoaded(self, e)
end

--- Refresh journal memory after MWSE reports a journal update.
---@param e journalEventData
function this:OnJournalUpdated(e)
    self:Publish()
end

return this