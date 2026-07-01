local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local config = require("morrowind-mcp.config")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "serializer" })

local this = {}

-- serialzie tes3 various objects for json serialization.

-- default __tojson(self) just put id such as "tes3baseObject:DoorMarker".
-- so we need to implement our own serialization function for tes3object and tes3reference... and more.
-- but I consider if __tojson(self) overrides, other mods possible unexpected behavior, so I implement a new functions.
-- also we don't need all field for AI. hand picking?


---@param i MCP.AnyMap?
---@return boolean
local function ValidateType(i)
    if not config.development.debug then
        return true
    end

    if i == nil then
        return true
    end

    local t = type(i)
    if t == "userdata" or t == "function" or t == "thread" then
        return false
    end

    if t == "table" then
        for k, v in pairs(i) do
            if not ValidateType(v) then
                logger:error("Invalid value in table: %s=%s", k, type(v))
                return false
            end
        end
    end

    return true
end
local _objectTypeName = nil ---@type table<tes3.objectType, string>

---@param objectType tes3.objectType
---@return string
local function objectTypeToString(objectType)
    if not _objectTypeName then
        _objectTypeName = {}
        for k, v in pairs(tes3.objectType) do
            _objectTypeName[v] = k
        end
    end
    if objectType == nil then
        return nil
    end
    return _objectTypeName[objectType]
end

local fontName = {
    "magic_cards_regular",         -- Magic Cards, default
    "century_gothic_font_regular", -- Century Sans
    "daedric_font",
}

---@param i tes3uiElement?
---@return MCP.AnyMap?
local function _tes3uiElement(i)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end

    -- same as human visibility
    if not i.visible then
        return nil
    end

    local o = jsonrpc.object({
        -- absolutePosAlignX = i.absolutePosAlignX,
        -- absolutePosAlignY = i.absolutePosAlignY,
        -- alpha = i.alpha,
        -- autoHeight = i.autoHeight,
        -- autoWidth = i.autoWidth,
        -- borderAllSides = i.borderAllSides,
        -- borderBottom = i.borderBottom,
        -- borderLeft = i.borderLeft,
        -- borderRight = i.borderRight,
        -- borderTop = i.borderTop,
        -- childAlignX = i.childAlignX,
        -- childAlignY = i.childAlignY,
        -- childOffsetX = i.childOffsetX,
        -- childOffsetY = i.childOffsetY,
        -- children = jsonrpc.array(table.size(i.children)), -- later
        -- color = i.color,
        consumeMouseEvents = i.consumeMouseEvents,
        contentPath = i.contentPath,
        contentType = i.contentType,
        disabled = i.disabled,
        -- flowDirection = i.flowDirection,
        font = fontName[i.font],
        -- height = i.height,
        -- heightProportional = i.heightProportional,
        id = i.id,
        -- ignoreLayoutX = i.ignoreLayoutX,
        -- ignoreLayoutY = i.ignoreLayoutY,
        -- imageFilter = i.imageFilter,
        -- imageScaleX = i.imageScaleX,
        -- imageScaleY = i.imageScaleY,
        -- justifyText = i.justifyText,
        -- maxHeight = i.maxHeight,
        -- maxWidth = i.maxWidth,
        -- minHeight = i.minHeight,
        -- minWidth = i.minWidth,
        name = i.name,
        -- paddingAllSides = i.paddingAllSides,
        -- paddingBottom = i.paddingBottom,
        -- paddingLeft = i.paddingLeft,
        -- paddingRight = i.paddingRight,
        -- paddingTop = i.paddingTop,
        -- parent = i.parent,
        -- positionX = i.positionX,
        -- positionY = i.positionY,
        rawText = i.rawText,
        repeatKeys = i.repeatKeys,
        -- scaleMode = i.scaleMode,
        -- sceneNode = i.sceneNode, -- need?
        text = i.text,
        -- texture = i.texture, -- need?
        type = i.type,
        -- visible = i.visible, -- if element is not terminated, it is needed to contain
        -- widget = ToJsonWidget(i.widget, i.type), -- need?
        -- width = i.width,
        -- widthProportional = i.widthProportional,
    })

    local children = jsonrpc.array(table.size(i.children))
    for _, child in ipairs(i.children) do
        local c = _tes3uiElement(child)
        if c then
            table.insert(children, c)
        end
    end
    if table.size(children) > 0 then
        o.children = children
    end

    if table.size(o) > 0 then
        return o
    end
    return nil
