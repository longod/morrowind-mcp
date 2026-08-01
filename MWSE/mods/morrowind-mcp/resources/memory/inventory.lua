local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local iter = require("morrowind-mcp.tes3.iterator")
local enumname = require("morrowind-mcp.tes3.enumname")
local inventoryutil = require("morrowind-mcp.util.inventory")

--- Memory module for the current player's live inventory collection.
---@class MCP.Resources.Memory.Inventory: MCP.Resources.MemoryModule
---@field inventoryEntry MCP.MemoryResourceEntry
---@field barterOfferCallback fun(e: barterOfferEventData)?
---@field menuEnterCallback fun(e: menuEnterEventData)?
---@field activateCallback fun(e: activateEventData)?
---@field enchantChargeUseCallback fun(e: enchantChargeUseEventData)?
---@field enchantedItemCreateFailedCallback fun(e: enchantedItemCreateFailedEventData)?
---@field enchantedItemCreatedCallback fun(e: enchantedItemCreatedEventData)?
---@field itemDroppedCallback fun(e: itemDroppedEventData)?
---@field pickpocketCallback fun(e: pickpocketEventData)?
---@field potionBrewFailedCallback fun(e: potionBrewFailedEventData)?
---@field potionBrewedCallback fun(e: potionBrewedEventData)?
---@field lockPickCallback fun(e: lockPickEventData)?
---@field repairCallback fun(e: repairEventData)?
---@field trapDisarmCallback fun(e: trapDisarmEventData)?
local this = {}
setmetatable(this, { __index = base })

local inventoryMenuId = tes3ui.registerID("MenuInventory")

local descriptor = document.Descriptor(
    "memory/player/inventory.json",
    "Player Inventory Memory",
    "Memory snapshot of the current player's inventory."
)

