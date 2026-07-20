local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local iter = require("morrowind-mcp.tes3.iterator")

--- Memory module that owns one actor collection and many observed actor entries internally.
---@class MCP.Resources.Memory.Actor: MCP.Resources.MemoryModule
---@field indexEntry MCP.MemoryResourceEntry
---@field observedActors table<string, MCP.MemoryObservedActor>
---@field actorLinks MCP.MemoryLink[]
---@field activationTargetChangedCallback fun(e: activationTargetChangedEventData)?
---@field activateCallback fun(e: activateEventData)?
---@field dialogActivatedCallback fun(e: uiActivatedEventData)?
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

--- Player interaction strength for one observed actor.
---@enum MCP.MemoryActorInteractionState
local interactionState = {
    observed = "observed",
    targeted = "targeted",
    activated = "activated",
    conversed = "conversed",
}

--- Mechanical sources that can observe or update an actor memory entry.
---@enum MCP.MemoryActorObservationSource
local observationSource = {
    activeCells = "active_cells",
    activationTargetChanged = "activation_target_changed",
    activate = "activate",
    menuDialog = "menu_dialog",
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

--- Return a compact vector snapshot suitable for normal Memory reads.
---@param vector tes3vector3?
---@return MCP.AnyMap?
local function VectorSummary(vector)
    if not vector then
        return nil
    end
    return jsonrpc.object({
        x = vector.x,
        y = vector.y,
        z = vector.z,
    })
end

--- Return compact cell identity without serializing the full cell object.
---@param cell tes3cell?
---@return MCP.AnyMap?
local function CellSummary(cell)
    if not cell then
        return nil
    end
    return jsonrpc.object({
        id = cell.id,
        name = cell.name,
        display_name = cell.displayName,
        is_interior = cell.isInterior,
    })
end

--- Add a truthy field to a compact service map.
---@param target MCP.AnyMap
---@param key string
---@param value boolean?
local function SetTrueField(target, key, value)
    if value then
        target[key] = true
    end
end

--- Return services exposed by an NPC class without serializing the entire class record.
---@param class tes3class?
---@return MCP.AnyMap?
local function ClassServiceSummary(class)
    if not class then
        return nil
    end

    local offers = jsonrpc.object()
    SetTrueField(offers, "bartering", class.offersBartering)
    SetTrueField(offers, "enchanting", class.offersEnchanting)
    SetTrueField(offers, "repairs", class.offersRepairs)
    SetTrueField(offers, "spellmaking", class.offersSpellmaking)
    SetTrueField(offers, "spells", class.offersSpells)
    SetTrueField(offers, "training", class.offersTraining)

    local barters = jsonrpc.object()
    SetTrueField(barters, "alchemy", class.bartersAlchemy)
    SetTrueField(barters, "apparatus", class.bartersApparatus)
    SetTrueField(barters, "armor", class.bartersArmor)
    SetTrueField(barters, "books", class.bartersBooks)
    SetTrueField(barters, "clothing", class.bartersClothing)
    SetTrueField(barters, "enchanted_items", class.bartersEnchantedItems)
    SetTrueField(barters, "ingredients", class.bartersIngredients)
    SetTrueField(barters, "lights", class.bartersLights)
    SetTrueField(barters, "lockpicks", class.bartersLockpicks)
    SetTrueField(barters, "misc_items", class.bartersMiscItems)
    SetTrueField(barters, "probes", class.bartersProbes)
    SetTrueField(barters, "repair_tools", class.bartersRepairTools)
    SetTrueField(barters, "weapons", class.bartersWeapons)

    local services = jsonrpc.object()
    if table.size(offers) > 0 then
        services.offers = offers
    end
    if table.size(barters) > 0 then
        services.barters = barters
    end
    if table.size(services) == 0 then
        return nil
    end
    return services
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

--- Return true when an activate event was triggered by the player.
---@param ref tes3reference?
---@return boolean
local function IsPlayerActivator(ref)
    if not ref then
        return false
    end
    local mobilePlayer = tes3.mobilePlayer
    if mobilePlayer and mobilePlayer.reference and ref == mobilePlayer.reference then
        return true
    end
    local player = tes3.player
    if player ~= nil and (ref == player or ref.object == player or ref.baseObject == player) then
        return true
    end
    return ref.object and ref.object.objectType == tes3.objectType.npc and ref.object.id == "player"
end

--- Return the reference for a service/dialog actor returned by tes3ui.getServiceActor().
---@param serviceActor tes3mobileActor|tes3mobileCreature|tes3mobileNPC|tes3mobilePlayer|tes3reference|nil
---@return tes3reference?
local function ServiceActorReference(serviceActor)
    if not serviceActor then
        return nil
    end
    return serviceActor.reference or serviceActor
end

--- Map observation source to the strongest player interaction state it proves.
---@param source MCP.MemoryActorObservationSource
---@return MCP.MemoryActorInteractionState
local function InteractionStateForSource(source)
    if source == observationSource.menuDialog then
        return interactionState.conversed
    end
    if source == observationSource.activate then
        return interactionState.activated
    end
    if source == observationSource.activationTargetChanged then
        return interactionState.targeted
    end
    return interactionState.observed
end

--- Add one mechanical observation source to a source list.
---@param sourceKinds string[]?
---@param source MCP.MemoryActorObservationSource
---@return boolean changed
local function AddSourceKind(sourceKinds, source)
    if not sourceKinds then
        return false
    end
    for _, existingSource in ipairs(sourceKinds) do
        if existingSource == source then
            return false
        end
    end
    table.insert(sourceKinds, source)
    return true
end

--- Update lightweight actor facts as a blackboard of currently known values.
---@param data MCP.AnyMap
---@param ref tes3reference
---@param source MCP.MemoryActorObservationSource
local function UpdateActorFacts(data, ref, source)
    local actorObject = ref.object
    data.facts = data.facts or jsonrpc.object()
    data.facts.name = ActorTitle(ref)
    data.facts.subject_type = document.SubjectTypeFromReference(ref)
    data.facts.data_type = ActorDataType(ref)
    data.facts.alive = ref.isDead ~= true
    data.facts.is_empty = ref.isEmpty
    data.facts.is_respawn = ActorRespawns(ref)
    data.facts.is_leveled_spawn = ref.isLeveledSpawn == true
    data.facts.location = CellSummary(ref.cell)
    data.facts.position = VectorSummary(ref.position)
    data.facts.facing = ref.facing

    if actorObject then
        data.facts.actor_id = actorObject.id
        data.facts.race = actorObject.race and jsonrpc.object({
            id = actorObject.race.id,
            name = actorObject.race.name,
        }) or nil
        data.facts.class = actorObject.class and jsonrpc.object({
            id = actorObject.class.id,
            name = actorObject.class.name,
        }) or nil
        data.facts.level = actorObject.level
        data.facts.disposition = actorObject.disposition
        data.facts.health = actorObject.health
        data.facts.is_guard = actorObject.isGuard
        data.facts.is_essential = actorObject.isEssential
    end

    if source == observationSource.menuDialog and actorObject and actorObject.class then
        data.facts.services = ClassServiceSummary(actorObject.class)
    end
end

--- Mark interaction facts that are proven by a mechanical observation source.
---@param data MCP.AnyMap
---@param source MCP.MemoryActorObservationSource
local function UpdateInteractionFacts(data, source)
    data.interaction = data.interaction or jsonrpc.object()
    data.interaction.source_kinds = data.interaction.source_kinds or jsonrpc.array()
    AddSourceKind(data.interaction.source_kinds, source)
    data.interaction.state = data.interaction.state or interactionState.observed
    data.interaction.observed = data.interaction.observed or source == observationSource.activeCells
    if source == observationSource.activationTargetChanged then
        data.interaction.targeted = true
    elseif source == observationSource.activate then
        data.interaction.activated = true
    elseif source == observationSource.menuDialog then
        data.interaction.conversed = true
    end
end

--- Copy actor data for document output without full TES3 reference serialization.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.AnyMap
local function BuildActorData(observedActor)
    local sourceData = observedActor.data
    return jsonrpc.object({
        id = sourceData.id,
        base_id = sourceData.base_id,
        reference_id = sourceData.reference_id,
        identity_kind = sourceData.identity_kind,
        is_instance = sourceData.is_instance,
        facts = sourceData.facts,
        interaction = sourceData.interaction,
    })
end

--- Return true if the next state is stronger than the current state.
---@param current MCP.MemoryActorInteractionState?
---@param next MCP.MemoryActorInteractionState
---@return boolean
local function IsStrongerInteractionState(current, next)
    local order = {
        [interactionState.observed] = 1,
        [interactionState.targeted] = 2,
        [interactionState.activated] = 3,
        [interactionState.conversed] = 4,
    }
    return (order[next] or 0) > (order[current] or 0)
end

--- Return the source label used in human-readable document provenance.
---@param source MCP.MemoryActorObservationSource
---@return string
local function SourceDescriptionName(source)
    if source == observationSource.activationTargetChanged then
        return "activationTargetChanged"
    end
    if source == observationSource.activeCells then
        return "active cells"
    end
    if source == observationSource.menuDialog then
        return "MenuDialog"
    end
    return source
end

--- Build a compact link description from identity fields that help choose the next resource.
--- Descriptions intentionally include raw ids so clients can distinguish same-title actors without reading each child first.
---@param dataType MCP.MemoryDataType
---@param baseId string
---@param referenceId string
---@param actorIdentityKind MCP.MemoryActorIdentityKind
---@param actorInteractionState MCP.MemoryActorInteractionState
---@return string
local function ActorLinkDescription(dataType, baseId, referenceId, actorIdentityKind, actorInteractionState)
    return string.format(
        "data_type=%s base_id=%s reference_id=%s identity_kind=%s interaction_state=%s",
        dataType,
        baseId,
        referenceId,
        actorIdentityKind,
        actorInteractionState
    )
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

--- Update the actor collection link for a changed observed actor.
---@param actorLinks MCP.MemoryLink[]
---@param observedActor MCP.MemoryObservedActor
local function UpdateActorLink(actorLinks, observedActor)
    for _, link in ipairs(actorLinks) do
        if link.uri == observedActor.descriptor.uri then
            link.description = ActorLinkDescription(
                observedActor.data_type,
                observedActor.data.base_id,
                observedActor.data.reference_id,
                observedActor.data.identity_kind,
                observedActor.data.interaction.state
            )
            return
        end
    end
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
    self.logger:debug("Memory actor entries cleared: previous_count=%d", previousCount)
end

--- Add one actor reference to the dynamic registry without clearing existing actor memory entries.
---@param ref tes3reference?
---@param source MCP.MemoryActorObservationSource?
---@param publishIfVisible boolean?
---@return boolean changed
function this:ObserveReference(ref, source, publishIfVisible)
    if not ref or not IsActorReference(ref) or not ref.object then
        return false
    end

    source = source or observationSource.activeCells
    local nextInteractionState = InteractionStateForSource(source)
    local dataType = assert(ActorDataType(ref), "Actor references must have a supported Memory data type.")
    local baseId = ActorBaseId(ref)
    local referenceId = ActorReferenceId(ref)
    local existingActorId = FindObservedActorId(self.observedActors, referenceId)
    if existingActorId then
        local observedActor = self.observedActors[existingActorId]
        local changed = AddSourceKind(observedActor.data.interaction.source_kinds, source)
        UpdateActorFacts(observedActor.data, ref, source)
        UpdateInteractionFacts(observedActor.data, source)
        if IsStrongerInteractionState(observedActor.data.interaction.state, nextInteractionState) then
            observedActor.data.interaction.state = nextInteractionState
            changed = true
        end
        if source == observationSource.activate then
            observedActor.data.interaction.activation_count = (observedActor.data.interaction.activation_count or 0) + 1
            observedActor.source_description = string.format("Observed actor reference from %s.", SourceDescriptionName(source))
            changed = true
        end
        if source == observationSource.menuDialog then
            observedActor.data.interaction.conversation_count = (observedActor.data.interaction.conversation_count or 0) + 1
            observedActor.source_description = string.format("Observed actor reference from %s.", SourceDescriptionName(source))
            changed = true
        end
        if changed then
            document.MarkDirty(observedActor.entry)
            document.MarkDirty(self.indexEntry)
            UpdateActorLink(self.actorLinks, observedActor)
        end
        self.logger:trace(
            "Memory actor observation updated: source=%s actor_id=%s base_id=%s reference_id=%s interaction_state=%s changed=%s",
            source,
            existingActorId,
            baseId,
            referenceId,
            observedActor.data.interaction.state,
            tostring(changed)
        )
        return changed
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
        facts = jsonrpc.object(),
        interaction = jsonrpc.object({
            state = nextInteractionState,
            source_kinds = jsonrpc.array({ source }),
            observed = source == observationSource.activeCells,
            targeted = source == observationSource.activationTargetChanged,
            activated = source == observationSource.activate,
            conversed = source == observationSource.menuDialog,
            activation_count = source == observationSource.activate and 1 or 0,
            conversation_count = source == observationSource.menuDialog and 1 or 0,
        }),
    })
    UpdateActorFacts(observedActor, ref, source)
    local entry = document.LiveEntry(descriptor, function()
        return self:BuildActorDocument(actorId)
    end)
    entry.debugHandler = function(desc)
        local memoryDocument = self:BuildActorDocument(actorId)
        return { jsonrpc.TextResourceContents(desc.uri, json.encode(memoryDocument, { indent = true }), desc.mimeType) }
    end
    self.observedActors[actorId] = {
        id = actorId,
        title = title,
        descriptor = descriptor,
        entry = entry,
        subject = document.Subject(document.SubjectTypeFromObject(ref), actorId, title),
        source_description = string.format("Observed actor reference from %s.", SourceDescriptionName(source)),
        data_type = dataType,
        data = observedActor,
    }
    table.insert(self.actorLinks, document.Link(document.linkRel.actor, descriptor.uri, title, ActorLinkDescription(dataType, baseId, referenceId, actorIdentityKind, nextInteractionState)))
    table.insert(self.entries, entry)
    document.MarkDirty(self.indexEntry)

    if publishIfVisible ~= false and self.published then
        self.resource:PublishResource(entry)
    end
    self.logger:trace(
        "Memory actor observed: source=%s actor_id=%s data_type=%s base_id=%s reference_id=%s identity_kind=%s interaction_state=%s published_now=%s",
        source,
        actorId,
        dataType,
        baseId,
        referenceId,
        actorIdentityKind,
        nextInteractionState,
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
                if self:ObserveReference(ref, observationSource.activeCells, false) then
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
    if e and self:ObserveReference(e.current, observationSource.activationTargetChanged) then
        self:MarkDirty()
        self.logger:debug("Memory actor activation target observed: total=%d", table.size(self.observedActors))
    end
end

--- Observe actor references the player actually activates.
---@param e activateEventData
function this:OnActivate(e)
    if e and IsPlayerActivator(e.activator) and self:ObserveReference(e.target, observationSource.activate) then
        self:MarkDirty()
        self.logger:debug("Memory actor activated: total=%d", table.size(self.observedActors))
    end
end

--- Observe the actor attached to a newly opened dialogue menu.
---@param e uiActivatedEventData
function this:OnMenuDialogActivated(e)
    if not e or not e.newlyCreated then
        return
    end

    local serviceActor = tes3ui.getServiceActor()
    local ref = ServiceActorReference(serviceActor)
    if self:ObserveReference(ref, observationSource.menuDialog) then
        self:MarkDirty()
        self.logger:debug("Memory actor conversation observed: total=%d", table.size(self.observedActors))
    end
end

--- Register loaded refreshes from the base module and target observation for actor memory.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if not self.activationTargetChangedCallback then
        self.activationTargetChangedCallback = function(e)
            self:OnActivationTargetChanged(e)
        end
        event.register(tes3.event.activationTargetChanged, self.activationTargetChangedCallback)
        self.logger:debug("Memory actor activation target handler registered")
    end

    if not self.activateCallback then
        self.activateCallback = function(e)
            self:OnActivate(e)
        end
        event.register(tes3.event.activate, self.activateCallback)
        self.logger:debug("Memory actor activate handler registered")
    end

    if self.dialogActivatedCallback then
        return
    end
    self.dialogActivatedCallback = function(e)
        self:OnMenuDialogActivated(e)
    end
    event.register(tes3.event.uiActivated, self.dialogActivatedCallback, { filter = "MenuDialog" })
    self.logger:debug("Memory actor MenuDialog handler registered")
end

--- Unregister actor-specific target observation and base loaded refreshes.
function this:UnregisterEvent()
    if self.dialogActivatedCallback then
        event.unregister(tes3.event.uiActivated, self.dialogActivatedCallback)
        self.dialogActivatedCallback = nil
        self.logger:debug("Memory actor MenuDialog handler unregistered")
    end
    if self.activateCallback then
        event.unregister(tes3.event.activate, self.activateCallback)
        self.activateCallback = nil
        self.logger:debug("Memory actor activate handler unregistered")
    end
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
        BuildActorData(observedActor),
        {
            subject = observedActor.subject,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, observedActor.source_description),
        }
    )
end

return this
