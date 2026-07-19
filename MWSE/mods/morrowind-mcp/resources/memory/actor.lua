local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

--- Memory module that owns one actor collection and many observed actor entries internally.
---@class MCP.Resources.Memory.Actor: MCP.Resources.MemoryModule
---@field indexEntry MCP.MemoryResourceEntry
---@field observedActors table<string, MCP.MemoryObservedActor>
---@field actorLinks MCP.MemoryLink[]
---@field activationTargetChangedCallback fun(e: activationTargetChangedEventData)?
local this = {}
setmetatable(this, { __index = base })

local collectionDescriptor = document.Descriptor(
    "memory/actors/index.json",
    "Observed Actor Memory",
    "Memory collection of observed actors in active cells."
)

local collectionLink = document.Link(
    document.linkRel.actors,
    collectionDescriptor.uri,
    collectionDescriptor.title,
    collectionDescriptor.description
)

--- Coarse identity classification for observed actors.
--- Unknown is intentional: creature records often lack enough in-game evidence to prove unique identity.
---@enum MCP.MemoryActorIdentityKind
local identityKind = {
    unique = "unique",
    generic = "generic",
    unknown = "unknown",
}

--- Convert an in-game identifier to a conservative URI path segment.
--- The raw TES3 id is kept in data; only the URI segment is normalized.
---@param value any
---@return string
local function SafeSegment(value)
    local text = string.lower(tostring(value or "unknown"))
    text = string.gsub(text, "[^%w%._%-~]+", "-")
    text = string.gsub(text, "%-+", "-")
    text = string.gsub(text, "^%-", "")
    text = string.gsub(text, "%-$", "")
    if text == "" then
        return "unknown"
    end
    return text
end

--- Check whether a reference should be represented by Actor Memory.
---@param ref tes3reference
---@return boolean
local function IsActorReference(ref)
    if not ref or not ref:isValid() or not ref.object then
        return false
    end
    return ref.object.objectType == tes3.objectType.npc or ref.object.objectType == tes3.objectType.creature
end

--- Return the base actor id used by this prototype as the primary observed actor identity.
---@param ref tes3reference
---@return string
local function ActorBaseId(ref)
    local baseObject = ref.baseObject or (ref.object and ref.object.baseObject) or ref.object
    return tostring((baseObject and baseObject.id) or "unknown")
end

--- Return the observed reference/object id that identifies the concrete runtime actor.
---@param ref tes3reference
---@return string
local function ActorReferenceId(ref)
    return tostring(ref.id or (ref.object and ref.object.id) or "unknown")
end

--- Return true when this actor respawns through its record or placed reference flags.
--- Both levels matter because MWSE exposes respawn data on references, actor instances, and base objects.
---@param ref tes3reference
---@return boolean
local function ActorRespawns(ref)
    local baseObject = ref.baseObject or (ref.object and ref.object.baseObject) or ref.object
    return ref.isRespawn == true or (ref.object and ref.object.isRespawn == true) or (baseObject and baseObject.isRespawn == true)
end

--- Return true when a creature reference was produced by a leveled creature list.
--- Leveled spawns are treated as generic even when the selected creature record itself does not respawn.
---@param ref tes3reference
---@return boolean
local function IsLeveledCreatureSpawn(ref)
    local baseObject = ref.baseObject or (ref.object and ref.object.baseObject)
    return ref.isLeveledSpawn == true
        or ref.leveledBaseReference ~= nil
        or (baseObject and baseObject.objectType == tes3.objectType.leveledCreature)
end

--- Return a human-readable actor title for resource labels.
---@param ref tes3reference
---@return string
local function ActorTitle(ref)
    return tostring((ref.object and ref.object.name) or (ref.object and ref.object.id) or "Actor")
end

--- Return how confidently the observed actor can be classified as unique, generic, or unknown.
--- NPC identity is mostly record-driven; creature identity stays unknown unless generic signals are strong.
---@param ref tes3reference
---@param baseId string
---@return MCP.MemoryActorIdentityKind
local function ActorIdentityKind(ref, baseId)
    if ref.object.objectType == tes3.objectType.npc then
        -- Din is the one vanilla named NPC that intentionally respawns.
        if not ActorRespawns(ref) or string.lower(baseId) == "din" then
            return identityKind.unique
        end
        return identityKind.generic
    end
    if ref.object.objectType == tes3.objectType.creature then
        if ActorRespawns(ref) or IsLeveledCreatureSpawn(ref) then
            return identityKind.generic
        end
        return identityKind.unknown
    end
    return identityKind.unknown
end

