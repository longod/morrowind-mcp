local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local enumname = require("morrowind-mcp.tes3.enumname")
local player = require("morrowind-mcp.resources.memory.player")

--- Memory module for the current player's castable spells and powers.
---@class MCP.Resources.Memory.Spellbook: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field charGenFinishedCallback fun(e: charGenFinishedEventData)?
---@field spellCreatedCallback fun(e: spellCreatedEventData)?
---@field spellCastedCallback fun(e: spellCastedEventData)?
---@field powerRechargedCallback fun(e: powerRechargedEventData)?
---@field magicMenuActivatedCallback fun(e: uiActivatedEventData)?
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/player/spellbook.json",
    "Player Spellbook Memory",
    "Current player spells and powers."
)

local spellbookLink = document.Link(
    document.linkRel.spellbook,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

--- Read a TES3 field without allowing unavailable game state to break a Memory response.
---@param callback fun(): any
---@return any
local function ReadValue(callback)
    local ok, result = pcall(callback)
    if ok then
        return result
    end
    return nil
end

--- Serialize one magic effect used by a spell without retaining MWSE userdata.
---@param effect tes3effect?
---@return MCP.AnyMap?
local function SerializeEffect(effect)
    if not effect or (type(effect.id) == "number" and effect.id < 0) then
        return nil
    end
    return jsonrpc.object({
        attribute = enumname.attribute(effect.attribute),
        duration = effect.duration,
        id = enumname.effect(effect.id) or effect.id,
        max = effect.max,
        min = effect.min,
        radius = effect.radius,
        rangeType = enumname.effectRange(effect.rangeType),
        skill = enumname.skill(effect.skill),
    })
end

--- Serialize any TES3 spell definition so other Memory modules can later reuse the stable shape.
---@param spell tes3spell?
---@return MCP.MemorySpell?
function this.SerializeSpell(spell)
    if not spell or (spell.isValid and not spell:isValid()) or spell.deleted or spell.disabled then
        return nil
    end
    local effects = jsonrpc.array()
    for _, effect in ipairs(spell.effects or {}) do
        local serializedEffect = SerializeEffect(effect)
        if serializedEffect then
            table.insert(effects, serializedEffect)
        end
    end
    return jsonrpc.object({
        id = spell.id,
        name = spell.name,
        castType = enumname.spellType(spell.castType),
        magickaCost = spell.magickaCost,
        effects = effects,
    })
end

--- Create the player-child spellbook module and its live resource entry.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Spellbook
function this.new(params)
    params.publishOnLoaded = true
    params.parentUri = player.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_spellbook" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Spellbook
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ spellbookLink })
    return instance
end

--- Return whether the player spell list is currently readable.
---@return boolean
local function IsAvailable()
    return ReadValue(function() return tes3.onMainMenu() end) ~= true
        and ReadValue(function() return tes3.player end) ~= nil
        and ReadValue(function() return tes3.mobilePlayer end) ~= nil
end

--- Read one cast type from the player list, preserving MWSE's display order.
---@param spellType tes3.spellType
---@return tes3spell[]
local function ReadSpells(spellType)
    if not IsAvailable() then
        return {}
    end
    return ReadValue(function()
        return tes3.getSpells({ target = tes3.player, spellType = spellType })
    end) or {}
end

--- Build the current player spellbook from MWSE's aggregate player spell API.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local spells = jsonrpc.array()
    local powers = jsonrpc.array()
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    for _, spell in ipairs(ReadSpells(tes3.spellType.spell)) do
        local serializedSpell = this.SerializeSpell(spell)
        if serializedSpell then
            table.insert(spells, serializedSpell)
        end
    end
    for _, power in ipairs(ReadSpells(tes3.spellType.power)) do
        local serializedPower = this.SerializeSpell(power)
        if serializedPower then
            ---@cast serializedPower MCP.MemoryPower
            local used = ReadValue(function() return mobilePlayer:hasUsedPower(power) end) == true
            serializedPower.used = used
            serializedPower.available = not used
            table.insert(powers, serializedPower)
        end
    end
    local subjectType = document.SubjectTypeFromObject(ReadValue(function() return tes3.player end))
    return document.Document(
        document.documentType.collection,
        document.dataType.playerSpellbook,
        descriptor.title,
        jsonrpc.object({
            available = IsAvailable(),
            spell_count = table.size(spells),
            power_count = table.size(powers),
            spells = spells,
            powers = powers,
        }),
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player spells and powers read on demand."),
        }
    )
end

--- Invalidate a clean published spellbook once per mutation burst.
---@param reason string
function this:InvalidateSpellbook(reason)
    if not self.published or self.entry.cache.dirty then
        return
    end
    self.logger:debug("Memory spellbook invalidated: reason=%s", reason)
    self:Publish()
end

--- Refresh after character generation finalizes the player's class, race, and birthsign spells.
function this:OnCharGenFinished()
    self:InvalidateSpellbook("character_generation_finished")
end

--- Refresh after spellmaking or script creation may have changed the current spell list.
---@param e spellCreatedEventData?
function this:OnSpellCreated(e)
    self:InvalidateSpellbook("spell_created")
end

--- Refresh when a player power is successfully cast and enters its recharge period.
---@param e spellCastedEventData?
function this:OnSpellCasted(e)
    if e and e.caster == tes3.player and e.source and e.source.castType == tes3.spellType.power then
        self:InvalidateSpellbook("power_casted")
    end
end

--- Refresh when one of the player's powers becomes available after recharging.
---@param e powerRechargedEventData?
function this:OnPowerRecharged(e)
    if e and (e.reference == tes3.player or e.mobile == tes3.mobilePlayer) then
        self:InvalidateSpellbook("power_recharged")
    end
end

--- Use the completed magic selector as the eventual-consistency boundary for purchases and mod changes.
---@param e uiActivatedEventData?
function this:OnMagicMenuActivated(e)
    self:InvalidateSpellbook("magic_menu_activated")
end

--- Register player spellbook invalidators together with the standard loaded callback.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.charGenFinishedCallback then
        return
    end
    self.charGenFinishedCallback = function(e) self:OnCharGenFinished() end
    self.spellCreatedCallback = function(e) self:OnSpellCreated(e) end
    self.spellCastedCallback = function(e) self:OnSpellCasted(e) end
    self.powerRechargedCallback = function(e) self:OnPowerRecharged(e) end
    self.magicMenuActivatedCallback = function(e) self:OnMagicMenuActivated(e) end
    event.register(tes3.event.charGenFinished, self.charGenFinishedCallback)
    event.register(tes3.event.spellCreated, self.spellCreatedCallback)
    event.register(tes3.event.spellCasted, self.spellCastedCallback)
    event.register(tes3.event.powerRecharged, self.powerRechargedCallback)
    event.register(tes3.event.uiActivated, self.magicMenuActivatedCallback, { filter = "MenuMagic" })
end

--- Unregister Player spellbook event callbacks before releasing the module.
function this:UnregisterEvent()
    local callbacks = {
        { tes3.event.charGenFinished, "charGenFinishedCallback" },
        { tes3.event.spellCreated, "spellCreatedCallback" },
        { tes3.event.spellCasted, "spellCastedCallback" },
        { tes3.event.powerRecharged, "powerRechargedCallback" },
        { tes3.event.uiActivated, "magicMenuActivatedCallback" },
    }
    for _, item in ipairs(callbacks) do
        local callback = self[item[2]]
        if callback then
            event.unregister(item[1], callback)
            self[item[2]] = nil
        end
    end
    base.UnregisterEvent(self)
end

return this