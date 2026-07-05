local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local config = require("morrowind-mcp.config")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "serializer" })
local enumname = require("morrowind-mcp.enumname")

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


local fontName = {
    "magic_cards_regular",         -- Magic Cards, default
    "century_gothic_font_regular", -- Century Sans
    "daedric_font",
}

local npcSexName = {
    [0] = "male",
    [1] = "female",
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
        contentType = enumname.contentType(i.contentType),
        disabled = i.disabled,
        -- flowDirection = enumname.flowDirection(i.flowDirection),
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
        type = enumname.uiElementType(i.type),
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
---@param i tes3fader
---@return MCP.AnyMap?
local function _tes3fader(o, i)
    o.active = i.active
    return o
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
    -- o.objectFlags = i.objectFlags -- TODO means flags
    o.objectType = enumname.objectType(i.objectType)
    o.persistent = i.persistent
    o.sourceless = i.sourceless
    o.sourceMod = i.sourceMod
    o.supportsActivate = i.supportsActivate
    return o
end

--- just returns value is better?
---@param o MCP.AnyMap
---@param i tes3globalVariable
---@return MCP.AnyMap?
local function _tes3globalVariable(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end
    o.value = i.value
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
---@param i tes3effect
---@return MCP.AnyMap?
local function _tes3effect(o, i)
    o.attribute = enumname.attribute(i.attribute)
    o.cost = i.cost
    o.duration = i.duration
    o.id = enumname.effect(i.id) or i.id -- possible modding extend id, its out of range (nil)
    o.max = i.max
    o.min = i.min
    o.object = i.object
    o.radius = i.radius
    o.rangeType = enumname.effectRange(i.rangeType)
    o.skill = enumname.skill(i.skill)
    return o
end


---@param o MCP.AnyMap
---@param i tes3spell
---@return MCP.AnyMap?
local function _tes3spell(o, i)
    if not _tes3object(o, i) then
        return nil
    end
    o.alwaysSucceeds = i.alwaysSucceeds
    o.autoCalc = i.autoCalc
    o.basePurchaseCost = i.basePurchaseCost
    o.castType = enumname.spellType(i.castType)
    if i.effects and table.size(i.effects) > 0 then
        local effects = jsonrpc.array(table.size(i.effects))
        for _, effect in ipairs(i.effects) do
            -- no nil return
            table.insert(effects, _tes3effect(jsonrpc.object(), effect))
        end
        o.effects = effects
    end
    -- o.flags = i.flags -- TODO means flags
    o.isAbility = i.isAbility
    o.isActiveCast = i.isActiveCast
    o.isBlightDisease = i.isBlightDisease
    o.isCommonDisease = i.isCommonDisease
    o.isCorprusDisease = i.isCorprusDisease
    o.isCurse = i.isCurse
    o.isDisease = i.isDisease
    o.isPower = i.isPower
    o.isSpell = i.isSpell
    o.magickaCost = i.magickaCost
    o.name = i.name
    o.playerStart = i.playerStart
    o.value = i.value
    return o
end

---@param o MCP.AnyMap
---@param i tes3birthsign
---@return MCP.AnyMap?
local function _tes3birthsign(o, i)
    if not _tes3baseObject(o, i) then
        return nil
    end
    o.description = i.description
    o.name = i.name
    o.spells = _tes3spell(jsonrpc.object(), i.spells)
    -- o.texturePath = i.texturePath
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
    o.type = enumname.dialogueType(i.type)

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
    o.npcSex = npcSexName[i.npcSex] or i.npcSex
    o.pcFaction = i.pcFaction
    o.pcRank = i.pcRank
    o.text = i.text
    o.type = enumname.dialogueType(i.type)

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
    -- o.flags = i.flags -- TODO means flags
    o.height = i.height
    -- o.impulseVelocity = i.impulseVelocity
    -- o.inventory = i.inventory
    -- o.isAffectedByGravity = i.isAffectedByGravity
    -- o.lightEffectData = i.lightEffectData
    -- o.mobToMobCollision = i.mobToMobCollision
    -- o.movementCollision = i.movementCollision
    -- o.movementFlags = i.movementFlags -- TODO means flags
    o.objectType = enumname.objectType(i.objectType)
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
---@param i tes3bountyData
---@return MCP.AnyMap?
local function _tes3bountyData(o, i)
    if not i then
        return nil
    end
    if table.size(i) == 0 then
        return nil
    end
    for _, key in ipairs(i.keys) do
        if key then
            local value  = i:getValue(key)
            o[key] = value
        end
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
    o.alwaysRun = i.alwaysRun
    -- o.animationController = i.animationController
    o.attackDisabled = i.attackDisabled
    o.autoRun = i.autoRun
    o.birthsign = _tes3birthsign(jsonrpc.object(), i.birthsign)
    o.bounty = i.bounty
    o.bountyData = _tes3bountyData(jsonrpc.object(), i.bountyData)
    -- o.cameraHeight = i.cameraHeight
    o.castReady = i.castReady
    o.clawMultiplier = _tes3globalVariable(jsonrpc.object(), i.clawMultiplier)
    o.controlsDisabled = i.controlsDisabled

    if i.dialogueList then
        local dialogueArray = jsonrpc.array(table.size(i.dialogueList))
        for _, dialogue in ipairs(i.dialogueList) do
            local dialogueObject = jsonrpc.object()
            if _tes3dialogue(dialogueObject, dialogue) then
                table.insert(dialogueArray, dialogueObject)
            end
        end
        if table.size(dialogueArray) > 0 then
            o.dialogueList = dialogueArray
        end
    end

    -- o.firstPerson = i.firstPerson
    -- o.firstPersonReference = i.firstPersonReference
    o.inactivityTime = i.inactivityTime
    o.inJail = i.inJail
    o.is3rdPerson = i.is3rdPerson
    o.jumpingDisabled = i.jumpingDisabled
    o.knownWerewolf = _tes3globalVariable(jsonrpc.object(), i.knownWerewolf)
    o.lastUsedAlembic = i.lastUsedAlembic -- TODO
    o.lastUsedAmmoCount = i.lastUsedAmmoCount
    o.lastUsedCalcinator = i.lastUsedCalcinator -- TODO
    o.lastUsedMortar = i.lastUsedMortar -- TODO
    o.lastUsedRetort = i.lastUsedRetort -- TODO
    o.levelupPerSpecialization = jsonrpc.array(i.levelupPerSpecialization)
    o.levelUpProgress = i.levelUpProgress
    o.levelupsPerAttribute = jsonrpc.array(i.levelupsPerAttribute)
    o.magicDisabled = i.magicDisabled
    o.markLocation = i.markLocation -- TODO
    o.mouseLookDisabled = i.mouseLookDisabled
    o.restHoursRemaining = i.restHoursRemaining
    o.skillProgress = jsonrpc.array(i.skillProgress)
    o.sleeping = i.sleeping
    o.telekinesis = i.telekinesis
    o.traveling = i.traveling
    o.vanityDisabled = i.vanityDisabled
    o.viewSwitchDisabled = i.viewSwitchDisabled
    o.visionBonus = i.visionBonus
    o.waiting = i.waiting
    o.weaponReady = i.weaponReady
    return o
end

--- TODO inheritance types: tes3weatherAsh|tes3weatherBlight|tes3weatherBlizzard|tes3weatherClear|tes3weatherCloudy|tes3weatherFoggy|tes3weatherOvercast|tes3weatherRain|tes3weatherSnow|tes3weatherThunder
--- but not important, because  thet contain some filed for less needed for AI.
---@param o MCP.AnyMap?
---@param i tes3weather
---@return MCP.AnyMap?
local function _tes3weather(o, i)
    if not i then
        return nil
    end
    o.ambientDayColor = i.ambientDayColor
    -- o.ambientLoopSound = i.ambientLoopSound
    -- o.ambientLoopSoundId = i.ambientLoopSoundId
    o.ambientNightColor = i.ambientNightColor
    -- o.ambientPlaying = i.ambientPlaying
    o.ambientSunriseColor = i.ambientSunriseColor
    o.ambientSunsetColor = i.ambientSunsetColor
    o.cloudsMaxPercent = i.cloudsMaxPercent
    o.cloudsSpeed = i.cloudsSpeed
    -- o.cloudTexture = i.cloudTexture
    -- o.controller = i.controller -- TODO avoid circular reference
    -- o.fogDayColor = i.fogDayColor
    -- o.fogNightColor = i.fogNightColor
    -- o.fogSunriseColor = i.fogSunriseColor
    -- o.fogSunsetColor = i.fogSunsetColor
    o.glareView = i.glareView
    o.index = enumname.weather(i.index)
    o.landFogDayDepth = i.landFogDayDepth
    o.landFogNightDepth = i.landFogNightDepth
    o.name = i.name
    -- o.skyDayColor = i.skyDayColor
    -- o.skyNightColor = i.skyNightColor
    -- o.skySunriseColor = i.skySunriseColor
    -- o.skySunsetColor = i.skySunsetColor
    o.sunDayColor = i.sunDayColor
    o.sundiscSunsetColor = i.sundiscSunsetColor
    o.sunNightColor = i.sunNightColor
    o.sunSunriseColor = i.sunSunriseColor
    o.sunSunsetColor = i.sunSunsetColor
    -- o.transitionDelta = i.transitionDelta
    -- o.underwaterSoundState = i.underwaterSoundState
    o.windSpeed = i.windSpeed
    return o
end

---@param o MCP.AnyMap?
---@param i tes3weatherController
---@return MCP.AnyMap?
local function _tes3weatherController(o, i)
    if not i then
        return nil
    end
    -- TODO need to calculate current ambient color?
    -- TODO need to calculate current sun direction and color?

    o.ambientPostSunriseTime = i.ambientPostSunriseTime
    o.ambientPostSunsetTime = i.ambientPostSunsetTime
    o.ambientPreSunriseTime = i.ambientPreSunriseTime
    o.ambientPreSunsetTime = i.ambientPreSunsetTime
    o.currentFogColor = i.currentFogColor
    o.currentSkyColor = i.currentSkyColor
    o.currentWeather = _tes3weather(jsonrpc.object(), i.currentWeather)
    o.daysRemaining = i.daysRemaining
    -- o.fogDepthChangeSpeed = i.fogDepthChangeSpeed
    -- o.fogPostSunriseTime = i.fogPostSunriseTime
    -- o.fogPostSunsetTime = i.fogPostSunsetTime
    -- o.fogPreSunriseTime = i.fogPreSunriseTime
    -- o.fogPreSunsetTime = i.fogPreSunsetTime
    o.hoursBetweenWeatherChanges = i.hoursBetweenWeatherChanges
    o.hoursRemaining = i.hoursRemaining
    -- o.lastActiveRegion = i.lastActiveRegion -- TODO
    -- o.masser = i.masser -- TODO
    o.nextWeather = _tes3weather(jsonrpc.object(), i.nextWeather)
    -- o.particlesActive = i.particlesActive
    -- o.particlesInactive = i.particlesInactive
    o.precipitationFallSpeed = i.precipitationFallSpeed
    -- o.sceneAtmosphere = i.sceneAtmosphere
    -- o.sceneClouds = i.sceneClouds
    -- o.sceneNightSky = i.sceneNightSky
    -- o.sceneRainRoot = i.sceneRainRoot
    -- o.sceneSkyLight = i.sceneSkyLight
    -- o.sceneSkyRoot = i.sceneSkyRoot
    -- o.sceneSnowRoot = i.sceneSnowRoot
    -- o.sceneStormRoot = i.sceneStormRoot
    -- o.sceneSunBase = i.sceneSunBase
    -- o.sceneSunGlare = i.sceneSunGlare
    -- o.sceneSunVis = i.sceneSunVis
    -- o.secunda = i.secunda -- TODO
    -- o.skyPostSunriseTime = i.skyPostSunriseTime
    -- o.skyPostSunsetTime = i.skyPostSunsetTime
    -- o.skyPreSunriseTime = i.skyPreSunriseTime
    -- o.skyPreSunsetTime = i.skyPreSunsetTime
    o.snowFallSpeedScale = i.snowFallSpeedScale
    o.starsFadingDuration = i.starsFadingDuration
    o.starsPostSunsetStart = i.starsPostSunsetStart
    o.starsPreSunriseFinish = i.starsPreSunriseFinish
    o.sunglareFaderAngleMax = i.sunglareFaderAngleMax
    o.sunglareFaderColor = i.sunglareFaderColor
    o.sunglareFaderMax = i.sunglareFaderMax
    o.sunPostSunriseTime = i.sunPostSunriseTime
    o.sunPostSunsetTime = i.sunPostSunsetTime
    o.sunPreSunriseTime = i.sunPreSunriseTime
    o.sunPreSunsetTime = i.sunPreSunsetTime
    o.sunriseDuration = i.sunriseDuration
    o.sunriseHour = i.sunriseHour
    o.sunsetDuration = i.sunsetDuration
    o.sunsetHour = i.sunsetHour
    o.timescaleClouds = i.timescaleClouds
    o.transitionScalar = i.transitionScalar
    o.underwaterColor = i.underwaterColor
    o.underwaterColorWeight = i.underwaterColorWeight
    o.underwaterDayFog = i.underwaterDayFog
    o.underwaterIndoorFog = i.underwaterIndoorFog
    o.underwaterNightFog = i.underwaterNightFog
    o.underwaterSunriseFog = i.underwaterSunriseFog
    o.underwaterSunsetFog = i.underwaterSunsetFog
    -- o.weathers = i.weathers -- all weathers
    o.windVelocityCurrWeather = i.windVelocityCurrWeather
    o.windVelocityNextWeather = i.windVelocityNextWeather
    return o
end

---@param o MCP.AnyMap?
---@param i tes3worldController
---@return MCP.AnyMap?
local function _tes3worldController(o, i)
    if not i then
        return nil
    end
    -- o.aiDistanceScale = i.aiDistanceScale
    -- o.allMobileActors = i.allMobileActors
    -- o.armCamera = i.armCamera
    -- o.audioController = i.audioController
    o.blindnessFader =  _tes3fader(jsonrpc.object(), i.blindnessFader)
    -- o.characterRenderTarget = i.characterRenderTarget
    -- o.charGenState = i.charGenState -- TODO
    -- o.countMusicTracksBattle = i.countMusicTracksBattle
    -- o.countMusicTracksExplore = i.countMusicTracksExplore
    -- o.criticalDamageSound = i.criticalDamageSound
    -- o.cursorOff = i.cursorOff
    o.day = _tes3globalVariable(jsonrpc.object(), i.day)
    o.daysPassed = _tes3globalVariable(jsonrpc.object(), i.daysPassed)
    -- o.deadFloatScale = i.deadFloatScale
    -- o.defaultLandSound = i.defaultLandSound
    -- o.defaultLandWaterSound = i.defaultLandWaterSound
    -- o.deltaTime = i.deltaTime
    o.difficulty = i.difficulty
    -- o.drowningDamageSound = i.drowningDamageSound
    -- o.drownSound = i.drownSound
    -- o.enchantedItemEffect = i.enchantedItemEffect
    -- o.enchantedItemEffectCreated = i.enchantedItemEffectCreated
    -- o.enchantedItemEffectTextures = i.enchantedItemEffectTextures
    o.flagLevitationDisabled = i.flagLevitationDisabled
    o.flagTeleportingDisabled = i.flagTeleportingDisabled
    -- o.globalScripts = i.globalScripts
    -- o.handToHandHit2Sound = i.handToHandHit2Sound
    -- o.handToHandHitSound = i.handToHandHitSound
    -- o.healthDamageSound = i.healthDamageSound
    -- o.heavyArmorHitSound = i.heavyArmorHitSound
    -- o.helpDelay = i.helpDelay
    o.hitFader = _tes3fader(jsonrpc.object(), i.hitFader)
    o.hour = _tes3globalVariable(jsonrpc.object(), i.hour)
    -- o.hudStyle = i.hudStyle -- TODO
    -- o.inputController = i.inputController
    -- o.instance = i.instance
    -- o.itemRepairSound = i.itemRepairSound
    -- o.lastFrameTime = i.lastFrameTime
    -- o.lightArmorHitSound = i.lightArmorHitSound
    -- o.mapController = i.mapController
    -- o.maxFPS = i.maxFPS
    -- o.mediumArmorHitSound = i.mediumArmorHitSound
    -- o.menuAlpha = i.menuAlpha
    -- o.menuCamera = i.menuCamera
    -- o.menuClickSound = i.menuClickSound
    -- o.menuController = i.menuController
    -- o.menuSizeSound = i.menuSizeSound
    -- o.missSound = i.missSound
    -- o.mobManager = i.mobManager
    o.month = _tes3globalVariable(jsonrpc.object(), i.month)
    o.monthsToRespawn = _tes3globalVariable(jsonrpc.object(), i.monthsToRespawn)
    -- o.mouseSensitivityX = i.mouseSensitivityX
    -- o.mouseSensitivityY = i.mouseSensitivityY
    o.musicSituation = enumname.musicSituation(i.musicSituation)
    -- o.nodeCursor = i.nodeCursor
    -- o.parentWindowHandle = i.parentWindowHandle
    -- o.projectionDistance = i.projectionDistance
    -- o.quests = i.quests
    -- o.quickSaveWhenResting = i.quickSaveWhenResting
    -- o.rechargingItems = i.rechargingItems -- need?
    -- o.shaderWaterReflectTerrain = i.shaderWaterReflectTerrain
    -- o.shaderWaterReflectUpdate = i.shaderWaterReflectUpdate
    -- o.shadowCamera = i.shadowCamera
    -- o.shadows = i.shadows
    -- o.showSubtitles = i.showSubtitles
    o.simulationTimeScalar = i.simulationTimeScalar
    -- o.splashController = i.splashController
    -- o.splashscreenCamera = i.splashscreenCamera
    o.stopGameLoop = i.stopGameLoop
    o.sunglareFader = _tes3fader(jsonrpc.object(), i.sunglareFader)
    o.systemTime = i.systemTime
    o.timescale = _tes3globalVariable(jsonrpc.object(), i.timescale)
    o.transitionFader = _tes3fader(jsonrpc.object(), i.transitionFader)
    o.useBestAttack = i.useBestAttack
    -- o.vfxManager = i.vfxManager
    -- o.viewHeight = i.viewHeight
    -- o.viewWidth = i.viewWidth
    -- o.weaponSwishSound = i.weaponSwishSound
    o.weatherController =  _tes3weatherController(jsonrpc.object(), i.weatherController)
    o.werewolfFader = _tes3fader(jsonrpc.object(), i.werewolfFader)
    -- o.werewolfFOV = i.werewolfFOV
    -- o.worldCamera = i.worldCamera
    o.year = _tes3globalVariable(jsonrpc.object(), i.year)

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