--- Return the Memory data type for the observed actor.
---@param ref tes3reference
---@return MCP.MemoryDataType?
local function ActorDataType(ref)
    if ref.object.objectType == tes3.objectType.npc then
        return document.dataType.npcSummary
    end
    if ref.object.objectType == tes3.objectType.creature then
        return document.dataType.creatureSummary
    end
    return nil
end

--- Build a compact link description from identity fields that help choose the next resource.
--- Descriptions intentionally include raw ids so clients can distinguish same-title actors without reading each child first.
---@param dataType MCP.MemoryDataType
---@param baseId string
---@param referenceId string
---@param actorIdentityKind MCP.MemoryActorIdentityKind
---@return string
local function ActorLinkDescription(dataType, baseId, referenceId, actorIdentityKind)
    return string.format("data_type=%s base_id=%s reference_id=%s identity_kind=%s", dataType, baseId, referenceId, actorIdentityKind)
end

--- Find an existing observed actor entry for the same concrete reference id.
---@param observedActors table<string, MCP.MemoryObservedActor>
---@param referenceId string
---@return string?
local function FindObservedActorId(observedActors, referenceId)
    for actorId, observedActor in pairs(observedActors) do
        if observedActor.data and observedActor.data.reference_id == referenceId then
            return actorId
        end
    end
    return nil
end

--- Allocate a route-friendly id while preserving raw TES3 ids in actor data.
---@param observedActors table<string, MCP.MemoryObservedActor>
---@param baseId string
---@return string
local function NextActorId(observedActors, baseId)
    local baseSegment = SafeSegment(baseId)
    if not observedActors[baseSegment] then
        return baseSegment
    end

    local suffix = 2
    while observedActors[string.format("%s-%d", baseSegment, suffix)] do
        suffix = suffix + 1
    end
    return string.format("%s-%d", baseSegment, suffix)
end

--- Create an actor collection module; individual actor resource entries are rebuilt on refresh.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Actor
function this.new(params)
    params.publishOnLoaded = true
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_actor" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Actor
    instance.observedActors = {}
    instance.actorLinks = jsonrpc.array()
    instance.indexEntry = document.LiveEntry(collectionDescriptor, function()
        return instance:BuildIndexDocument()
    end)
    instance.entries = jsonrpc.array({ instance.indexEntry })
    instance.links = jsonrpc.array({ collectionLink })
    return instance
end

--- Remove all dynamic actor entries while keeping the collection entry owned by the module.
function this:ClearObservedActors()
    local previousCount = table.size(self.observedActors or {})
    self.observedActors = {}
    self.actorLinks = jsonrpc.array()
    self.entries = jsonrpc.array({ self.indexEntry })
    self.logger:debug("Memory actor observations cleared: previous_count=%d", previousCount)
end

--- Add one actor reference to the dynamic registry without clearing existing observations.
---@param ref tes3reference?
---@param reason string?
---@param publishIfVisible boolean?
---@return boolean added
function this:ObserveReference(ref, reason, publishIfVisible)
    if not ref or not IsActorReference(ref) or not ref.object then
        return false
    end

    local dataType = assert(ActorDataType(ref), "Actor references must have a supported Memory data type.")
    local baseId = ActorBaseId(ref)
    local referenceId = ActorReferenceId(ref)
    if FindObservedActorId(self.observedActors, referenceId) then
        self.logger:trace("Memory actor observation ignored: reason=%s cause=duplicate base_id=%s reference_id=%s", tostring(reason), baseId, referenceId)
        return false
    end

    local actorId = NextActorId(self.observedActors, baseId)
    local title = ActorTitle(ref)
    local descriptor = document.Descriptor(
        string.format("memory/actors/%s/index.json", actorId),
        title,
        string.format("Observed actor memory for %s.", title)
    )
    local actorIdentityKind = ActorIdentityKind(ref, baseId)
    local observedActor = jsonrpc.object({
        id = actorId,
        base_id = baseId,
        reference_id = referenceId,
        identity_kind = actorIdentityKind,
        is_instance = ref.object.isInstance == true,
        reference = obj.tes3reference(ref),
    })
    local entry = document.LiveEntry(descriptor, function()
        return self:BuildActorDocument(actorId)
    end)
    self.observedActors[actorId] = {
        id = actorId,
        title = title,
        descriptor = descriptor,
        entry = entry,
        subject = document.Subject(document.SubjectTypeFromObject(ref), actorId, title),
        source_description = reason and string.format("Observed actor reference from %s.", reason)
            or "Observed actor reference captured from active cells.",
        data_type = dataType,
        data = observedActor,
    }
    table.insert(self.actorLinks, document.Link(document.linkRel.actor, descriptor.uri, title, ActorLinkDescription(dataType, baseId, referenceId, actorIdentityKind)))
    table.insert(self.entries, entry)
    document.MarkDirty(self.indexEntry)

    if publishIfVisible ~= false and self.published then
        self.resource:PublishResource(entry)
    end
    self.logger:trace(
        "Memory actor observed: reason=%s actor_id=%s data_type=%s base_id=%s reference_id=%s identity_kind=%s published_now=%s",
        tostring(reason),
        actorId,
        dataType,
        baseId,
        referenceId,
        actorIdentityKind,
        tostring(publishIfVisible ~= false and self.published)
    )
    return true
