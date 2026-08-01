local logger = require("morrowind-mcp.logger").Get({ moduleName = "target" })

-- Keep a short interaction history without retaining unbounded game objects.
local historyLimit = 8
local maxHoverAncestors = 8

-- Property keys used by vanilla UI to expose game data.
local PROP_MAGIC_SPELL = "MagicMenu_Spell"
local PROP_MAGIC_OBJECT = "MagicMenu_object"
local PROP_STAT_ATTRIBUTE = "MenuStat_attribute_strength"
local PROP_STAT_MESSAGE = "MenuStat_message"
local PROP_CONTENTS_REF = "MenuContents_ObjectRefr"
local PROP_CONTENTS_CONTAINER = "MenuContents_ObjectContainer"
local PROP_DIALOG_DIALOGUE = "PartHyperText_dialog"
local PROP_DIALOG_ACTOR = "PartHyperText_actor"
local PROP_ALCHEMY_OBJECT = "MenuAlchemy_object"
local PROP_INV_SELECT_OBJECT = "MenuInventorySelect_object"

-- Records interaction history without retaining tes3uiElement instances.
-- https://mwse.github.io/MWSE/guides/object-lifetimes/
local this = {}

---@class MCP.Target.CrosshairHistoryEntry
---@field referenceId string Immutable ID captured while the reference was valid.
---@field reference mwseSafeObjectHandle Safe handle; may no longer resolve when read.

---@class MCP.Target.HoverHistoryEntry
---@field spell tes3spell?
---@field magicObject tes3object?
---@field attributeId integer?
---@field skillId integer?
---@field faction tes3faction?
---@field contentsRefId string? Immutable ID captured while the reference was valid.
---@field contentsRef mwseSafeObjectHandle? Safe handle; may no longer resolve when read.
---@field contentsContainer tes3object?
---@field dialogue tes3dialogue?
---@field dialogActorRefId string? Immutable ID captured while the actor was valid.
---@field dialogActorRef mwseSafeObjectHandle? Safe handle; may no longer resolve when read.
---@field alchemyObject tes3object?
---@field inventorySelectObject tes3object?

---@class MCP.Target.History
---@field crosshair MCP.Target.CrosshairHistoryEntry[]
---@field hover MCP.Target.HoverHistoryEntry[]

---@type MCP.Target.History
this.history = {
    crosshair = {},
    hover = {},
}

---@param element tes3uiElement?
---@param property string
---@param typeCast string?
---@return any?
local function SafeGetPropertyObject(element, property, typeCast)
    if not element then
        return nil
    end
    local ok, value = pcall(function()
        if typeCast then
            return element:getPropertyObject(property, typeCast)
        end
        return element:getPropertyObject(property)
    end)
    if ok then
        return value
    end
    return nil
end

---Resolves a reference only while the safe handle remains valid.
---@param handle mwseSafeObjectHandle?
---@return tes3reference?
local function TryGetReference(handle)
    if handle and handle:valid() then
        local object = handle:getObject()
        if object and object.objectType == tes3.objectType.reference then
            return object --[[@as tes3reference]]
        end
    end
    return nil
end

---Creates a safe handle so history entries do not retain a volatile reference directly.
---@param reference tes3reference?
---@return mwseSafeObjectHandle?
local function MakeReferenceHandle(reference)
    if reference and reference:isValid() then
        return tes3.makeSafeObjectHandle(reference)
    end
    return nil
end

---Creates a safe reference handle for an actor whose mobile may expire after a cell unload.
---@param mobile tes3mobileActor?
---@return mwseSafeObjectHandle?
local function MakeReferenceHandleFromMobile(mobile)
    if not mobile then
        return nil
    end
    return MakeReferenceHandle(mobile.reference)
end

---Collects the element and a bounded number of its ancestors for vanilla property probing.
---@param start tes3uiElement
---@return tes3uiElement[]
local function CollectAncestors(start)
    local elements = {}
    local current = start
    local depth = 0
    while current and current:isValid() and depth < maxHoverAncestors do
        table.insert(elements, current)
        current = current.parent
        depth = depth + 1
    end
    return elements
end

---Adds a distinct history entry and evicts the oldest entry beyond the local limit.
---@param history table
---@param entry table
---@param signature string
---@param getSignature fun(value: table): string
---@return boolean appended
local function AppendHistory(history, entry, signature, getSignature)
    local previous = history[table.size(history)]
    if previous and getSignature(previous) == signature then
        return false
    end

    table.insert(history, entry)
    while table.size(history) > historyLimit do
        table.remove(history, 1)
    end
    return true
