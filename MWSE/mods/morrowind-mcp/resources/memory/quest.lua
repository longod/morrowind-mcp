local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local obj = require("morrowind-mcp.tes3.object")
local document = require("morrowind-mcp.resources.memory.document")

--- Memory module for quest states relevant to the current player.
---@class MCP.Resources.Memory.Quest: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field journalCallback fun(e : journalEventData)?
---@field scriptExecutedCallback fun(e : scriptExecutedEventData)?
local this = {}
setmetatable(this, { __index = base })

local relativePath = "memory/player/quests.json"
local descriptor = document.Descriptor(
    relativePath,
    "Player Quest Memory",
    "Memory collection of current player quest states."
)

this.link = document.Link(document.linkRel.quests, descriptor.uri, descriptor.title, descriptor.description)

--- Create a player-child quest module that becomes visible after a loaded game exists.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Quest
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = "morrowind://memory/player/index.json"
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Quest
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ this.link })
    return instance
end

--- Read all loaded quests once and keep quests that matter to the current player memory.
---@return MCP.AnyMap[]
function this:ReadQuestEntries()
    local entries = jsonrpc.array()
    if tes3.onMainMenu() or not tes3.worldController or not tes3.worldController.quests then
        return entries
    end

    for _, quest in ipairs(tes3.worldController.quests) do
        if quest:isValid() and (quest.isStarted or quest.isActive or quest.isFinished) then
            local entry = obj.tes3quest(quest)
            if entry then
                table.insert(entries, entry)
            end
        end
    end
    return entries
end

--- Build a Memory quest collection from the current world controller quest state.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local subjectType = document.SubjectTypeFromObject(tes3.player)
    return document.Document(
        document.documentType.collection,
        document.dataType.questEntries,
        descriptor.title,
        jsonrpc.object({
            quests = self:ReadQuestEntries(),
        }),
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current quest state read from tes3.worldController.quests."),
        }
    )
end

--- Register quest-specific Memory invalidation events.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if not self.journalCallback then
        self.journalCallback = function(e)
            self:OnJournalUpdated(e)
        end
        event.register(tes3.event.journal, self.journalCallback)
    end
    if not self.scriptExecutedCallback then
        self.scriptExecutedCallback = function(e)
            self:OnScriptExecuted(e)
        end
        event.register(tes3.event.scriptExecuted, self.scriptExecutedCallback)
    end
end

--- Unregister quest-specific Memory invalidation events.
function this:UnregisterEvent()
    if self.journalCallback then
        event.unregister(tes3.event.journal, self.journalCallback)
        self.journalCallback = nil
    end
    if self.scriptExecutedCallback then
        event.unregister(tes3.event.scriptExecuted, self.scriptExecutedCallback)
        self.scriptExecutedCallback = nil
    end
    base.UnregisterEvent(self)
end

--- Hide stale quest memory for a new game; otherwise publish after loading a save.
---@param e loadedEventData
function this:OnLoaded(e)
    if e.newGame then
        self:Unpublish()
        return
    end
    base.OnLoaded(self, e)
end

--- Refresh quest memory when journal state changes.
---@param e journalEventData
function this:OnJournalUpdated(e)
    self:Publish()
end

--- Refresh quest memory when a script event can change quest state.
---@param e scriptExecutedEventData
function this:OnScriptExecuted(e)
    if not e.info then
        return
    end
    if e.info.journalIndex == nil and not e.info.isQuestFinished and not e.info.isQuestRestart then
        return
    end

    self:Publish()
end

return this
