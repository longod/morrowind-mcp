local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local document = require("morrowind-mcp.resources.memory.document")
local inventory = require("morrowind-mcp.resources.memory.inventory")
local inventoryutil = require("morrowind-mcp.util.inventory")

--- Helpers for actor-local actual and barter inventory Memory child resources.
--- Actor Memory owns event timing; this module owns snapshot resource state and payloads.
local this = {}

--- Return an inventory payload for an actor reference, or nil when its runtime inventory is unavailable.
---@param reference tes3reference?
---@param includeStack (fun(item: tes3item, itemData: tes3itemData?): boolean)?
---@return MCP.AnyMap?
local function ReadReferenceInventory(reference, includeStack)
    local actorInventory = inventoryutil.GetReferenceInventory(reference)
    if not actorInventory then
        return nil
    end
    return inventoryutil.ReadInventory(actorInventory, inventory.SerializeItem, inventory.SerializeItemData, includeStack)
end

--- Build a link to an actor's observed actual inventory snapshot.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.MemoryLink?
function this.InventoryLink(observedActor)
    if not observedActor.inventory_descriptor then
        return nil
    end
    return document.Link(
        document.linkRel.inventory,
        observedActor.inventory_descriptor.uri,
        string.format("%s Inventory Memory", observedActor.title),
        string.format("Inventory observed directly from %s.", observedActor.title)
    )
end

--- Build a link to an actor's merchant trade-eligible inventory snapshot.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.MemoryLink?
function this.BarterLink(observedActor)
    if not observedActor.barter_descriptor then
        return nil
    end
    return document.Link(
        document.linkRel.barter,
        observedActor.barter_descriptor.uri,
        string.format("%s Barter Inventory Memory", observedActor.title),
        string.format("Trade-eligible inventory observed for %s.", observedActor.title)
    )
end

--- Build all actor-local inventory child links.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.MemoryLink[]
function this.BuildLinks(observedActor)
    local links = jsonrpc.array()
    local inventoryLink = this.InventoryLink(observedActor)
    if inventoryLink then
        table.insert(links, inventoryLink)
    end
    local barterLink = this.BarterLink(observedActor)
    if barterLink then
        table.insert(links, barterLink)
    end
    return links
end

--- Build one actor inventory child document from its captured state.
---@param module MCP.Resources.Memory.Actor
---@param actorId string
---@param isBarter boolean
---@return MCP.MemoryDocument?
local function BuildDocument(module, actorId, isBarter)
    local observedActor = module.observedActors[actorId]
    if not observedActor then
        return nil
    end
    local data = isBarter and observedActor.barter_data or observedActor.inventory_data
    local source = isBarter and observedActor.barter_source or observedActor.inventory_source
    if not data or not source then
        return nil
    end
    local titleSuffix = isBarter and " Barter Inventory Memory" or " Inventory Memory"
    local dataType = isBarter and document.dataType.actorBarterItems or document.dataType.actorInventoryItems
    return document.Document(
        document.documentType.collection,
        dataType,
        observedActor.title .. titleSuffix,
        jsonrpc.object({
            actor_id = observedActor.id,
            base_id = observedActor.data.base_id,
            reference_id = observedActor.data.reference_id,
            inventory = data,
        }),
        {
            subject = observedActor.subject,
            scope = module.manager:GetScope(),
            source = source,
        }
    )
end

--- Capture one actor inventory child resource and publish it on first observation.
---@param module MCP.Resources.Memory.Actor
---@param observedActor MCP.MemoryObservedActor
---@param data MCP.AnyMap
---@param source MCP.MemorySource
---@param isBarter boolean
---@return boolean
local function Capture(module, observedActor, data, source, isBarter)
    local descriptorField = isBarter and "barter_descriptor" or "inventory_descriptor"
    local entryField = isBarter and "barter_entry" or "inventory_entry"
    local dataField = isBarter and "barter_data" or "inventory_data"
    local sourceField = isBarter and "barter_source" or "inventory_source"
    local suffix = isBarter and "barter.json" or "inventory.json"
    local titleSuffix = isBarter and " Barter Inventory Memory" or " Inventory Memory"
    local description = isBarter
        and string.format("Trade-eligible inventory observed for %s.", observedActor.title)
        or string.format("Inventory observed directly from %s.", observedActor.title)

    observedActor[dataField] = data
    observedActor[sourceField] = source
    if not observedActor[descriptorField] then
        observedActor[descriptorField] = document.Descriptor(
            string.format("memory/actors/%s/%s", observedActor.id, suffix),
            observedActor.title .. titleSuffix,
            description
        )
        observedActor[entryField] = document.SnapshotEntry(
            observedActor[descriptorField],
            assert(BuildDocument(module, observedActor.id, isBarter))
        )
        table.insert(module.entries, observedActor[entryField])
        if module.published then
            module.resource:PublishResource(observedActor[entryField])
        end
    else
        document.CaptureSnapshot(observedActor[entryField], BuildDocument(module, observedActor.id, isBarter))
    end
    module:CaptureActorSnapshot(observedActor)
    return true
end

--- Capture an actor's actual inventory after the player can directly inspect it.
---@param module MCP.Resources.Memory.Actor
---@param observedActor MCP.MemoryObservedActor
---@param reference tes3reference?
---@param eventName string
---@param description string
---@return boolean
function this.CaptureActual(module, observedActor, reference, eventName, description)
    local data = ReadReferenceInventory(reference)
    if not data then
        return false
    end
    return Capture(module, observedActor, data, document.Source(document.sourceKind.event, nil, eventName, description), false)
end

--- Capture a merchant's trade-eligible inventory using the MWSE item-record eligibility API.
---@param module MCP.Resources.Memory.Actor
---@param observedActor MCP.MemoryObservedActor
---@param reference tes3reference?
---@param eventName string
---@param description string
---@return boolean
function this.CaptureBarter(module, observedActor, reference, eventName, description)
    if not reference then
        return false
    end
    local data = ReadReferenceInventory(reference, function(item)
        return tes3.checkMerchantTradesItem({
            reference = reference,
            item = item,
        }) == true
    end)
    if not data then
        return false
    end
    return Capture(module, observedActor, data, document.Source(document.sourceKind.event, nil, eventName, description), true)
end

--- Build one actual-inventory child document.
---@param module MCP.Resources.Memory.Actor
---@param actorId string
---@return MCP.MemoryDocument?
function this.BuildInventoryDocument(module, actorId)
    return BuildDocument(module, actorId, false)
end

--- Build one barter-inventory child document.
---@param module MCP.Resources.Memory.Actor
---@param actorId string
---@return MCP.MemoryDocument?
function this.BuildBarterDocument(module, actorId)
    return BuildDocument(module, actorId, true)
end

return this