end

--- Rebuild dynamic actor entries from active cells; the manager still sees only this one module.
function this:RefreshObservedActors()
    self:ClearObservedActors()
    if tes3.onMainMenu() then
        self.logger:debug("Memory actor refresh skipped: reason=main_menu")
        return
    end

    local cells = tes3.getActiveCells()
    if not cells then
        self.logger:debug("Memory actor refresh skipped: reason=no_active_cells")
        return
    end

    local cellCount = 0
    local observedCount = 0
    for _, cell in ipairs(cells) do
        cellCount = cellCount + 1
        if cell.actors then
            for ref in iter.ForEachReferenceList(cell.actors) do
                if self:ObserveReference(ref, "active cells", false) then
                    observedCount = observedCount + 1
                end
            end
        end
    end
    self.logger:debug("Memory actor refresh completed: cells=%d observed=%d total=%d", cellCount, observedCount, table.size(self.observedActors))
end

--- Observe the player's activation target when it changes.
---@param e activationTargetChangedEventData
function this:OnActivationTargetChanged(e)
    if e and self:ObserveReference(e.current, "activationTargetChanged") then
        self:MarkDirty()
        self.logger:debug("Memory actor activation target added: total=%d", table.size(self.observedActors))
    end
end

--- Register loaded refreshes from the base module and target observation for actor memory.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.activationTargetChangedCallback then
        return
    end

    self.activationTargetChangedCallback = function(e)
        self:OnActivationTargetChanged(e)
    end
    event.register(tes3.event.activationTargetChanged, self.activationTargetChangedCallback)
    self.logger:debug("Memory actor activation target handler registered")
end

--- Unregister actor-specific target observation and base loaded refreshes.
function this:UnregisterEvent()
    if self.activationTargetChangedCallback then
        event.unregister(tes3.event.activationTargetChanged, self.activationTargetChangedCallback)
        self.activationTargetChangedCallback = nil
        self.logger:debug("Memory actor activation target handler unregistered")
    end
    base.UnregisterEvent(self)
end

--- Return either the root actor collection link or the collection's observed actor child links.
---@param parentUri MCP.ResourceUri?
---@return MCP.MemoryLink[]
function this:GetLinksForParent(parentUri)
    if not self.published then
        return jsonrpc.array()
    end
    if parentUri == nil then
        return self.links
    end
    if parentUri == collectionDescriptor.uri then
        return self.actorLinks or jsonrpc.array()
    end
    return jsonrpc.array()
end

--- Refresh observed actor entries, then publish the collection and individual actor resources.
function this:Publish()
    self:RefreshObservedActors()
    self.logger:debug("Memory actor publish prepared: entries=%d actors=%d", table.size(self.entries), table.size(self.observedActors))
    base.Publish(self)
end

--- Unpublish current actor resources and clear dynamic state afterward.
function this:Unpublish()
    base.Unpublish(self)
    self:ClearObservedActors()
    self.logger:debug("Memory actor unpublished and dynamic state cleared")
end

--- Hide stale actor memory for a new game; otherwise publish after loading a save.
---@param e loadedEventData
function this:OnLoaded(e)
    if e.newGame then
        self:Unpublish()
        return
    end
    base.OnLoaded(self, e)
end

--- Build the actor collection Memory document with links to observed actor entries.
---@return MCP.MemoryDocument
function this:BuildIndexDocument()
    local links = self:GetLinksForParent(collectionDescriptor.uri)
    return document.Document(
        document.documentType.collection,
        document.dataType.actorIndex,
        collectionDescriptor.title,
        jsonrpc.object({
            actor_count = table.size(links),
        }),
        {
            scope = self.manager:GetScope(),
            links = links,
            source = document.Source(document.sourceKind.liveState, nil, nil, "Observed actor registry for active cells."),
        }
    )
end

--- Build one observed actor Memory document from the module's current captured state.
---@param actorId string
---@return MCP.MemoryDocument?
function this:BuildActorDocument(actorId)
    local observedActor = self.observedActors[actorId]
    if not observedActor then
        return nil
    end
    return document.Document(
        document.documentType.entity,
        observedActor.data_type,
        observedActor.title,
        observedActor.data,
        {
            subject = observedActor.subject,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, observedActor.source_description),
        }
    )
end

return this
