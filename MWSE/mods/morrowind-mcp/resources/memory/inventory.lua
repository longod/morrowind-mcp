local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local iter = require("morrowind-mcp.tes3.iterator")
local obj = require("morrowind-mcp.tes3.object")
local enumname = require("morrowind-mcp.tes3.enumname")

--- Memory module for the current player's inventory snapshot.
---@class MCP.Resources.Memory.Inventory: MCP.Resources.MemoryModule
---@field inventoryEntry MCP.MemoryResourceEntry
---@field snapshot MCP.MemoryInventoryStack[]
---@field snapshotByItemId table<string, MCP.MemoryInventoryStack[]> Runtime-only serialized stack index.
---@field gold integer
---@field snapshotAvailable boolean
---@field snapshotCurrent boolean
---@field inventoryMenuWasVisible boolean
---@field barterOfferCallback fun(e: barterOfferEventData)?
---@field uiActivatedCallback fun(e: uiActivatedEventData)?
---@field menuEnterCallback fun(e: menuEnterEventData)?
---@field menuExitCallback fun(e: menuExitEventData)?
local this = {}
setmetatable(this, { __index = base })

local inventoryMenuId = tes3ui.registerID("MenuInventory")
local standardStackKey = "normal"

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
    -- FIXME FIX TEST
    -- if not i:isValid() then
    --     return nil
    -- end
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
    -- FIXME FIX TEST
    -- if not i:isValid() then
    --     return nil
    -- end
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
    -- FIXME FIX TEST
    -- if not i:isValid() then
    --     return nil
    -- end
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


--- Return whether the player inventory menu currently exists and is visible.
---@return boolean
local function InventoryMenuVisible()
    local menu = tes3ui.findMenu(inventoryMenuId)
    return menu ~= nil and menu.visible == true
end

--- Capture only the stable item identity and display name needed by an inventory stack.
---@param item tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon
---@return MCP.AnyMap
local function SerializeItem(item)
    return this.tes3item(item)
end

--- Equality check for itemData
---@param l tes3itemData
---@param r tes3itemData
local function EqualsItemData(l, r)
    if l.charge ~= r.charge then -- without miscitem?
        return false
    end
    if l.condition ~= r.condition then -- without light?
        return false
    end
    if l.count ~= r.count then
        return false
    end
    -- TODO requirement
    local lowner = l.owner and l.owner.id or nil
    local rowner = r.owner and r.owner.id or nil
    if lowner ~= rowner then
        return false
    end
    local lscript = l.script and l.script.id or nil
    local rscript = r.script and r.script.id or nil
    if lscript ~= rscript then
        return false
    end
    local lsoul = l.soul and l.soul.id or nil
    local rsoul = r.soul and r.soul.id or nil
    if lsoul ~= rsoul then
        return false
    end
     if l.timeLeft ~= r.timeLeft then -- light only?
        return false
    end
    return true
end

--- Capture mutable item-data fields that distinguish inventory stacks.
--- Arbitrary mod data and static object definitions are intentionally excluded.
---@param itemData tes3itemData?
---@param item tes3alchemy|tes3apparatus|tes3armor|tes3book|tes3clothing|tes3ingredient|tes3item|tes3light|tes3lockpick|tes3misc|tes3probe|tes3repairTool|tes3weapon
---@return MCP.AnyMap?
local function SerializeItemData(itemData, item)
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

-- TODO read_policy snapshot entry is not exists.
-- event driven update should be snapshot? inventory, actor...

--- Create the player inventory module and its one linked collection resource.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Inventory
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = descriptor.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_inventory" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Inventory
    instance.snapshot = jsonrpc.array()
    instance.snapshotByItemId = {}
    instance.gold = 0
    instance.snapshotAvailable = false
    instance.snapshotCurrent = false
    instance.inventoryMenuWasVisible = false
    instance.inventoryEntry = document.LiveEntry(descriptor, function()
        return instance:BuildInventoryDocument()
    end)
    instance.entries = jsonrpc.array({ instance.inventoryEntry })
    instance.links = jsonrpc.array({ inventoryLink })
    return instance
end

--- Replace the runtime snapshot from the complete current player inventory.
---@return boolean
function this:RefreshSnapshot()
    self.snapshot = jsonrpc.array()
    self.snapshotByItemId = {}
    self.gold = 0
    self.snapshotAvailable = false
    self.snapshotCurrent = false
    if tes3.onMainMenu() or not tes3.mobilePlayer or not tes3.mobilePlayer.inventory then
        self:MarkDirty()
        self.logger:debug("Memory inventory refresh skipped: reason=no_player")
        return false
    end

    for item, count, itemData in iter.ForEachInventory(tes3.mobilePlayer.inventory) do
        if IsGoldItem(item) then
            self.gold = self.gold + count
        else
            local itemId = item.id
            local stack = {
                itemId = itemId,
                item = SerializeItem(item),
                itemData = SerializeItemData(itemData, item),
                count = count,
                snapshotIndex = table.size(self.snapshot) + 1,
            }
            local itemBin = self.snapshotByItemId[itemId]
            if not itemBin then
                itemBin = {}
                self.snapshotByItemId[itemId] = itemBin
            end
            table.insert(itemBin, stack)
            table.insert(self.snapshot, stack)
        end
    end
    self.snapshotAvailable = true
    self.snapshotCurrent = true
    self:MarkDirty()
    self.logger:debug("Memory inventory refreshed: stacks=%d", table.size(self.snapshot))
    return true