end

---@param o MCP.AnyMap
---@param i tes3baseObject
---@return MCP.AnyMap?
local function _tes3baseObject(o, i)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    o.blocked = i.blocked
    o.deleted = i.deleted
    o.disabled = i.disabled
    o.id = i.id
    o.modified = i.modified
    o.objectFlags = i.objectFlags
    o.objectType = objectTypeToString(i.objectType)
    o.persistent = i.persistent
    o.sourceless = i.sourceless
    o.sourceMod = i.sourceMod
    o.supportsActivate = i.supportsActivate
    return o
end

---@param o MCP.AnyMap
---@param i tes3object
---@return MCP.AnyMap?
local function _tes3object(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end
    o.isLocationMarker = i.isLocationMarker
    -- o.nextInCollection = i.nextInCollection
    -- o.owningCollection = i.owningCollection
    -- o.previousInCollection = i.previousInCollection
    o.scale = i.scale
    -- o.sceneCollisionRoot = i.sceneCollisionRoot
    -- o.sceneNode = i.sceneNode
    return o
end

---@param o MCP.AnyMap
---@param i tes3reference
---@return MCP.AnyMap?
local function _tes3reference(o, i)
    if not _tes3object(o, i) then
        return nil
    end
    --[[
    -- o.activationReference = i.activationReference
    -- o.animationData = i.animationData
    o.attachments = i.attachments
    o.baseObject = i.baseObject
    o.bodyPartManager = i.bodyPartManager
    o.cell = i.cell
    -- o.context = i.context
    o.data = i.data
    o.destination = i.destination
    o.facing = i.facing
    o.forwardDirection = i.forwardDirection
    o.hasNoCollision = i.hasNoCollision
    o.isDead = i.isDead
    o.isEmpty = i.isEmpty
    o.isLeveledSpawn = i.isLeveledSpawn
    o.isRespawn = i.isRespawn
    o.itemData = i.itemData
    o.leveledBaseReference = i.leveledBaseReference
    -- o.light = i.light
    o.lockNode = i.lockNode
    o.mesh = i.mesh
    o.mobile = i.mobile
    o.nextNode = i.nextNode
    o.nodeData = i.nodeData
    o.object = i.object
    o.orientation = i.orientation
    o.position = i.position
    o.previousNode = i.previousNode
    o.rightDirection = i.rightDirection
    -- o.sceneNode = i.sceneNode
    o.sourceFormId = i.sourceFormId
    o.sourceModId = i.sourceModId
    o.stackSize = i.stackSize
    o.startingOrientation = i.startingOrientation
    o.startingPosition = i.startingPosition
    o.supportsLuaData = i.supportsLuaData
    o.targetFormId = i.targetFormId
    o.targetModId = i.targetModId
    o.tempData = i.tempData
    --]]
    return o
end

---@param o MCP.AnyMap?
---@param i tes3dialogue
---@return MCP.AnyMap?
local function _tes3dialogue(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end

    -- need no serialize option or parent. avoid circular reference. info has dialogue, dialogue has info.

    o.journalIndex = i.journalIndex
    o.type = i.type -- TODO convert to string. tes3.dialogueType

    return o
end

---@param o MCP.AnyMap?
---@param i tes3dialogueInfo
---@return MCP.AnyMap?
local function _tes3dialogueInfo(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end
    -- o.actor = i.actor
    -- o.cell = i.cell
    o.disposition = i.disposition
    -- o.firstHeardFrom = i.firstHeardFrom
    o.isQuestFinished = i.isQuestFinished
    o.isQuestName = i.isQuestName
    o.isQuestRestart = i.isQuestRestart
    o.journalIndex = i.journalIndex
    -- o.npcClass = i.npcClass
    -- o.npcFaction = i.npcFaction
    -- o.npcRace = i.npcRace
    o.npcRank = i.npcRank
    o.npcSex = i.npcSex
    o.pcFaction = i.pcFaction
    o.pcRank = i.pcRank
    o.text = i.text
    o.type = i.type

    return o
end

---@param o MCP.AnyMap?
---@param i tes3quest
---@return MCP.AnyMap?
local function _tes3quest(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end

    -- TODO array and object iterate helper

    if i.dialogue then
        local dialogueArray = jsonrpc.array(table.size(i.dialogue))
        for _, dialogue in ipairs(i.dialogue) do
            local dialogueObject = jsonrpc.object()
            if _tes3dialogue(dialogueObject, dialogue) then
                table.insert(dialogueArray, dialogueObject)
            end
        end
        if table.size(dialogueArray) > 0 then
            o.dialogue = dialogueArray
        end
    end
    if i.info then
        local infoArray = jsonrpc.array(table.size(i.info))
        for _, info in ipairs(i.info) do
            local infoObject = jsonrpc.object()
            if _tes3dialogueInfo(infoObject, info) then
                table.insert(infoArray, infoObject)
            end
        end
        if table.size(infoArray) > 0 then
            o.info = infoArray
        end
    end
    o.isActive = i.isActive
    o.isFinished = i.isFinished
    o.isStarted = i.isStarted
    return o
end

---@param o MCP.AnyMap?
---@param i tes3mobileObject
---@return MCP.AnyMap?
local function _tes3mobileObject(o, i)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    return o
end

---@param o MCP.AnyMap?
---@param i tes3mobileActor
---@return MCP.AnyMap?
local function _tes3mobileActor(o, i)
    if not _tes3mobileObject(o, i) then
        return nil
    end
    -- o.boundSize = i.boundSize
    -- o.boundSize2D = i.boundSize2D
    o.cellX = i.cellX
    o.cellY = i.cellY
    -- o.dynamicLightingValid = i.dynamicLightingValid
    o.flags = i.flags
    o.height = i.height
    -- o.impulseVelocity = i.impulseVelocity
    -- o.inventory = i.inventory
    -- o.isAffectedByGravity = i.isAffectedByGravity
    -- o.lightEffectData = i.lightEffectData
    -- o.mobToMobCollision = i.mobToMobCollision
    -- o.movementCollision = i.movementCollision
    -- o.movementFlags = i.movementFlags
    o.objectType = objectTypeToString(i.objectType)
    o.playerDistance = i.playerDistance
    o.position = i.position
    -- o.prevMovementFlags = i.prevMovementFlags
    -- o.reference = i.reference
    o.velocity = i.velocity
    return o
end

---@param o MCP.AnyMap?
---@param i tes3mobileNPC
---@return MCP.AnyMap?
local function _tes3mobileNPC(o, i)
    if not _tes3mobileActor(o, i) then
        return nil
    end
    return o
end

---@param o MCP.AnyMap?
---@param i tes3mobilePlayer
---@return MCP.AnyMap?
local function _tes3mobilePlayer(o, i)
    if not _tes3mobileNPC(o, i) then
        return nil
    end
    return o
end

---@param o MCP.AnyMap?
---@param i tes3worldController
---@return MCP.AnyMap?
local function _tes3worldController(o, i)
    if not i then
        return nil
    end

    return o
end

---@param i tes3uiElement
---@return MCP.AnyMap?
function this.tes3uiElement(i)
    local o = _tes3uiElement(i)
    local _ = ValidateType(o)
    return o
end

---@param i tes3reference
---@return MCP.AnyMap?
function this.tes3reference(i)
    local o = jsonrpc.object()
    local _ = ValidateType(_tes3reference(o, i))
    return o
end

---@param i tes3quest
---@return MCP.AnyMap?
function this.tes3quest(i)
    local o = jsonrpc.object()
    local _ = ValidateType(_tes3quest(o, i))
    return o
end

---@param i tes3mobilePlayer
---@return MCP.AnyMap?
function this.tes3mobilePlayer(i)
    local o = jsonrpc.object()
    local _ = ValidateType(_tes3mobilePlayer(o, i))
    return o
end

---@param i tes3worldController
---@return MCP.AnyMap?
function this.tes3worldController(i)
    local o = jsonrpc.object()
    local _ = ValidateType(_tes3worldController(o, i))
    return o
end

--- TODO move to other helper
---@param list tes3referenceList
---@return fun(): tes3reference
function this.ForEachReferenceList(list)
    local function iterator()
        local ref = list.head

        if list.size ~= 0 then
            coroutine.yield(ref)
        end

        while ref.nextNode do
            ref = ref.nextNode
            coroutine.yield(ref)
        end
    end
    return coroutine.wrap(iterator)
end

return this