end

---@param entry MCP.Target.CrosshairHistoryEntry
---@return string
local function GetCrosshairSignature(entry)
    return entry.referenceId
end

---@param entry MCP.Target.HoverHistoryEntry
---@return string
local function GetHoverSignature(entry)
    local compact = {}
    local function AddPart(name, value)
        if value ~= nil then
            table.insert(compact, name .. ":" .. tostring(value))
        end
    end

    AddPart("spell", entry.spell and entry.spell.id or nil)
    AddPart("magicObject", entry.magicObject and entry.magicObject.id or nil)
    AddPart("attribute", entry.attributeId)
    AddPart("skill", entry.skillId)
    AddPart("faction", entry.faction and entry.faction.id or nil)
    AddPart("contentsRef", entry.contentsRefId)
    AddPart("contentsContainer", entry.contentsContainer and entry.contentsContainer.id or nil)
    AddPart("dialogue", entry.dialogue and entry.dialogue.id or nil)
    AddPart("dialogActorRef", entry.dialogActorRefId)
    AddPart("alchemyObject", entry.alchemyObject and entry.alchemyObject.id or nil)
    AddPart("inventorySelectObject", entry.inventorySelectObject and entry.inventorySelectObject.id or nil)
    return table.concat(compact, "\31")
end

---@param entry MCP.Target.HoverHistoryEntry
---@param element tes3uiElement
local function ProbeElementProperties(entry, element)
    if not entry.spell then
        entry.spell = SafeGetPropertyObject(element, PROP_MAGIC_SPELL, "tes3spell")
    end

    if not entry.magicObject then
        entry.magicObject = SafeGetPropertyObject(element, PROP_MAGIC_OBJECT)
    end

    if entry.attributeId == nil then
        local name = element.name or ""
        local parentName = element.parent and element.parent.name or ""
        if name:find("MenuStat_attribute", 1, true) or parentName:find("MenuStat_attribute", 1, true) then
            entry.attributeId = element:getPropertyInt(PROP_STAT_ATTRIBUTE)
        end
    end

    if entry.skillId == nil and not entry.faction then
        entry.faction = SafeGetPropertyObject(element, PROP_STAT_MESSAGE, "tes3faction")
        if not entry.faction then
            local name = element.name or ""
            local parentName = element.parent and element.parent.name or ""
            local isSkill = name:find("major", 1, true) or name:find("minor", 1, true) or name:find("misc", 1, true)
                or parentName:find("major", 1, true) or parentName:find("minor", 1, true)
                or parentName:find("misc", 1, true)
            if (name:find("MenuStat_", 1, true) or parentName:find("MenuStat_", 1, true)) and isSkill then
                entry.skillId = element:getPropertyInt(PROP_STAT_MESSAGE)
            end
        end
    end

    if not entry.contentsRef then
        local contentsRef = SafeGetPropertyObject(element, PROP_CONTENTS_REF, "tes3reference") ---@type tes3reference?
        entry.contentsRef = MakeReferenceHandle(contentsRef)
        entry.contentsRefId = contentsRef and contentsRef.id or nil
    end

    if not entry.contentsContainer then
        entry.contentsContainer = SafeGetPropertyObject(element, PROP_CONTENTS_CONTAINER)
    end

    if not entry.dialogue then
        entry.dialogue = SafeGetPropertyObject(element, PROP_DIALOG_DIALOGUE, "tes3dialogue")
    end

    if not entry.dialogActorRef then
        local dialogActor = SafeGetPropertyObject(element, PROP_DIALOG_ACTOR, "tes3mobileActor") ---@type tes3mobileActor?
        entry.dialogActorRef = MakeReferenceHandleFromMobile(dialogActor)
        entry.dialogActorRefId = dialogActor and dialogActor.reference and dialogActor.reference.id or nil
    end

    if not entry.alchemyObject then
        entry.alchemyObject = SafeGetPropertyObject(element, PROP_ALCHEMY_OBJECT)
    end

    if not entry.inventorySelectObject then
        entry.inventorySelectObject = SafeGetPropertyObject(element, PROP_INV_SELECT_OBJECT)
    end
end

