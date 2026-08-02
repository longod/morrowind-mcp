local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local inventory = require("morrowind-mcp.resources.memory.inventory")
local player = require("morrowind-mcp.resources.memory.player")

--- Memory module for the current player's live equipped item collection.
---@class MCP.Resources.Memory.Equipment: MCP.Resources.MemoryModule
---@field equipmentEntry MCP.MemoryResourceEntry
---@field equippedCallback fun(e: equippedEventData)?
---@field unequippedCallback fun(e: unequippedEventData)?
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/player/equipment.json",
    "Player Equipment Memory",
    "Memory snapshot of the current player's equipped items."
)

local equipmentLink = document.Link(
    document.linkRel.equipment,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

--- Create the player-child equipment module and its live resource entry.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Equipment
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = player.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_equipment" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Equipment
    instance.equipmentEntry = document.LiveEntry(descriptor, function()
        return instance:BuildEquipmentDocument()
    end)
    instance.entries = jsonrpc.array({ instance.equipmentEntry })
    instance.links = jsonrpc.array({ equipmentLink })
    return instance
end

--- Return whether an equipment event belongs to the active player.
---@param e equippedEventData|unequippedEventData?
---@return boolean
local function IsPlayerEquipmentEvent(e)
    return e ~= nil and (e.reference == tes3.player or e.mobile == tes3.mobilePlayer)
end

--- Read current equipped stacks without inferring slots from item definitions.
---@return MCP.AnyMap
function this:ReadEquipmentData()
    local mobilePlayer = tes3.mobilePlayer
    local playerReference = tes3.player
    local actor = playerReference and playerReference.object
    local items = jsonrpc.array()
    if tes3.onMainMenu() or not actor or not actor.equipment then
        self.logger:debug("Memory equipment live read skipped: reason=no_player")
        return jsonrpc.object({
            available = false,
            item_count = table.size(items),
            items = items,
        })
    end

    -- The player reference owns the actor instance equipment; firstPerson is only the rendered NPC.
    for _, stack in ipairs(actor.equipment) do
        if stack and stack.object then
            local count = stack == mobilePlayer.readiedAmmo and mobilePlayer.readiedAmmoCount or 1
            table.insert(items, jsonrpc.object({
                item = inventory.SerializeItem(stack.object),
                itemData = inventory.SerializeItemData(stack.itemData, stack.object),
                count = count,
            }))
        end
    end

    self.logger:debug("Memory equipment live read: stacks=%d", table.size(items))
    return jsonrpc.object({
        available = true,
        item_count = table.size(items),
        items = items,
    })
end

--- Invalidate one clean live entry after a confirmed player equipment mutation.
---@param reason string
function this:InvalidateEquipment(reason)
    if not self.published or self.equipmentEntry.cache.dirty then
        return
    end
    self.logger:debug("Memory equipment invalidated: reason=%s", reason)
    self:Publish()
end

--- Invalidate only when a completed equipment event targets the player.
---@param e equippedEventData|unequippedEventData?
function this:OnEquipmentChanged(e)
    if IsPlayerEquipmentEvent(e) then
        self:InvalidateEquipment("equipment_changed")
    end
end

--- Register post-mutation equipment event invalidators with the standard loaded callback.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if not self.equippedCallback then
        self.equippedCallback = function(e) self:OnEquipmentChanged(e) end
        event.register(tes3.event.equipped, self.equippedCallback)
    end
    if not self.unequippedCallback then
        self.unequippedCallback = function(e) self:OnEquipmentChanged(e) end
        event.register(tes3.event.unequipped, self.unequippedCallback)
    end
end

--- Unregister equipment event callbacks before releasing the module.
function this:UnregisterEvent()
    if self.equippedCallback then
        event.unregister(tes3.event.equipped, self.equippedCallback)
        self.equippedCallback = nil
    end
    if self.unequippedCallback then
        event.unregister(tes3.event.unequipped, self.unequippedCallback)
        self.unequippedCallback = nil
    end
    base.UnregisterEvent(self)
end

--- Build the current player equipment collection from the live actor equipment array.
---@return MCP.MemoryDocument
function this:BuildEquipmentDocument()
    local data = self:ReadEquipmentData()
    local subjectType = document.SubjectTypeFromObject(tes3.player)
    return document.Document(
        document.documentType.collection,
        document.dataType.equipmentItems,
        descriptor.title,
        data,
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player equipment read on demand."),
        }
    )
end

return this