end

--- Apply the gold portion of a successful barter to the aggregated player gold balance.
---@param delta integer
---@return boolean
function this:ApplyGoldDelta(delta)
    local nextGold = self.gold + delta
    if nextGold < 0 then
        return false
    end
    self.gold = nextGold
    return true
end

--- Want to apply a completed barter transaction without re-enumerating the whole inventory. but it was complicated to do this correctly, so for now just refresh the whole inventory after a barter.
---@param e barterOfferEventData
function this:OnBarterOffer(e)
    if not e or e.success ~= true or not self.snapshotAvailable or not self.snapshotCurrent then
        return
    end

    self:RefreshSnapshot()

end

--- Refresh after MenuInventory is built or made visible, only when the menu is visible.
---@param e uiActivatedEventData
function this:OnInventoryUiActivated(e)
    if not e or not e.element or e.element.id ~= inventoryMenuId or not InventoryMenuVisible() then
        return
    end
    self.inventoryMenuWasVisible = true
    self:RefreshSnapshot()
end

--- Refresh when any menu-mode entry leaves MenuInventory visible in the composed UI.
---@param e menuEnterEventData
function this:OnMenuEnter(e)
    if not InventoryMenuVisible() then
        return
    end
    self.inventoryMenuWasVisible = true
    self:RefreshSnapshot()
end

--- Refresh after MenuInventory becomes invisible, avoiding unrelated menu exits.
---@param e menuExitEventData
function this:OnMenuExit(e)
    if not self.inventoryMenuWasVisible or InventoryMenuVisible() then
        return
    end
    self.inventoryMenuWasVisible = false
    self:RefreshSnapshot()
end

--- Register inventory-specific event callbacks alongside the standard loaded callback.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if not self.barterOfferCallback then
        self.barterOfferCallback = function(e) self:OnBarterOffer(e) end
        event.register(tes3.event.barterOffer, self.barterOfferCallback)
        self.logger:debug("Memory inventory barterOffer handler registered")
    end
    if not self.uiActivatedCallback then
        self.uiActivatedCallback = function(e) self:OnInventoryUiActivated(e) end
        event.register(tes3.event.uiActivated, self.uiActivatedCallback)
        self.logger:debug("Memory inventory uiActivated handler registered")
    end
    if not self.menuEnterCallback then
        self.menuEnterCallback = function(e) self:OnMenuEnter(e) end
        event.register(tes3.event.menuEnter, self.menuEnterCallback)
        self.logger:debug("Memory inventory menuEnter handler registered")
    end
    if not self.menuExitCallback then
        self.menuExitCallback = function(e) self:OnMenuExit(e) end
        event.register(tes3.event.menuExit, self.menuExitCallback)
        self.logger:debug("Memory inventory menuExit handler registered")
    end
end

--- Unregister inventory-specific callbacks before releasing the standard loaded callback.
function this:UnregisterEvent()
    if self.menuExitCallback then
        event.unregister(tes3.event.menuExit, self.menuExitCallback)
        self.menuExitCallback = nil
        self.logger:debug("Memory inventory menuExit handler unregistered")
    end
    if self.menuEnterCallback then
        event.unregister(tes3.event.menuEnter, self.menuEnterCallback)
        self.menuEnterCallback = nil
        self.logger:debug("Memory inventory menuEnter handler unregistered")
    end
    if self.uiActivatedCallback then
        event.unregister(tes3.event.uiActivated, self.uiActivatedCallback)
        self.uiActivatedCallback = nil
        self.logger:debug("Memory inventory uiActivated handler unregistered")
    end
    if self.barterOfferCallback then
        event.unregister(tes3.event.barterOffer, self.barterOfferCallback)
        self.barterOfferCallback = nil
        self.logger:debug("Memory inventory barterOffer handler unregistered")
    end
    base.UnregisterEvent(self)
end

--- Synchronize UI state and capture a full snapshot before publishing after a loaded-game transition.
---@param e loadedEventData
function this:OnLoaded(e)
    self.inventoryMenuWasVisible = InventoryMenuVisible()
    self:RefreshSnapshot()
    base.OnLoaded(self, e)
end

--- Build the serialized inventory collection from the runtime snapshot.
---@return MCP.MemoryDocument
function this:BuildInventoryDocument()
    -- TODO it seems to on-demand reflesh on document build better than event driven snapshot.
    -- event just notification.

    local items = jsonrpc.array()
    for _, stack in ipairs(self.snapshot) do
        table.insert(items, jsonrpc.object({
            item = stack.item,
            itemData = stack.itemData,
            count = stack.count,
        }))
    end
    local data = jsonrpc.object({
        -- available = self.snapshotAvailable, -- need?
        -- is_current = self.snapshotCurrent, -- need?
        gold = self.gold,
        item_count = table.size(items),
        items = items,
    })
    local subjectType = document.SubjectTypeFromObject(tes3.player)
    return document.Document(
        document.documentType.collection,
        document.dataType.inventoryItems,
        descriptor.title,
        data,
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player inventory snapshot."),
        }
    )
end

return this