---Builds a game-data-only hover record, or nil when the UI exposes no targetable game data.
---@param element tes3uiElement
---@return MCP.Target.HoverHistoryEntry?
local function TryBuildHoverEntry(element)
    ---@type MCP.Target.HoverHistoryEntry
    local entry = {}
    for _, ancestor in ipairs(CollectAncestors(element)) do
        ProbeElementProperties(entry, ancestor)
    end

    if GetHoverSignature(entry) == "" then
        return nil
    end
    return entry
end

---Copies an array so callers cannot accidentally mutate module history.
---@param source table
---@return table
local function CopyHistory(source)
    local copy = {}
    for index, entry in ipairs(source) do
        copy[index] = entry
    end
    return copy
end

---Clears recorded interaction history after a game load.
---@param e loadedEventData
local function LoadedCallback(e)
    this.ClearHistory()
end

---Records each distinct valid activation target as a crosshair history entry.
---@param e activationTargetChangedEventData
local function ActivationTargetChangedCallback(e)
    if not e.current or not e.current:isValid() then
        return
    end

    local reference = MakeReferenceHandle(e.current)
    if not reference then
        return
    end

    local entry = {
        referenceId = e.current.id,
        reference = reference,
    }
    if AppendHistory(this.history.crosshair, entry, GetCrosshairSignature(entry), GetCrosshairSignature) then
        logger:trace("Crosshair history recorded: %s (%d/%d)", entry.referenceId, table.size(this.history.crosshair), historyLimit)
    end
end

---Samples vanilla UI properties and records only distinct game-domain hover data.
---@param e enterFrameEventData
local function EnterFrameCallback(e)
    local worldController = tes3.worldController
    local menuController = worldController and worldController.menuController
    local inputController = menuController and menuController.inputController
    local element = inputController and inputController.pointerMoveEventSource
    if not element or not element:isValid() then
        return
    end

    local entry = TryBuildHoverEntry(element)
    if entry then
        local signature = GetHoverSignature(entry)
        if AppendHistory(this.history.hover, entry, signature, GetHoverSignature) then
            logger:trace("Hover history recorded: %s (%d/%d)", signature:gsub("\31", ", "), table.size(this.history.hover), historyLimit)
        end
    end
end

---Returns a copy of the crosshair history. Stored handles may have expired.
---@return MCP.Target.CrosshairHistoryEntry[]
function this.GetCrosshairHistory()
    return CopyHistory(this.history.crosshair)
end

---Returns a copy of the game-data hover history. Stored handles may have expired.
---@return MCP.Target.HoverHistoryEntry[]
function this.GetHoverHistory()
    return CopyHistory(this.history.hover)
end

---Returns the latest crosshair reference while its safe handle is still valid.
---@return tes3reference?
function this.TryGetLastCrosshairTarget()
    local entry = this.history.crosshair[table.size(this.history.crosshair)]
    return entry and TryGetReference(entry.reference) or nil
end

---Returns the latest hovered contents reference while its safe handle is still valid.
---@return tes3reference?
function this.TryGetLastHoverContentsRef()
    local entry = this.history.hover[table.size(this.history.hover)]
    return entry and TryGetReference(entry.contentsRef) or nil
end

---Returns the latest hovered dialogue actor reference while its safe handle is still valid.
---@return tes3reference?
function this.TryGetLastHoverDialogActorRef()
    local entry = this.history.hover[table.size(this.history.hover)]
    return entry and TryGetReference(entry.dialogActorRef) or nil
end

---Returns the latest hovered dialogue actor while its reference and mobile are still valid.
---@return tes3mobileActor?
function this.TryGetLastHoverDialogActor()
    local reference = this.TryGetLastHoverDialogActorRef()
    return reference and reference.mobile or nil
end

---Clears both histories without changing event registration.
function this.ClearHistory()
    this.history.crosshair = {}
    this.history.hover = {}
end

---Registers the events required to collect target interaction history.
function this.RegisterEvent()
    local priority = 100
    event.register(tes3.event.loaded, LoadedCallback, { priority = priority })
    event.register(tes3.event.activationTargetChanged, ActivationTargetChangedCallback, { priority = priority })
    event.register(tes3.event.enterFrame, EnterFrameCallback, { priority = priority })
end

---Unregisters the events used to collect target interaction history.
function this.UnregisterEvent()
    event.unregister(tes3.event.loaded, LoadedCallback)
    event.unregister(tes3.event.activationTargetChanged, ActivationTargetChangedCallback)
    event.unregister(tes3.event.enterFrame, EnterFrameCallback)
end

return this