local inventoryLink = document.Link(
    document.linkRel.inventory,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

---@param i tes3effect
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3effect(i, o)
    if i == nil then
        return nil
    end
    if type(i.id) == "number" and i.id < 0 then -- empty?
        return nil
    end

    o = o or jsonrpc.object()

    o.attribute = enumname.attribute(i.attribute)
    -- o.cost = i.cost -- FIXME game_calcSingleEffectCost broken?
    o.duration = i.duration
    o.id = enumname.effect(i.id) or i.id
    o.max = i.max
    o.min = i.min
    -- o.object = obj.tes3magicEffect(i.object) -- VFXs and sounds
    o.radius = i.radius
    o.rangeType = enumname.effectRange(i.rangeType)
    o.skill = enumname.skill(i.skill)
    return o
end

---@param i tes3enchantment?
---@return MCP.AnyMap?
function this.tes3enchantment(i)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    if i.deleted then
        return nil
    end
    if i.disabled then
        return nil
    end
    local o = jsonrpc.object()

    o.id = i.id

    -- o.autoCalc = i.autoCalc
    o.castType = enumname.enchantmentType(i.castType)
    o.chargeCost = i.chargeCost
    o.effects = iter.ForEachObject(i.effects, this.tes3effect)
    -- o.flags = i.flags -- flags mean?
    o.maxCharge = i.maxCharge

    return o
end

---@param i tes3soulGemData
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3soulGemData(i, o)
    if i == nil then
        return nil
    end
    o = o or jsonrpc.object()

    o.capacity = i.capacity
    o.id = i.id
    -- o.item = i.item -- reference back to item
    -- o.mesh = i.mesh
    o.name = i.name
    -- o.texture = i.texture
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3skill
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3skill(i, o)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    if i.deleted then
        return nil
    end
    if i.disabled then
        return nil
    end
    o = o or jsonrpc.object()
    -- o.id = i.id -- baseobject string id conflicts with enumname.skill(i.id)?

    -- o.actions = jsonrpc.array(i.actions) -- TODO naming
    o.attribute = enumname.attribute(i.attribute)
    o.description = i.description
    -- o.iconPath = i.iconPath
    o.id = enumname.skill(i.id)
    o.name = i.name
    o.specialization = enumname.specialization(i.specialization)

    return o
end

---@param i tes3alchemy
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3alchemy(i, o)
    -- o.autoCalc = i.autoCalc
    o.effects = iter.ForEachObject(i.effects, this.tes3effect)
    -- o.flags = i.flags
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight
    return o
end

---@param i tes3apparatus
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3apparatus(i, o)
    o.quality  = i.quality
    -- o.script  = this.tes3script(i.script)
    o.type  = enumname.apparatusType(i.type)
    o.value  = i.value
    o.weight  = i.weight
    return o
end

---@param i tes3book
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3book(i, o)
    if i.enchantCapacity > 0 then
        o.enchantCapacity = i.enchantCapacity
    end
    o.enchantment = this.tes3enchantment(i.enchantment)
    -- o.script = this.tes3script(i.script)
    o.skill = enumname.skill(i.skill)
    -- o.text = i.text -- TODO  dont read open check flag? convert html to markdown or json. or just empty until activate.
    o.type = enumname.bookType(i.type)
    o.value = i.value
    o.weight = i.weight
    return o
end

---@param i tes3armor
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3armor(i, o)

    o.armorRating = i.armorRating
    o.armorScalar = i.armorScalar
    if i.enchantCapacity > 0 then
        o.enchantCapacity = i.enchantCapacity
    end
    o.enchantment = this.tes3enchantment(i.enchantment)
    if i.isClosedHelmet then
        o.isClosedHelmet = i.isClosedHelmet
    end
    if i.isLeftPart then
        o.isLeftPart = i.isLeftPart
    end
    o.isUsableByBeasts = i.isUsableByBeasts
    o.maxCondition = i.maxCondition
    -- o.parts = iter.ForEachObject(i.parts, )
    -- o.script = this.tes3script(i.script)
    o.slot = enumname.armorSlot(i.slot) -- same as slotName?
    o.slotName = i.slotName
    o.value = i.value
    o.weight = i.weight
    o.weightClass = enumname.armorWeightClass(i.weightClass)
    return o
end

---@param i tes3clothing
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3clothing(i, o)
    if i.enchantCapacity > 0 then
        o.enchantCapacity = i.enchantCapacity
    end
    o.enchantment =  this.tes3enchantment(i.enchantment)
    if i.isLeftPart then
        o.isLeftPart = i.isLeftPart
    end
    o.isUsableByBeasts = i.isUsableByBeasts
    -- o.parts = i.parts
    -- o.script = this.tes3script(i.script)
    o.slot = enumname.clothingSlot(i.slot)
    o.slotName = i.slotName
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3ingredient
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3ingredient(i, o)

    o.effectAttributeIds = iter.ForEachObject(i.effectAttributeIds, function(value)
        return enumname.attribute(value) or nil
    end)
    o.effects = iter.ForEachObject(i.effects, function(value)
        return enumname.effect(value) or nil
    end)
    o.effectSkillIds = iter.ForEachObject(i.effectSkillIds, function(value)
        return enumname.skill(value) or nil
    end)
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight
    return o
end

---@param i tes3light
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3light(i, o)
    -- o.canCarry = i.canCarry
    -- o.color = jsonrpc.array(i.color)
    -- o.flickers = i.flickers
    -- o.flickersSlowly = i.flickersSlowly
    -- o.isDynamic = i.isDynamic
    -- o.isFire = i.isFire
    -- o.isNegative = i.isNegative
    -- o.isOffByDefault = i.isOffByDefault
    -- o.pulses = i.pulses
    -- o.pulsesSlowly = i.pulsesSlowly
    o.radius = i.radius
    -- o.script = this.tes3script(i.script)
    -- o.sound = this.tes3sound(i.sound)
    o.time = i.time
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3lockpick
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3lockpick(i, o)

    o.maxCondition = i.maxCondition
    o.quality = i.quality
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight
    return o
end

---@param i tes3misc
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3misc(i, o)
    if i.isGold then
        o.isGold = i.isGold
    end
    if i.isKey then
        o.isKey = i.isKey
    end
    if i.isSoulGem then
        o.isSoulGem = i.isSoulGem
        o.soulGemCapacity = i.soulGemCapacity
        o.soulGemData = this.tes3soulGemData(i.soulGemData)
    end
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3probe
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3probe(i, o)
    o.maxCondition = i.maxCondition
    o.quality = i.quality
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3repairTool
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3repairTool(i, o)

    o.maxCondition = i.maxCondition
    o.quality = i.quality
    -- o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    return o
end

---@param i tes3weapon
---@param o MCP.AnyMap
---@return MCP.AnyMap
function this.tes3weapon(i, o)
    o.chopMax = i.chopMax
    o.chopMin = i.chopMin
    if i.enchantCapacity > 0 then
        o.enchantCapacity = i.enchantCapacity
    end
    o.enchantment = this.tes3enchantment(i.enchantment)
    -- o.flags = i.flags
    if i.hasDurability then
        -- o.hasDurability = i.hasDurability
        o.maxCondition = i.maxCondition
    end
    o.ignoresNormalWeaponResistance = i.ignoresNormalWeaponResistance
    if i.isAmmo then
        o.isAmmo = i.isAmmo
    end
    if i.isMelee then
        o.isMelee = i.isMelee
    end
    if i.isOneHanded then
        o.isOneHanded = i.isOneHanded
    end
    if i.isProjectile then
        o.isProjectile = i.isProjectile
    end
    if i.isRanged then
        o.isRanged = i.isRanged
    end
    o.isSilver = i.isSilver
    if i.isTwoHanded then
        o.isTwoHanded = i.isTwoHanded
    end
    -- o.maxCondition = i.maxCondition
    o.reach = i.reach
    -- o.script = this.tes3script(i.script)
    o.skill = this.tes3skill(i.skill)
    o.skillId = enumname.skill(i.skillId)
    o.slashMax = i.slashMax
    o.slashMin = i.slashMin
    o.speed = i.speed
    o.thrustMax = i.thrustMax
    o.thrustMin = i.thrustMin
    o.type = enumname.weaponType(i.type) -- same as typeName?
    o.typeName = i.typeName
    o.value = i.value
    o.weight = i.weight

    return o
end

local objectHandler = {
    ["alchemy"] = this.tes3alchemy,
    ["ammunition"] = this.tes3weapon,
    ["apparatus"] = this.tes3apparatus,
    ["armor"] = this.tes3armor,
    ["book"] = this.tes3book,
    ["clothing"] = this.tes3clothing,
    ["ingredient"] = this.tes3ingredient,
    ["light"] = this.tes3light,
    ["lockpick"] = this.tes3lockpick,
    ["miscItem"] = this.tes3misc,
    ["probe"] = this.tes3probe,
    ["repairItem"] = this.tes3repairTool,
    ["weapon"] = this.tes3weapon,
}

--- lightweight item serializer
---@param i tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon
function this.tes3item(i)
    if not i:isValid() then
        return nil
    end
    if i.deleted then
        return nil
    end
    if i.disabled then
        return nil
    end

    local objectType = enumname.objectType(i.objectType)
    if not objectType then
        return nil
    end
    local handler = objectHandler[objectType]
    if not handler then
        return nil
    end
    local o = jsonrpc.object()
    o.id = i.id
    o.name = i.name
    o.objectType = enumname.objectType(i.objectType)

    -- if i.promptsEquipmentReevaluation then
    --     o.promptsEquipmentReevaluation = i.promptsEquipmentReevaluation
    -- end
    if #i.stolenList > 0 then
        o.stolen = true
    end

    return handler(i, o)
end


--- Capture the serialized item definition used by an inventory entry.
---@param item tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon
---@return MCP.AnyMap
function this.SerializeItem(item)
    return this.tes3item(item)
end

--- Capture mutable item-data fields that distinguish inventory stacks.
--- Arbitrary mod data and static object definitions are intentionally excluded.
---@param itemData tes3itemData?
---@param item tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon
---@return MCP.AnyMap?
function this.SerializeItemData(itemData, item)
    if not itemData then
        return nil
    end
    local charge = nil
    if item.objectType == tes3.objectType.miscItem then
        -- FIXME The charge of the item. Provides incorrect values on misc items, which instead have a soul actor.
    elseif item.enchantment then -- is it correctly?
        charge = itemData.charge
    end
    local condition = nil
    if item.objectType == tes3.objectType.light then
        condition = itemData.timeLeft
    elseif item.maxCondition then
        condition = itemData.condition
    end

    return jsonrpc.object({
        charge = charge,
        condition = condition,
        scriptId = itemData.script and itemData.script.id or nil,
        soulId = itemData.soul and itemData.soul.id or nil,
    })
end

--- Return whether an item is the standard gold stack represented separately by this module.
---@param item tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon|nil
---@return boolean
local function IsGoldItem(item)
    return item ~= nil and item.isGold == true
end

--- Return whether the active player currently carries the specific event item.
--- This avoids treating items used by other actors as player-inventory mutations.
---@param item tes3item|nil
---@param itemData tes3itemData|nil
---@return boolean
local function PlayerInventoryContains(item, itemData)
    local player = tes3.mobilePlayer
    if player == nil or player.inventory == nil or item == nil then
        return false
    end
    local inventory = player.inventory
    ---@cast inventory tes3inventory
    return inventory:contains(item, itemData)
end

--- Return whether MenuInventory is visible for the eventual-consistency fallback.
---@return boolean
local function InventoryMenuVisible()
    local menu = tes3ui.findMenu(inventoryMenuId)
    return menu ~= nil and menu.visible == true
end

--- Create the player inventory module and its one linked collection resource.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Inventory
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = descriptor.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_inventory" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Inventory
    instance.inventoryEntry = document.LiveEntry(descriptor, function()
        return instance:BuildInventoryDocument()
    end)
    instance.entries = jsonrpc.array({ instance.inventoryEntry })
    instance.links = jsonrpc.array({ inventoryLink })
    return instance
end

--- Read and serialize the complete current player inventory for a live document build.
---@return MCP.AnyMap
function this:ReadInventoryData()
    if tes3.onMainMenu() or not tes3.mobilePlayer or not tes3.mobilePlayer.inventory then
        self.logger:debug("Memory inventory live read skipped: reason=no_player")
        return inventoryutil.ReadInventory(nil, this.SerializeItem, this.SerializeItemData)
    end

    local data = inventoryutil.ReadInventory(tes3.mobilePlayer.inventory, this.SerializeItem, this.SerializeItemData)
    self.logger:debug("Memory inventory live read: gold=%d stacks=%d", data.gold, data.item_count)
    return data
end

--- Publish one dirty notification for a burst of inventory mutations.
--- Repeated actions do not republish until a client has rebuilt the live entry.
---@param reason string
function this:InvalidateInventory(reason)
    if not self.published or self.inventoryEntry.cache.dirty then
        return
    end
    self.logger:debug("Memory inventory invalidated: reason=%s", reason)
    self:Publish()
end

--- Invalidate after an accepted player barter transaction.
---@param e barterOfferEventData
function this:OnBarterOffer(e)
    if not e or e.success ~= true then
        return
    end
    self:InvalidateInventory("barter_offer")
end

--- Invalidate after the player activates an object, including an item pickup.
---@param e activateEventData
function this:OnActivate(e)
    if not e or e.activator ~= tes3.player then
        return
    end
    self:InvalidateInventory("activate")
end

--- Invalidate after the player spends charge on a carried enchanted item.
---@param e enchantChargeUseEventData
function this:OnEnchantChargeUse(e)
    if not e or not e.isCast or e.caster ~= tes3.player or not PlayerInventoryContains(e.item, e.itemData) then
        return
    end
    self:InvalidateInventory("enchant_charge_use")
end

--- Invalidate after the player completes an enchantment attempt.
---@param e enchantedItemCreateFailedEventData|enchantedItemCreatedEventData
function this:OnEnchantedItemCreated(e)
    if not e or e.enchanterReference ~= tes3.player then
        return
    end
    self:InvalidateInventory("enchanted_item_created")
end

--- Invalidate after a player item drop.
---@param e itemDroppedEventData
function this:OnItemDropped(e)
    self:InvalidateInventory("item_dropped")
end

--- Invalidate when a pickpocket window closes after its transfer operations complete.
---@param e pickpocketEventData
function this:OnPickpocket(e)
    if not e or e.item ~= nil then
        return
    end
    self:InvalidateInventory("pickpocket_closed")
end

--- Invalidate after a potion-brewing attempt changes player ingredients or output.
---@param e potionBrewFailedEventData|potionBrewedEventData
function this:OnPotionBrewed(e)
    self:InvalidateInventory("potion_brewed")
end

--- Invalidate only when the player uses a physical lockpick carried in inventory.
---@param e lockPickEventData
function this:OnLockPick(e)
    if not e or e.picker ~= tes3.mobilePlayer or not e.tool or e.tool.objectType ~= tes3.objectType.lockpick
        or not PlayerInventoryContains(e.tool, e.toolItemData) then
        return
    end
    self:InvalidateInventory("lock_pick")
end

--- Invalidate only when the player uses a physical probe carried in inventory.
---@param e trapDisarmEventData
function this:OnTrapDisarm(e)
    if not e or e.disarmer ~= tes3.mobilePlayer or not e.tool or e.tool.objectType ~= tes3.objectType.probe
        or not PlayerInventoryContains(e.tool, e.toolItemData) then
        return
    end
    self:InvalidateInventory("trap_disarm")
end

--- Invalidate a successful player repair when both affected items are still carried.
---@param e repairEventData
function this:OnRepair(e)
    if not e or e.repairer ~= tes3.mobilePlayer or e.roll >= e.chance
        or not PlayerInventoryContains(e.item, e.itemData) or not PlayerInventoryContains(e.tool, e.toolData) then
        return
    end
    self:InvalidateInventory("repair")
end

--- Use MenuInventory entry as an eventual-consistency fallback for unattributed mutations.
---@param e menuEnterEventData
function this:OnMenuEnter(e)
    if InventoryMenuVisible() then
        self:InvalidateInventory("menu_inventory_visible")
    end
end

--- Register inventory-specific event callbacks alongside the standard loaded callback.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if not self.barterOfferCallback then
        self.barterOfferCallback = function(e) self:OnBarterOffer(e) end
        event.register(tes3.event.barterOffer, self.barterOfferCallback)
    end
    if not self.menuEnterCallback then
        self.menuEnterCallback = function(e) self:OnMenuEnter(e) end
        event.register(tes3.event.menuEnter, self.menuEnterCallback)
    end
    if not self.activateCallback then
        self.activateCallback = function(e) self:OnActivate(e) end
        event.register(tes3.event.activate, self.activateCallback)
    end
    if not self.enchantChargeUseCallback then
        self.enchantChargeUseCallback = function(e) self:OnEnchantChargeUse(e) end
        event.register(tes3.event.enchantChargeUse, self.enchantChargeUseCallback)
    end
    if not self.enchantedItemCreateFailedCallback then
        self.enchantedItemCreateFailedCallback = function(e) self:OnEnchantedItemCreated(e) end
        event.register(tes3.event.enchantedItemCreateFailed, self.enchantedItemCreateFailedCallback)
    end
    if not self.enchantedItemCreatedCallback then
        self.enchantedItemCreatedCallback = function(e) self:OnEnchantedItemCreated(e) end
        event.register(tes3.event.enchantedItemCreated, self.enchantedItemCreatedCallback)
    end
    if not self.itemDroppedCallback then
        self.itemDroppedCallback = function(e) self:OnItemDropped(e) end
        event.register(tes3.event.itemDropped, self.itemDroppedCallback)
    end
    if not self.pickpocketCallback then
        self.pickpocketCallback = function(e) self:OnPickpocket(e) end
        event.register(tes3.event.pickpocket, self.pickpocketCallback)
    end
    if not self.potionBrewFailedCallback then
        self.potionBrewFailedCallback = function(e) self:OnPotionBrewed(e) end
        event.register(tes3.event.potionBrewFailed, self.potionBrewFailedCallback)
    end
    if not self.potionBrewedCallback then
        self.potionBrewedCallback = function(e) self:OnPotionBrewed(e) end
        event.register(tes3.event.potionBrewed, self.potionBrewedCallback)
    end
    if not self.lockPickCallback then
        self.lockPickCallback = function(e) self:OnLockPick(e) end
        event.register(tes3.event.lockPick, self.lockPickCallback)
    end
    if not self.repairCallback then
        self.repairCallback = function(e) self:OnRepair(e) end
        event.register(tes3.event.repair, self.repairCallback)
    end
    if not self.trapDisarmCallback then
        self.trapDisarmCallback = function(e) self:OnTrapDisarm(e) end
        event.register(tes3.event.trapDisarm, self.trapDisarmCallback)
    end
end

--- Unregister inventory-specific callbacks before releasing the standard loaded callback.
function this:UnregisterEvent()
    local callbacks = {
        { "trapDisarmCallback", tes3.event.trapDisarm },
        { "repairCallback", tes3.event.repair },
        { "lockPickCallback", tes3.event.lockPick },
        { "potionBrewedCallback", tes3.event.potionBrewed },
        { "potionBrewFailedCallback", tes3.event.potionBrewFailed },
        { "pickpocketCallback", tes3.event.pickpocket },
        { "itemDroppedCallback", tes3.event.itemDropped },
        { "enchantedItemCreatedCallback", tes3.event.enchantedItemCreated },
        { "enchantedItemCreateFailedCallback", tes3.event.enchantedItemCreateFailed },
        { "enchantChargeUseCallback", tes3.event.enchantChargeUse },
        { "activateCallback", tes3.event.activate },
        { "menuEnterCallback", tes3.event.menuEnter },
        { "barterOfferCallback", tes3.event.barterOffer },
    }
    for _, callback in ipairs(callbacks) do
        local callbackName = callback[1]
        local eventId = callback[2]
        if self[callbackName] then
            event.unregister(eventId, self[callbackName])
            self[callbackName] = nil
        end
    end
    base.UnregisterEvent(self)
end

--- Build the serialized inventory collection from the current player inventory.
---@return MCP.MemoryDocument
function this:BuildInventoryDocument()
    local data = self:ReadInventoryData()
    local subjectType = document.SubjectTypeFromObject(tes3.player)
    return document.Document(
        document.documentType.collection,
        document.dataType.inventoryItems,
        descriptor.title,
        data,
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player inventory read on demand."),
        }
    )
end

return this
