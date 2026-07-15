local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local config = require("morrowind-mcp.config")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "tes3object" })
local enumname = require("morrowind-mcp.tes3.enumname")
local ui = require("morrowind-mcp.tes3.ui")
local iter = require("morrowind-mcp.tes3.iterator")

-- serialzie tes3 various objects for json serialization.
local this = {}

--TODO text fields need to clean macro. replace variables like a journal.

--TODO fetch shallow (only id, name) or traverse once, traverse recrusively.


-- default __tojson(self) just put id such as "tes3baseObject:DoorMarker".
-- so we need to implement our own serialization function for tes3object and tes3reference... and more.
-- but I consider if __tojson(self) overrides, other mods possible unexpected behavior, so I implement a new functions.
-- also we don't need all field for AI. hand picking?

-- cache static objects better performance? how?

-- TODO rename tes3object***.lua, tes3ui***.lua, tes3***data.lua?
-- tes3/ object, ui, data, enum

-- TODO filepath convert to mcp resoucrs path? possibly agents try to access resource? if so, we need to load game data additionaly.

-- for cycler reference snippet
--[[
local function serialize(obj, cache)
    cache = cache or {}
    if cache[obj] then
        return "<Circular Reference>"
    end
    if type(obj) == "table" then
        cache[obj] = true

        local result = "{"
        for k, v in pairs(obj) do
            result = result .. tostring(k) .. "=" .. serialize(v, cache) .. ", "
        end
        result = result .. "}"
        return result
    else
        return tostring(obj)
    end
end
--]]


---@param i any
---@return boolean
local function HasToJsonMethod(i)
    if type(i) ~= "userdata" then
        return false
    end

    local ok, mt = pcall(getmetatable, i)
    if not ok or type(mt) ~= "table" then
        return false
    end

    return type(mt.__tojson) == "function"
end

---@param i any
---@return boolean
local function ValidateType(i)
    if not config.development.debug then
        return true
    end

    if i == nil then
        return true
    end
    -- Allow userdata only when it provides __tojson for stable JSON serialization.

    local t = type(i)
    if t == "userdata" then
        return HasToJsonMethod(i)
    end

    if t == "function" or t == "thread" then
        return false
    end

    if t == "table" then
        for k, v in pairs(i) do
            local vt = type(v)
            if vt == "userdata" then
                if not HasToJsonMethod(v) then
                    logger:error("Invalid value in table: %s=%s", k, vt)
                    return false
                end
            elseif vt == "function" or vt == "thread" then
                logger:error("Invalid value in table: %s=%s", k, vt)
                return false
            end
        end
    end

    return true
end


local npcSexName = {
    [0] = "male",
    [1] = "female",
}



---@param i tes3bountyData
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3bountyData(i, o)
    if not i then
        return nil
    end
    if not i.keys or table.size(i.keys) == 0 then
        return nil
    end
    o = o or jsonrpc.object(table.size(i.keys))
    local amount = 0
    for _, key in ipairs(i.keys) do
        if key then
            local value = i:getValue(key)
            o[key] = value
            amount = amount + value
        end
    end

    local _ = ValidateType(o)
    return o
end

---@param i tes3fader
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3fader(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()
    o.active = i.active
    -- cant get current value of fader

    local _ = ValidateType(o)
    return o
end

---@param i tes3itemData
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3itemData(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()

    o.charge = i.charge
    o.condition = i.condition
    -- o.context = i.context
    o.count = i.count
    -- o.data = i.data -- for modding data
    -- o.owner = i.owner -- TODO
    -- o.requirement = i.requirement -- TODO
    o.script = this.tes3script(i.script)
    -- o.scriptVariables = i.scriptVariables
    o.soul = this.tes3anyObject(i.soul)
    -- o.tempData = i.tempData -- for modding temp data
    o.timeLeft = i.timeLeft

    local _ = ValidateType(o)
    return o
end


---@param i tes3inventoryTile
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3inventoryTile(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()

    o.count = i.count
    o.element = ui.tes3uiElement(i.element)
    -- o.flags = i.flags
    o.isBartered = i.isBartered
    o.isBoundItem = i.isBoundItem
    o.isEquipped = i.isEquipped
    o.item = this.tes3anyObject(i.item)
    o.itemData = this.tes3itemData(i.itemData)
    o.type = enumname.inventoryTileType(i.type)

    local _ = ValidateType(o)
    return o
end

---@param i tes3statisticSkill|tes3statistic|nil
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3statistic(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()

    o.base = i.base
    -- o.baseRaw = i.baseRaw
    o.current = i.current
    -- o.currentRaw = i.currentRaw
    o.normalized = i.normalized

    -- almost skills are tes3statisticSkill or tes3statistic.
    -- it needs to care about incoming base type.
    if i.type then
        o.type = enumname.skillType(i.type)
    end

    local _ = ValidateType(o)
    return o
end


---@param i tes3weatherClear
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherClear(i, o)
    -- no fields
end
---@param i tes3weatherCloudy
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherCloudy(i, o)
    -- no fields
end
---@param i tes3weatherFoggy
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherFoggy(i, o)
    -- no fields
end
---@param i tes3weatherOvercast
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherOvercast(i, o)
    -- no fields
end
---@param i tes3weatherRain
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherRain(i, o)
    o.maxParticles = i.maxParticles
    o.particleEntranceSpeed = i.particleEntranceSpeed
    o.particleHeightMax = i.particleHeightMax
    o.particleHeightMin = i.particleHeightMin
    o.particleRadius = i.particleRadius
    o.rainActive = i.rainActive
    o.rainLoopSound = this.tes3sound(i.rainLoopSound)
    o.rainLoopSoundId = i.rainLoopSoundId
    o.threshold = i.threshold
end
---@param i tes3weatherThunder
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherThunder(i, o)
    o.flashDecrement = i.flashDecrement
    o.maxParticles = i.maxParticles
    o.particleEntranceSpeed = i.particleEntranceSpeed
    o.particleHeightMax = i.particleHeightMax
    o.particleHeightMin = i.particleHeightMin
    o.particleRadius = i.particleRadius
    o.rainActive = i.rainActive
    o.rainLoopSound = this.tes3sound(i.rainLoopSound)
    o.rainLoopSoundId = i.rainLoopSoundId
    o.threshold = i.threshold
    o.thunderFrequency = i.thunderFrequency
    o.thunderSound1 = this.tes3sound(i.thunderSound1)
    o.thunderSound1Id = i.thunderSound1Id
    o.thunderSound2 = this.tes3sound(i.thunderSound2)
    o.thunderSound2Id = i.thunderSound2Id
    o.thunderSound3 = this.tes3sound(i.thunderSound3)
    o.thunderSound3Id = i.thunderSound3Id
    o.thunderSound4 = this.tes3sound(i.thunderSound4)
    o.thunderSound4Id = i.thunderSound4Id
    o.thunderSoundCount = i.thunderSoundCount
    o.thunderThreshold = i.thunderThreshold
end
---@param i tes3weatherAsh
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherAsh(i, o)
    o.stormOrigin = i.stormOrigin
    o.threshold = i.threshold
end
---@param i tes3weatherBlight
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherBlight(i, o)
    o.blightDiseaseChance = i.blightDiseaseChance
    -- o.blightDiseases = i.blightDiseases -- TODO
    o.stormOrigin = i.stormOrigin
    o.threshold = i.threshold
end
---@param i tes3weatherSnow
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherSnow(i, o)
    o.maxParticles = i.maxParticles
    o.particleEntranceSpeed = i.particleEntranceSpeed
    o.particleHeightMax = i.particleHeightMax
    o.particleHeightMin = i.particleHeightMin
    o.particleRadius = i.particleRadius
    o.threshold = i.threshold
end
---@param i tes3weatherBlizzard
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3weatherBlizzard(i, o)
    o.threshold = i.threshold
end

local weatherHandler = {
	[tes3.weather.clear] = tes3weatherClear,
	[tes3.weather.cloudy] = tes3weatherCloudy,
	[tes3.weather.foggy] = tes3weatherFoggy,
	[tes3.weather.overcast] = tes3weatherOvercast,
	[tes3.weather.rain] = tes3weatherRain,
	[tes3.weather.thunder] = tes3weatherThunder,
	[tes3.weather.ash] = tes3weatherAsh,
	[tes3.weather.blight] = tes3weatherBlight,
	[tes3.weather.snow] = tes3weatherSnow,
	[tes3.weather.blizzard] = tes3weatherBlizzard,
}

---@param i tes3weather|tes3weatherAsh|tes3weatherBlight|tes3weatherBlizzard|tes3weatherClear|tes3weatherCloudy|tes3weatherFoggy|tes3weatherOvercast|tes3weatherRain|tes3weatherSnow|tes3weatherThunder
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3weather(i, o)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    o = o or jsonrpc.object()

    o.ambientDayColor = i.ambientDayColor
    o.ambientLoopSound = this.tes3sound(i.ambientLoopSound)
    o.ambientLoopSoundId = i.ambientLoopSoundId
    o.ambientNightColor = i.ambientNightColor
    o.ambientPlaying = i.ambientPlaying
    o.ambientSunriseColor = i.ambientSunriseColor
    o.ambientSunsetColor = i.ambientSunsetColor
    o.cloudsMaxPercent = i.cloudsMaxPercent
    o.cloudsSpeed = i.cloudsSpeed
    o.cloudTexture = i.cloudTexture
    -- o.controller = i.controller -- TODO avoid circular reference
    o.fogDayColor = i.fogDayColor
    o.fogNightColor = i.fogNightColor
    o.fogSunriseColor = i.fogSunriseColor
    o.fogSunsetColor = i.fogSunsetColor
    o.glareView = i.glareView
    o.index = enumname.weather(i.index) -- equals name?
    o.landFogDayDepth = i.landFogDayDepth
    o.landFogNightDepth = i.landFogNightDepth
    o.name = i.name
    o.skyDayColor = i.skyDayColor
    o.skyNightColor = i.skyNightColor
    o.skySunriseColor = i.skySunriseColor
    o.skySunsetColor = i.skySunsetColor
    o.sunDayColor = i.sunDayColor
    o.sundiscSunsetColor = i.sundiscSunsetColor
    o.sunNightColor = i.sunNightColor
    o.sunSunriseColor = i.sunSunriseColor
    o.sunSunsetColor = i.sunSunsetColor
    o.transitionDelta = i.transitionDelta
    o.underwaterSoundState = i.underwaterSoundState
    o.windSpeed = i.windSpeed

    local handler = weatherHandler[i.index]
    if handler then
        handler(i, o)
    else
        logger:warn("No serializer for weather type: %s", enumname.weather(i.index))
    end

    local _ = ValidateType(o)
    return o
end


---@param i tes3weatherController
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3weatherController(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()

    -- TODO need to calculate current ambient color?
    -- TODO need to calculate current sun direction and color?

    o.ambientPostSunriseTime = i.ambientPostSunriseTime
    o.ambientPostSunsetTime = i.ambientPostSunsetTime
    o.ambientPreSunriseTime = i.ambientPreSunriseTime
    o.ambientPreSunsetTime = i.ambientPreSunsetTime
    o.currentFogColor = i.currentFogColor
    o.currentSkyColor = i.currentSkyColor
    o.currentWeather = this.tes3weather(i.currentWeather)
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
    o.nextWeather = this.tes3weather(i.nextWeather)
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

    local _ = ValidateType(o)
    return o
end


---@param i tes3worldController
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3worldController(i, o)
    if not i then
        return nil
    end
    o = o or jsonrpc.object()

    -- o.aiDistanceScale = i.aiDistanceScale
    -- o.allMobileActors = i.allMobileActors
    -- o.armCamera = i.armCamera
    -- o.audioController = i.audioController
    o.blindnessFader = this.tes3fader(i.blindnessFader)
    -- o.characterRenderTarget = i.characterRenderTarget
    -- o.charGenState = i.charGenState -- TODO
    -- o.countMusicTracksBattle = i.countMusicTracksBattle
    -- o.countMusicTracksExplore = i.countMusicTracksExplore
    -- o.criticalDamageSound = i.criticalDamageSound
    -- o.cursorOff = i.cursorOff
    o.day = this.tes3globalVariable(i.day)
    o.daysPassed = this.tes3globalVariable(i.daysPassed)
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
    o.hitFader = this.tes3fader(i.hitFader)
    o.hour = this.tes3globalVariable(i.hour)
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
    o.month = this.tes3globalVariable(i.month)
    o.monthsToRespawn = this.tes3globalVariable(i.monthsToRespawn)
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
    o.sunglareFader = this.tes3fader(i.sunglareFader)
    o.systemTime = i.systemTime
    o.timescale = this.tes3globalVariable(i.timescale)
    o.transitionFader = this.tes3fader(i.transitionFader)
    o.useBestAttack = i.useBestAttack
    -- o.vfxManager = i.vfxManager
    -- o.viewHeight = i.viewHeight
    -- o.viewWidth = i.viewWidth
    -- o.weaponSwishSound = i.weaponSwishSound
    o.weatherController = this.tes3weatherController(i.weatherController)
    o.werewolfFader = this.tes3fader(i.werewolfFader)
    -- o.werewolfFOV = i.werewolfFOV
    -- o.worldCamera = i.worldCamera
    o.year = this.tes3globalVariable(i.year)

    return o
end








---@param i tes3baseObject?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3baseObject(i, o)
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

    -- o.blocked = i.blocked -- locked on CS
    -- o.deleted = i.deleted
    -- o.disabled = i.disabled
    o.id = i.id
    o.modified = i.modified
    -- o.objectFlags = i.objectFlags -- TODO means flags
    o.objectType = enumname.objectType(i.objectType)
    o.persistent = i.persistent
    o.sourceless = i.sourceless
    -- o.sourceMod = i.sourceMod
    o.supportsActivate = i.supportsActivate

    local _ = ValidateType(o)
    return o
end

---@param i tes3object?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3object(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end
    if i.isLocationMarker then -- for CS
        return nil
    end
    -- o.isLocationMarker = i.isLocationMarker
    -- o.nextInCollection = i.nextInCollection
    -- o.owningCollection = i.owningCollection
    -- o.previousInCollection = i.previousInCollection
    o.scale = i.scale
    -- o.sceneCollisionRoot = i.sceneCollisionRoot
    -- o.sceneNode = i.sceneNode

    local _ = ValidateType(o)
    return o
end


---@param i tes3physicalObject?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3physicalObject(i, o)
    if not i then
        return nil
    end
    o = tes3object(i, o)
    if not o then
        return nil
    end

    o.boundingBox = i.boundingBox
    -- o.referenceList = i.referenceList

    local _ = ValidateType(o)
    return o
end

---@param i tes3item?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3item(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.icon = i.icon
    o.isCarriable = i.isCarriable
    o.mesh = i.mesh
    o.name = i.name
    o.promptsEquipmentReevaluation = i.promptsEquipmentReevaluation
    -- o.stolenList = i.stolenList -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3actor?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3actor(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    -- o.actorFlags = i.actorFlags
    o.barterGold = i.barterGold
    o.blood = i.blood
    -- o.cloneCount = i.cloneCount
    -- o.equipment = i.equipment -- TODO
    -- o.inventory = i.inventory -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileObject?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3mobileObject(i, o)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    o = o or jsonrpc.object()

    o.boundSize = i.boundSize
    o.boundSize2D = i.boundSize2D
    o.cellX = i.cellX
    o.cellY = i.cellY
    o.dynamicLightingValid = i.dynamicLightingValid
    -- o.flags = i.flags
    o.height = i.height
    o.impulseVelocity = i.impulseVelocity
    -- o.inventory = i.inventory -- TODO
    o.isAffectedByGravity = i.isAffectedByGravity
    -- o.lightEffectData = i.lightEffectData
    o.mobToMobCollision = i.mobToMobCollision
    o.movementCollision = i.movementCollision
    -- o.movementFlags = i.movementFlags
    o.objectType = enumname.objectType(i.objectType)
    o.playerDistance = i.playerDistance
    o.position = i.position
    -- o.prevMovementFlags = i.prevMovementFlags
    -- o.reference = this.tes3reference(i.reference, nil, i) -- TODO avoid circular reference
    o.velocity = i.velocity

    local _ = ValidateType(o)
    return o
end

--- tes3globalVariable inherits tes3baseObject, but it seems just to return value is better.
---@param i tes3globalVariable
---@param o MCP.AnyMap?
---@return number?
function this.tes3globalVariable(i, o)
    if i == nil then
        return nil
    end
    return i.value
    -- if not this.tes3baseObject(i, o) then
    --     return nil
    -- end
    -- o.value = i.value
    -- return o
end


-- https://mwse.github.io/MWSE/references/object-types/

-- avoid circular reference idea
-- this.function(i, o, root?)
-- or instance.new(root) then instance.function(i, o)

---@param i tes3activator?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3activator(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.mesh = i.mesh
    o.name = i.name
    o.script = this.tes3script(i.script)

    local _ = ValidateType(o)
    return o
end

---@param i tes3alchemy?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3alchemy(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    -- o.autoCalc = i.autoCalc
    -- o.effects = iter.ForEach(i.effects, this.tes3effect) -- TODO
    -- o.flags = i.flags
    o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3apparatus?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3apparatus(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.quality  = i.quality
    o.script  = this.tes3script(i.script)
    o.type  = enumname.apparatusType(i.type)
    o.value  = i.value
    o.weight  = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3armor?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3armor(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.armorRating = i.armorRating
    o.armorScalar = i.armorScalar
    o.enchantCapacity = i.enchantCapacity
    o.enchantment = this.tes3enchantment(i.enchantment)
    o.isClosedHelmet = i.isClosedHelmet
    o.isLeftPart = i.isLeftPart
    o.isUsableByBeasts = i.isUsableByBeasts
    o.maxCondition = i.maxCondition
    -- o.parts = iter.ForEach(i.parts, ) -- TODO
    o.script = this.tes3script(i.script)
    o.slot = enumname.armorSlot(i.slot) -- same as slotName?
    o.slotName = i.slotName
    o.value = i.value
    o.weight = i.weight
    o.weightClass = enumname.armorWeightClass(i.weightClass)

    local _ = ValidateType(o)
    return o
end

---@param i tes3birthsign?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3birthsign(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.description = i.description
    o.name = i.name
    -- o.spells = i.spells -- TODO
    o.texturePath = i.texturePath

    local _ = ValidateType(o)
    return o
end

---@param i tes3bodyPart?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3bodyPart(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.female = i.female
    o.mesh = i.mesh
    o.part = enumname.partIndex(i.part)
    o.partType = enumname.activeBodyPartLayer(i.partType)
    o.playable = i.playable
    o.raceName = i.raceName
    -- o.sceneNode = i.sceneNode
    o.vampiric = i.vampiric

    local _ = ValidateType(o)
    return o
end

---@param i tes3book?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3book(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.enchantCapacity = i.enchantCapacity
    o.enchantment = this.tes3enchantment(i.enchantment)
    o.script = this.tes3script(i.script)
    o.skill = enumname.skill(i.skill)
    -- o.text = i.text -- TODO  dont read open check flag? convert html to markdown or json. or just empty until activate.
    o.type = enumname.bookType(i.type)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3cell?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3cell(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.activators = i.activators -- TODO use list iterator
    -- o.actors = i.actors -- TODO use list iterator
    -- o.ambientColor = i.ambientColor -- TODO interior only, enough world controller and weather?
    o.behavesAsExterior = i.behavesAsExterior
    -- o.cellFlags =  i.cellFlags
    o.displayName = i.displayName
    o.editorName = i.editorName
    -- o.fogColor = i.fogColor -- TODO interior only, enough world controller and weather?
    -- o.fogDensity = i.fogDensity -- TODO interior only, enough world controller and weather?
    o.gridX = i.gridX
    o.gridY = i.gridY
    o.hasMapMarker = i.hasMapMarker
    o.hasWater = i.hasWater
    o.isInterior = i.isInterior
    o.isOrBehavesAsExterior = i.isOrBehavesAsExterior
    o.landscape =  this.tes3land(i.landscape)
    o.name = i.name
    -- o.pathGrid = this.tes3pathGrid(i.pathGrid) -- TODO avoid circular reference
    -- o.pickObjectsRoot = i.pickObjectsRoot
    o.region = this.tes3region(i.region)
    o.restingIsIllegal = i.restingIsIllegal
    -- o.staticObjectsRoot = i.staticObjectsRoot
    -- o.statics = i.statics -- TODO use list iterator
    -- o.sunColor = i.sunColor -- TODO interior only, enough world controller and weather?
    o.waterLevel = i.waterLevel

    local _ = ValidateType(o)
    return o
end

---@param i tes3class?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3class(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.attributes = iter.ForEachObject(i.attributes, enumname.attribute)
    o.bartersAlchemy = i.bartersAlchemy
    o.bartersApparatus = i.bartersApparatus
    o.bartersArmor = i.bartersArmor
    o.bartersBooks = i.bartersBooks
    o.bartersClothing = i.bartersClothing
    o.bartersEnchantedItems = i.bartersEnchantedItems
    o.bartersIngredients = i.bartersIngredients
    o.bartersLights = i.bartersLights
    o.bartersLockpicks = i.bartersLockpicks
    o.bartersMiscItems = i.bartersMiscItems
    o.bartersProbes = i.bartersProbes
    o.bartersRepairTools = i.bartersRepairTools
    o.bartersWeapons = i.bartersWeapons
    o.description = i.description
    o.image = i.image
    o.majorSkills = iter.ForEachObject(i.majorSkills, enumname.skill)
    o.minorSkills = iter.ForEachObject(i.minorSkills, enumname.skill)
    o.name = i.name
    o.offersBartering = i.offersBartering
    o.offersEnchanting = i.offersEnchanting
    o.offersRepairs = i.offersRepairs
    o.offersSpellmaking = i.offersSpellmaking
    o.offersSpells = i.offersSpells
    o.offersTraining = i.offersTraining
    o.playable = i.playable
    o.services = i.services
    o.skills = iter.ForEachObject(i.skills, enumname.skill)
    o.specialization = enumname.specialization(i.specialization)

    local _ = ValidateType(o)
    return o
end

---@param i tes3clothing?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3clothing(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.enchantCapacity = i.enchantCapacity
    o.enchantment =  this.tes3enchantment(i.enchantment)
    o.isLeftPart = i.isLeftPart
    o.isUsableByBeasts = i.isUsableByBeasts
    -- o.parts = i.parts -- TODO
    o.script = this.tes3script(i.script)
    o.slot = enumname.clothingSlot(i.slot)
    o.slotName = i.slotName
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3container|tes3containerInstance|nil
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3container(i, o)
    if not i then
        return nil
    end
    o = tes3actor(i, o)
    if not o then
        return nil
    end

    -- common fields
    o.isInstance = i.isInstance
    o.mesh = i.mesh
    o.name = i.name
    o.organic = i.organic
    o.respawns = i.respawns
    o.script = this.tes3script(i.script)

    if i.isInstance then
        ---@cast i tes3containerInstance
        o.baseObject = this.tes3container(i.baseObject)-- almost values are same as between baseObject and instance?
        o.reference = this.tes3reference(i.reference)
    else
        ---@cast i tes3container
        o.capacity = i.capacity
    end

    local _ = ValidateType(o)
    return o
end

---@param i tes3creature|tes3creatureInstance|nil
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3creature(i, o)
    if not i then
        return nil
    end
    o = tes3actor(i, o)
    if not o then
        return nil
    end

    -- common field
    -- o.aiConfig = i.aiConfig -- TODO
    -- o.attacks = i.attacks -- TODO
    o.attributes = jsonrpc.array(i.attributes)
    o.biped = i.biped
    o.fatigue = i.fatigue
    o.flies = i.flies
    o.health = i.health
    o.isAttacked = i.isAttacked
    o.isEssential = i.isEssential
    o.isInstance = i.isInstance
    o.isRespawn = i.isRespawn
    o.level = i.level
    o.magicka = i.magicka
    o.mesh = i.mesh
    o.name = i.name
    o.respawns = i.respawns
    o.script = this.tes3script(i.script)
    o.skills = jsonrpc.array(i.skills)
    o.soul = i.soul
    o.soundCreature = this.tes3creature(i.soundCreature)
    -- o.spells = i.spells -- TODO
    o.swims = i.swims
    o.type = enumname.creatureType(i.type)
    o.usesEquipment = i.usesEquipment
    o.walks = i.walks

    if i.isInstance then
        ---@cast i tes3creatureInstance
        o.baseObject = this.tes3creature(i.baseObject)-- almost values are same as between baseObject and instance?
        -- o.equipment = i.equipment -- TODO
        -- o.mobile = this.tes3anyObject(i.mobile) -- TODO avoid circular reference
        o.reference = this.tes3reference(i.reference)
        o.weapon = this.tes3weapon(i.weapon)

    else
        ---@cast i tes3creature
    end

    local _ = ValidateType(o)
    return o
end

---@param i tes3dialogue?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3dialogue(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.info = iter.ForEachObject(i.info, this.tes3dialogueInfo) -- contain all info
    o.journalIndex = i.journalIndex
    o.type = enumname.dialogueType(i.type)

    local _ = ValidateType(o)
    return o
end

---@param i tes3dialogueInfo?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3dialogueInfo(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.actor = this.tes3anyObject(i.actor)
    o.cell = this.tes3cell(i.cell)
    o.disposition = i.disposition
    -- o.firstHeardFrom = this.tes3anyObject(i.firstHeardFrom) -- need?
    o.isQuestFinished = i.isQuestFinished
    o.isQuestName = i.isQuestName
    o.isQuestRestart = i.isQuestRestart
    o.journalIndex = i.journalIndex
    o.npcClass = this.tes3class(i.npcClass)
    o.npcFaction = this.tes3faction(i.npcFaction)
    o.npcRace = this.tes3anyObject(i.npcRace)
    o.npcRank = i.npcRank
    o.npcSex = npcSexName[i.npcSex] or i.npcSex
    o.pcFaction = i.pcFaction -- TODO number to means string if possible
    o.pcRank = i.pcRank
    o.text = i.text
    o.type = enumname.dialogueType(i.type)

    local _ = ValidateType(o)
    return o
end

---@param i tes3door?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3door(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.closeSound = this.tes3sound(i.closeSound)
    o.mesh = i.mesh
    o.name = i.name
    o.openSound = this.tes3sound(i.openSound)
    o.script = this.tes3script(i.script)

    local _ = ValidateType(o)
    return o
end

---@param i tes3enchantment?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3enchantment(i, o)
    if not i then
        return nil
    end
    o = tes3object(i, o)
    if not o then
        return nil
    end

    o.autoCalc = i.autoCalc
    o.castType = enumname.enchantmentType(i.castType)
    o.chargeCost = i.chargeCost
    -- o.effects = iter.ForEach(i.effects, this.tes3effect) -- TODO
    -- o.flags = i.flags -- flags mean?
    o.maxCharge = i.maxCharge

    local _ = ValidateType(o)
    return o
end

---@param i tes3faction?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3faction(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.attributes = i.attributes -- TODO
    o.name = i.name
    o.playerExpelled = i.playerExpelled
    o.playerJoined = i.playerJoined
    o.playerRank = i.playerRank
    o.playerReputation = i.playerReputation
    -- o.ranks = i.ranks -- TODO
    -- o.reactions = i.reactions -- TODO
    -- o.skills = i.skills -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3gameSetting?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3gameSetting(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.defaultValue = i.defaultValue
    -- o.index = i.index
    -- o.rawValue = i.rawValue -- maybe no need
    o.type = i.type
    o.value = i.value

    local _ = ValidateType(o)
    return o
end

---@param i tes3ingredient?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3ingredient(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.effectAttributeIds = jsonrpc.array(i.effectAttributeIds)
    -- o.effects = i.effects -- TODO
    o.effectSkillIds = jsonrpc.array(i.effectSkillIds)
    o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3land?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3land(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.flags = i.flags -- means?
    o.gridX = i.gridX
    o.gridY = i.gridY
    o.maxHeight = i.maxHeight
    o.minHeight = i.minHeight
    -- o.sceneNode = i.sceneNode -- TODO
    -- o.textureIndices = jsonrpc.array(i.textureIndices) -- tes3.dataHandler.nonDynamicData.landTextures

    local _ = ValidateType(o)
    return o
end

---@param i tes3landTexture?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3landTexture(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.filename = i.filename
    o.id = i.id
    o.index = i.index
    -- o.texture = i.texture

    local _ = ValidateType(o)
    return o
end

---@param i tes3leveledCreature?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3leveledCreature(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.calculateFromAllLevels = i.calculateFromAllLevels
    o.chanceForNothing = i.chanceForNothing
    o.count = i.count
    -- o.flags = i.flags -- means?
    -- o.list = i.list -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3leveledItem?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3leveledItem(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.calculateForEachItem = i.calculateForEachItem
    o.calculateFromAllLevels = i.calculateFromAllLevels
    o.chanceForNothing = i.chanceForNothing
    o.count = i.count
    -- o.flags = i.flags -- means?
    -- o.list = i.list -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3light?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3light(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.canCarry = i.canCarry
    o.color = jsonrpc.array(i.color)
    o.flickers = i.flickers
    o.flickersSlowly = i.flickersSlowly
    o.isDynamic = i.isDynamic
    o.isFire = i.isFire
    o.isNegative = i.isNegative
    o.isOffByDefault = i.isOffByDefault
    o.pulses = i.pulses
    o.pulsesSlowly = i.pulsesSlowly
    o.radius = i.radius
    o.script = this.tes3script(i.script)
    o.sound = this.tes3sound(i.sound)
    o.time = i.time
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3lockpick?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3lockpick(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.maxCondition = i.maxCondition
    o.quality = i.quality
    o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3magicEffect?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3magicEffect(i, o)
    if not i then
        return nil
    end
    -- actually tes3magicEffect actually  inherit tes3baseObject, but meta data is not inherit.
    -- https://github.com/MWSE/MWSE/blob/7f2fab33b05627b46cd3d1357dbe3ad4ee1b073f/MWSE/TES3MagicEffect.h#L227
    ---@diagnostic disable-next-line: param-type-mismatch
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.allowEnchanting = i.allowEnchanting
    o.allowSpellmaking = i.allowSpellmaking
    o.appliesOnce = i.appliesOnce
    o.areaSoundEffect = this.tes3sound(i.areaSoundEffect)
    o.areaVisualEffect = this.tes3anyObject(i.areaVisualEffect)
    -- o.baseFlags = i.baseFlags -- means?
    o.baseMagickaCost = i.baseMagickaCost
    o.bigIcon = i.bigIcon
    o.boltSoundEffect = this.tes3sound(i.boltSoundEffect)
    o.boltVisualEffect = this.tes3anyObject(i.boltVisualEffect)
    o.canCastSelf = i.canCastSelf
    o.canCastTarget = i.canCastTarget
    o.canCastTouch = i.canCastTouch
    o.casterLinked = i.casterLinked
    o.castSoundEffect = this.tes3sound(i.castSoundEffect)
    o.castVisualEffect = this.tes3anyObject(i.castVisualEffect)
    o.description = i.description
    -- o.flags = i.flags -- means?
    o.hasActorLighting = i.hasActorLighting
    o.hasContinuousVFX = i.hasContinuousVFX
    o.hasNoDuration = i.hasNoDuration
    o.hasNoMagnitude = i.hasNoMagnitude
    o.hitSoundEffect = this.tes3sound(i.hitSoundEffect)
    o.hitVisualEffect = this.tes3anyObject(i.hitVisualEffect)
    o.icon = i.icon
    o.id = enumname.effect(i.id) or i.id -- modding magic possible to be out of ranges in tes3.effect.
    o.illegalDaedra = i.illegalDaedra
    o.isHarmful = i.isHarmful
    -- convert to vector3 is better?
    o.lightingBlue = i.lightingBlue
    o.lightingGreen = i.lightingGreen
    o.lightingRed = i.lightingRed
    o.name = i.name
    o.nonRecastable = i.nonRecastable
    o.particleTexture = i.particleTexture
    o.school =  enumname.magicSchool(i.school)
    o.size = i.size
    o.sizeCap = i.sizeCap
    o.skill = enumname.skill(i.skill)
    o.speed = i.speed
    o.spellFailureSoundEffect = this.tes3sound(i.spellFailureSoundEffect)
    o.targetsAttributes = i.targetsAttributes
    o.targetsSkills = i.targetsSkills
    o.unreflectable = i.unreflectable
    o.usesNegativeLighting = i.usesNegativeLighting

    local _ = ValidateType(o)
    return o
end

---@param i tes3misc?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3misc(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.isGold = i.isGold
    o.isKey = i.isKey
    o.isSoulGem = i.isSoulGem
    o.script = this.tes3script(i.script)
    o.soulGemCapacity = i.soulGemCapacity
    -- o.soulGemData = i.soulGemData -- TODO
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileActor?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobileActor(i, o)
    if not i then
        return nil
    end
    o = tes3mobileObject(i, o)
    if not o then
        return nil
    end

    -- o.actionBeforeCombat = i.actionBeforeCombat -- TODO
    -- o.actionData = i.actionData -- TODO
    o.activeAI = i.activeAI
    -- o.activeMagicEffectList = i.activeMagicEffectList -- TODO
    o.actorType = enumname.actorType(i.actorType)
    o.agility = this.tes3statistic(i.agility)
    -- o.aiPlanner = i.aiPlanner -- TODO
    o.alarm = i.alarm
    -- o.animationController = i.animationController -- TODO
    o.armorRating = i.armorRating
    o.attackBonus = i.attackBonus
    o.attacked = i.attacked
    o.attributes = iter.ForEachObject(i.attributes, this.tes3statistic)
    o.barterGold = i.barterGold
    o.blind = i.blind
    o.canAct = i.canAct
    o.canJump = i.canJump
    o.canJumpMidair = i.canJumpMidair
    o.canMove = i.canMove
    -- o.cell = this.tes3cell(i.cell) -- TODO avoid circular reference
    o.chameleon = i.chameleon
    -- o.collidingReference = this.tes3reference(i.collidingReference)
    -- o.combatSession = i.combatSession -- TODO
    o.corpseHourstamp = i.corpseHourstamp
    -- o.currentEnchantedItem = i.currentEnchantedItem -- TODO
    -- o.currentSpell = i.currentSpell -- TODO
    -- o.effectAttributes = jsonrpc.array(i.effectAttributes)
    o.encumbrance = this.tes3statistic(i.encumbrance)
    o.endurance = this.tes3statistic(i.endurance)
    o.facing = i.facing
    o.fatigue = this.tes3statistic(i.fatigue)
    o.fight = i.fight
    o.flee = i.flee
    -- o.friendlyActors = i.friendlyActors -- TODO
    o.friendlyFireHitCount = i.friendlyFireHitCount
    o.greetDuration = i.greetDuration
    o.greetTimer = i.greetTimer
    o.hasBlightDisease = i.hasBlightDisease
    o.hasCommonDisease = i.hasCommonDisease
    o.hasCorprusDisease = i.hasCorprusDisease
    o.hasFreeAction = i.hasFreeAction
    o.hasVampirism = i.hasVampirism
    o.health = this.tes3statistic(i.health)
    o.height = i.height
    o.hello = i.hello
    o.holdBreathTime = i.holdBreathTime
    -- o.hostileActors = i.hostileActors -- TODO
    o.idleAnim = i.idleAnim
    o.inCombat = i.inCombat
    o.intelligence = this.tes3statistic(i.intelligence)
    o.invisibility = i.invisibility
    o.isAttackingOrCasting = i.isAttackingOrCasting
    o.isCrittable = i.isCrittable
    o.isDead = i.isDead
    o.isDiseased = i.isDiseased
    o.isFalling = i.isFalling
    o.isFlying = i.isFlying
    o.isHitStunned = i.isHitStunned
    o.isJumping = i.isJumping
    o.isKnockedDown = i.isKnockedDown
    o.isKnockedOut = i.isKnockedOut
    o.isMovingBack = i.isMovingBack
    o.isMovingForward = i.isMovingForward
    o.isMovingLeft = i.isMovingLeft
    o.isMovingRight = i.isMovingRight
    o.isParalyzed = i.isParalyzed
    o.isPlayerDetected = i.isPlayerDetected
    o.isPlayerHidden = i.isPlayerHidden
    o.isReadyingWeapon = i.isReadyingWeapon
    o.isRunning = i.isRunning
    o.isSliding = i.isSliding
    o.isSneaking = i.isSneaking
    o.isSpeaking = i.isSpeaking
    o.isSwimming = i.isSwimming
    o.isTurningLeft = i.isTurningLeft
    o.isTurningRight = i.isTurningRight
    o.isWalking = i.isWalking
    o.jump = i.jump
    o.lastGroundZ = i.lastGroundZ
    o.levitate = i.levitate
    o.luck = this.tes3statistic(i.luck)
    o.magicka = this.tes3statistic(i.magicka)
    o.magickaMultiplier = this.tes3statistic(i.magickaMultiplier)
    o.nextActionWeight = i.nextActionWeight
    o.paralyze = i.paralyze
    o.personality = this.tes3statistic(i.personality)
    -- o.readiedAmmo = i.readiedAmmo -- TODO
    o.readiedAmmoCount = i.readiedAmmoCount
    -- o.readiedShield = i.readiedShield -- TODO
    -- o.readiedWeapon = i.readiedWeapon -- TODO
    -- o.resistBlightDisease = i.resistBlightDisease -- TODO
    o.resistCommonDisease = i.resistCommonDisease -- TODO
    o.resistCorprus = i.resistCorprus
    o.resistFire = i.resistFire
    o.resistFrost = i.resistFrost
    o.resistMagicka = i.resistMagicka
    o.resistNormalWeapons = i.resistNormalWeapons
    o.resistParalysis = i.resistParalysis
    o.resistPoison = i.resistPoison
    o.resistShock = i.resistShock
    o.sanctuary = i.sanctuary
    o.scanInterval = i.scanInterval
    o.scanTimer = i.scanTimer
    o.shield = i.shield
    o.silence = i.silence
    o.sound = i.sound -- magic effect sound
    o.speed = this.tes3statistic(i.speed)
    o.spellReadied = i.spellReadied
    o.strength = this.tes3statistic(i.strength)
    o.swiftSwim = i.swiftSwim
    o.talkedTo = i.talkedTo
    -- o.torchSlot = i.torchSlot -- TODO
    o.underwater = i.underwater
    o.waterBreathing = i.waterBreathing
    o.waterWalking = i.waterWalking
    o.weaponDrawn = i.weaponDrawn
    o.weaponReady = i.weaponReady
    o.werewolf = i.werewolf
    o.width = i.width
    o.willpower = this.tes3statistic(i.willpower)

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileCreature?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobileCreature(i, o)
    if not i then
        return nil
    end
    o = this.tes3mobileActor(i, o)
    if not o then
        return nil
    end

    o.combat = this.tes3statistic(i.combat)
    o.flySpeed = i.flySpeed
    o.magic = this.tes3statistic(i.magic)
    o.moveSpeed = i.moveSpeed
    -- o.object = this.tes3creature(i.object) -- TODO avoid circular reference
    o.runSpeed = i.runSpeed
    -- o.skills = iter.ForEach(i.skills, this.tes3statistic) -- TODO represent key=value
    o.stealth = this.tes3statistic(i.stealth)
    o.swimRunSpeed = i.swimRunSpeed
    o.swimSpeed = i.swimSpeed
    o.walkSpeed = i.walkSpeed

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileNPC?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobileNPC(i, o)
    if not i then
        return nil
    end
    o = this.tes3mobileActor(i, o)
    if not o then
        return nil
    end

    o.acrobatics = this.tes3statistic(i.acrobatics)
    o.alchemy = this.tes3statistic(i.alchemy)
    o.alteration = this.tes3statistic(i.alteration)
    o.armorer = this.tes3statistic(i.armorer)
    o.athletics = this.tes3statistic(i.athletics)
    o.axe = this.tes3statistic(i.axe)
    o.block = this.tes3statistic(i.block)
    o.bluntWeapon = this.tes3statistic(i.bluntWeapon)
    o.conjuration = this.tes3statistic(i.conjuration)
    o.destruction = this.tes3statistic(i.destruction)
    o.enchant = this.tes3statistic(i.enchant)
    o.flySpeed = i.flySpeed
    o.forceJump = i.forceJump
    o.forceMoveJump = i.forceMoveJump
    o.forceRun = i.forceRun
    o.forceSneak = i.forceSneak
    o.handToHand = this.tes3statistic(i.handToHand)
    o.heavyArmor = this.tes3statistic(i.heavyArmor)
    o.illusion = this.tes3statistic(i.illusion)
    o.lightArmor = this.tes3statistic(i.lightArmor)
    o.longBlade = this.tes3statistic(i.longBlade)
    o.marksman = this.tes3statistic(i.marksman)
    o.mediumArmor = this.tes3statistic(i.mediumArmor)
    o.mercantile = this.tes3statistic(i.mercantile)
    o.moveSpeed = i.moveSpeed
    o.mysticism = this.tes3statistic(i.mysticism)
    o.object = i.object
    o.restoration = this.tes3statistic(i.restoration)
    o.runSpeed = i.runSpeed
    o.security = this.tes3statistic(i.security)
    o.shortBlade = this.tes3statistic(i.shortBlade)
    -- o.skills = i.skills
    o.sneak = this.tes3statistic(i.sneak)
    o.spear = this.tes3statistic(i.spear)
    o.speechcraft = this.tes3statistic(i.speechcraft)
    o.swimRunSpeed = i.swimRunSpeed
    o.swimSpeed = i.swimSpeed
    o.unarmored = this.tes3statistic(i.unarmored)
    o.walkSpeed = i.walkSpeed

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobilePlayer?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobilePlayer(i, o)
    if not i then
        return nil
    end
    o = this.tes3mobileNPC(i, o)
    if not o then
        return nil
    end

    o.alwaysRun = i.alwaysRun
    -- o.animationController = i.animationController -- TODO
    o.attackDisabled = i.attackDisabled
    o.autoRun = i.autoRun
    o.birthsign = this.tes3birthsign(i.birthsign)
    o.bounty = i.bounty
    o.bountyData = this.tes3bountyData(i.bountyData)
    o.cameraHeight = i.cameraHeight
    o.castReady = i.castReady
    -- o.clawMultiplier = i.clawMultiplier -- TODO
    o.controlsDisabled = i.controlsDisabled
    -- o.dialogueList = i.dialogueList -- TODO
    o.firstPerson = this.tes3npc(i.firstPerson)
    -- o.firstPersonReference = this.tes3reference(i.firstPersonReference) -- TODO avoid circular reference
    o.inactivityTime = i.inactivityTime
    o.inJail = i.inJail
    o.is3rdPerson = i.is3rdPerson
    o.jumpingDisabled = i.jumpingDisabled
    -- o.knownWerewolf = i.knownWerewolf -- TODO
    o.lastUsedAlembic = this.tes3apparatus(i.lastUsedAlembic)
    o.lastUsedAmmoCount = i.lastUsedAmmoCount
    o.lastUsedCalcinator = this.tes3apparatus(i.lastUsedCalcinator)
    o.lastUsedMortar = this.tes3apparatus(i.lastUsedMortar)
    o.lastUsedRetort = this.tes3apparatus(i.lastUsedRetort)
    o.levelupPerSpecialization = jsonrpc.array(i.levelupPerSpecialization)
    o.levelUpProgress = i.levelUpProgress
    o.levelupsPerAttribute = jsonrpc.array(i.levelupsPerAttribute)
    o.magicDisabled = i.magicDisabled
    -- o.markLocation = i.markLocation --TODO
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

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileProjectile?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobileProjectile(i, o)
    if not i then
        return nil
    end
    o = tes3mobileObject(i, o)
    if not o then
        return nil
    end

    o.animTime = i.animTime
    o.attackSwing = i.attackSwing
    o.damage = i.damage
    o.expire = i.expire
    o.firingMobile = this.tes3anyObject(i.firingMobile) -- or just id, who is firing? other infos is not important.
    o.firingWeapon = this.tes3weapon(i.firingWeapon)
    o.initialSpeed = i.initialSpeed
    -- o.spellInstance = i.spellInstance -- TODO
    o.velocity = i.velocity

    local _ = ValidateType(o)
    return o
end

---@param i tes3mobileSpellProjectile?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3mobileSpellProjectile(i, o)
    if not i then
        return nil
    end
    o = this.tes3mobileProjectile(i, o)
    if not o then
        return nil
    end

    o.rotationSpeed = i.rotationSpeed
    -- o.spellInstance = i.spellInstance -- TODO
    o.spellInstanceSerial = i.spellInstanceSerial

    local _ = ValidateType(o)
    return o
end

---@param i tes3npc|tes3npcInstance|nil
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3npc(i, o)
    if not i then
        return nil
    end
    o = tes3actor(i, o)
    if not o then
        return nil
    end

    -- o.aiConfig = i.aiConfig -- TODO
    o.attributes = jsonrpc.array(i.attributes)
    o.autoCalc = i.autoCalc
    o.baseDisposition = i.baseDisposition
    o.class = this.tes3class(i.class)
    o.faction = this.tes3faction(i.faction)
    o.factionRank = i.factionRank
    o.fatigue = i.fatigue
    o.female = i.female
    o.health = i.health
    o.height = i.height
    o.isAttacked = i.isAttacked
    o.isEssential = i.isEssential
    o.isInstance = i.isInstance
    o.isRespawn = i.isRespawn
    o.level = i.level
    o.magicka = i.magicka
    o.mesh = i.mesh
    o.name = i.name
    o.race = this.tes3race(i.race)
    o.reputation = i.reputation
    o.script = this.tes3script(i.script)
    o.skills = jsonrpc.array(i.skills)
    o.soul = i.soul
    -- o.spells = i.spells -- TODO
    o.weight = i.weight

    if i.isInstance then
        ---@cast i tes3npcInstance
        o.baseObject = this.tes3npc(i.baseObject) -- almost values are same as between baseObject and instance?
        o.disposition = i.disposition
        o.isGuard = i.isGuard
        -- o.mobile = this.tes3anyObject(i.mobile) -- TODO avoid circular reference
        o.reference = this.tes3reference(i.reference)
    else
        ---@cast i tes3npc
        o.hair = this.tes3bodyPart(i.hair)
        o.head = this.tes3bodyPart(i.head)
    end

    local _ = ValidateType(o)
    return o
end

---@param i tes3pathGrid?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3pathGrid(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.granularity = i.granularity
    o.isLoaded = i.isLoaded
    o.nodeCount = i.nodeCount
    -- o.nodes = i.nodes -- TODO
    -- o.parentCell = this.tes3cell(i.parentCell) -- TODO avoid circular reference

    local _ = ValidateType(o)
    return o
end

---@param i tes3probe?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3probe(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.maxCondition = i.maxCondition
    o.quality = i.quality
    o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3quest?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3quest(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.dialogue = iter.ForEachObject(i.dialogue, this.tes3dialogue)
    o.info = iter.ForEachObject(i.info, this.tes3dialogueInfo)
    o.isActive = i.isActive
    o.isFinished = i.isFinished
    o.isStarted = i.isStarted

    local _ = ValidateType(o)
    return o
end

---@param i tes3race?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3race(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.abilities = i.abilities -- TODO
    -- o.baseAttributes = i.baseAttributes -- TODO
    o.description = i.description
    -- o.femaleBody = i.femaleBody -- TODO
    -- o.flags = i.flags
    -- o.height = i.height -- TODO
    o.isBeast = i.isBeast
    o.isPlayable = i.isPlayable
    -- o.maleBody = i.maleBody -- TODO
    o.name = i.name
    -- o.skillBonuses = i.skillBonuses -- TODO
    -- o.weight = i.weight -- TODO

    local _ = ValidateType(o)
    return o
end

---@param i tes3reference?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3reference(i, o)
    if not i then
        return nil
    end
    o = tes3object(i, o)
    if not o then
        return nil
    end

    o.activationReference = this.tes3reference(i.activationReference)
    -- o.animationData = i.animationData -- TODO
    -- o.attachments = i.attachments --TODO
    o.baseObject = tes3object(i.baseObject)
    -- o.bodyPartManager = i.bodyPartManager -- TODO
    o.cell = this.tes3cell(i.cell)
    -- o.context = i.context
    -- o.data = i.data
    -- o.destination = i.destination -- TODO
    o.facing = i.facing
    o.forwardDirection = i.forwardDirection
    o.hasNoCollision = i.hasNoCollision
    o.isDead = i.isDead
    o.isEmpty = i.isEmpty
    o.isLeveledSpawn = i.isLeveledSpawn
    o.isRespawn = i.isRespawn
    -- o.itemData = i.itemData -- TODO
    o.leveledBaseReference = this.tes3reference(i.leveledBaseReference)
    -- o.light = i.light
    -- o.lockNode = i.lockNode -- TODO
    o.mesh = i.mesh
    o.mobile = this.tes3anyObject(i.mobile)
    -- o.nextNode = i.nextNode
    -- o.nodeData = i.nodeData
    o.object = this.tes3anyObject(i.object)
    o.orientation = i.orientation
    o.position = i.position
    -- o.previousNode = i.previousNode
    o.rightDirection = i.rightDirection
    -- o.sceneNode = i.sceneNode
    -- o.sourceFormId = i.sourceFormId
    -- o.sourceModId = i.sourceModId
    o.stackSize = i.stackSize
    -- o.startingOrientation = i.startingOrientation
    -- o.startingPosition = i.startingPosition
    -- o.supportsLuaData = i.supportsLuaData
    -- o.targetFormId = i.targetFormId
    -- o.targetModId = i.targetModId
    -- o.tempData = i.tempData
    o.upDirection = i.upDirection

    local _ = ValidateType(o)
    return o
end

---@param i tes3region?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3region(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.name = i.name
    o.sleepCreature = this.tes3leveledCreature(i.sleepCreature)
    -- o.sounds = i.sounds -- TODO
    -- o.weather = i.weather -- TODO
    o.weatherChanceAsh = i.weatherChanceAsh
    o.weatherChanceBlight = i.weatherChanceBlight
    o.weatherChanceBlizzard = i.weatherChanceBlizzard
    o.weatherChanceClear = i.weatherChanceClear
    o.weatherChanceCloudy = i.weatherChanceCloudy
    o.weatherChanceFoggy = i.weatherChanceFoggy
    o.weatherChanceOvercast = i.weatherChanceOvercast
    o.weatherChanceRain = i.weatherChanceRain
    -- o.weatherChances = i.weatherChances
    o.weatherChanceSnow = i.weatherChanceSnow
    o.weatherChanceThunder = i.weatherChanceThunder

    local _ = ValidateType(o)
    return o
end

---@param i tes3repairTool?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3repairTool(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.maxCondition = i.maxCondition
    o.quality = i.quality
    o.script = this.tes3script(i.script)
    o.value = i.value
    o.weight = i.weight

    local _ = ValidateType(o)
    return o
end

---@param i tes3script?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3script(i, o)
    return nil -- no field
    --[[
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    -- o.byteCode = jsonrpc.array(i.byteCode)
    -- o.context = i.context
    -- o.floatVariableCount = i.floatVariableCount
    -- o.longVariableCount = i.longVariableCount
    -- o.shortVariableCount = i.shortVariableCount
    -- o.text = i.text -- access IO

    local _ = ValidateType(o)
    return o
    --]]
end

---@param i tes3skill?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3skill(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.actions = jsonrpc.array(i.actions) -- TODO naming
    o.attribute = enumname.attribute(i.attribute)
    o.description = i.description
    o.iconPath = i.iconPath
    o.id = enumname.skill(i.id)
    o.name = i.name
    o.specialization = enumname.specialization(i.specialization)

    local _ = ValidateType(o)
    return o
end

---@param i tes3sound?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3sound(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.filename = i.filename
    o.maxDistance = i.maxDistance
    o.minDistance = i.minDistance
    o.volume = i.volume

    local _ = ValidateType(o)
    return o
end

---@param i tes3soundGenerator?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3soundGenerator(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.creature = this.tes3creature(i.creature)
    o.sound = this.tes3sound(i.sound)
    o.type = enumname.soundGenType(i.type)

    local _ = ValidateType(o)
    return o
end

---@param i tes3spell?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3spell(i, o)
    if not i then
        return nil
    end
    o = tes3object(i, o)
    if not o then
        return nil
    end

    o.alwaysSucceeds = i.alwaysSucceeds
    o.autoCalc = i.autoCalc
    o.basePurchaseCost = i.basePurchaseCost
    o.castType = enumname.spellType(i.castType)
    -- o.effects = i.effects -- TODO
    -- o.flags = i.flags -- means?
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

    local _ = ValidateType(o)
    return o
end

---@param i tes3startScript?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3startScript(i, o)
    if not i then
        return nil
    end
    o = tes3baseObject(i, o)
    if not o then
        return nil
    end

    o.script = this.tes3script(i.script)

    local _ = ValidateType(o)
    return o
end

---@param i tes3static?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3static(i, o)
    if not i then
        return nil
    end
    o = tes3physicalObject(i, o)
    if not o then
        return nil
    end

    o.mesh = i.mesh

    local _ = ValidateType(o)
    return o
end

---@param i tes3weapon?
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3weapon(i, o)
    if not i then
        return nil
    end
    o = tes3item(i, o)
    if not o then
        return nil
    end

    o.chopMax = i.chopMax
    o.chopMin = i.chopMin
    o.enchantCapacity = i.enchantCapacity
    o.enchantment = this.tes3enchantment(i.enchantment)
    -- o.flags = i.flags
    o.hasDurability = i.hasDurability
    o.ignoresNormalWeaponResistance = i.ignoresNormalWeaponResistance
    o.isAmmo = i.isAmmo
    o.isMelee = i.isMelee
    o.isOneHanded = i.isOneHanded
    o.isProjectile = i.isProjectile
    o.isRanged = i.isRanged
    o.isSilver = i.isSilver
    o.isTwoHanded = i.isTwoHanded
    o.maxCondition = i.maxCondition
    o.reach = i.reach
    o.script = this.tes3script(i.script)
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

    local _ = ValidateType(o)
    return o
end

-- Tracks objects currently being serialized in the active call stack.
-- Weak keys avoid retaining MWSE userdata/tables after serialization ends.
-- The table is created at top-level entry and discarded when unwinding back
-- to depth 0, so each serialization request has isolated cycle state.
local serializationVisited = nil
local serializationDepth = 0

---@param i any
---@return MCP.AnyMap
local function CircularReferencePlaceholder(i)
    -- When a cycle is detected, return a minimal object instead of recursing.
    -- This keeps JSON valid and prevents stack overflow.
    local o = jsonrpc.object()
    o.circularReference = true

    -- id/objectType are optional diagnostics so callers can still identify
    -- what object was collapsed by cycle protection.
    -- Access is wrapped in pcall because some userdata fields may throw.
    local okId, id = pcall(function()
        return i.id
    end)
    if okId and id ~= nil then
        o.id = id
    end

    local okObjectType, objectType = pcall(function()
        return i.objectType
    end)
    if okObjectType and objectType ~= nil then
        o.objectType = enumname.objectType(objectType) or objectType
    end

    return o
end

---@param functionName string
---@param serializer fun(i:any, o:any):any
---@return fun(i:any, o:any):any
local function WrapSerializerWithVisited(functionName, serializer)
    return function(i, o)
        local isTopLevel = (serializationDepth == 0)
        if isTopLevel then
            serializationVisited = setmetatable({}, { __mode = "k" })
        end
        serializationDepth = serializationDepth + 1

        local ok, result = pcall(function()
        -- Preserve existing nil behavior of each serializer.
        if not i then
            return serializer(i, o)
        end

        local inputType = type(i)
        -- Cycle tracking is only needed for reference-like values.
        if inputType ~= "table" and inputType ~= "userdata" then
            return serializer(i, o)
        end

        -- Re-entrance on the same object means we hit a reference cycle.
        if serializationVisited and serializationVisited[i] then
            logger:trace("Detected circular reference in %s", functionName)
            return CircularReferencePlaceholder(i)
        end

        -- Mark before descending into child serializers.
        if serializationVisited then
            serializationVisited[i] = true
        end

        -- Protect the visited map cleanup even if serializer throws.
        local ok, result = pcall(serializer, i, o)

        -- Unmark on both success and failure paths.
        if serializationVisited then
            serializationVisited[i] = nil
        end

        if not ok then
            -- Re-throw original serializer error for normal upstream handling.
            error(result)
        end
        return result
        end)

        serializationDepth = serializationDepth - 1
        if serializationDepth == 0 then
            serializationVisited = nil
        end

        if not ok then
            error(result)
        end
        return result
    end
end

for name, fn in pairs(this) do
    if type(fn) == "function" and string.sub(name, 1, 4) == "tes3" then
        -- Wrap all public tes3 serializers so cycle protection is applied
        -- consistently across nested serializer calls.
        this[name] = WrapSerializerWithVisited(name, fn)
    end
end

local objectHandler = {
    ["activator"] = this.tes3activator,
    ["alchemy"] = this.tes3alchemy,
    ["ammunition"] = this.tes3weapon,
    ["apparatus"] = this.tes3apparatus,
    ["armor"] = this.tes3armor,
    ["birthsign"] = this.tes3birthsign,
    ["bodyPart"] = this.tes3bodyPart,
    ["book"] = this.tes3book,
    ["cell"] = this.tes3cell,
    ["class"] = this.tes3class,
    ["clothing"] = this.tes3clothing,
    ["container"] = this.tes3container,
    ["creature"] = this.tes3creature,
    ["dialogue"] = this.tes3dialogue,
    ["dialogueInfo"] = this.tes3dialogueInfo,
    ["door"] = this.tes3door,
    ["enchantment"] = this.tes3enchantment,
    ["faction"] = this.tes3faction,
    ["gmst"] = this.tes3gameSetting,
    ["ingredient"] = this.tes3ingredient,
    ["land"] = this.tes3land,
    ["landTexture"] = this.tes3landTexture,
    ["leveledCreature"] = this.tes3leveledCreature,
    ["leveledItem"] = this.tes3leveledItem,
    ["light"] = this.tes3light,
    ["lockpick"] = this.tes3lockpick,
    ["magicEffect"] = this.tes3magicEffect,
    ["miscItem"] = this.tes3misc,
    ["mobileActor"] = this.tes3mobileActor,
    ["mobileCreature"] = this.tes3mobileCreature,
    ["mobileNPC"] = this.tes3mobileNPC,
    ["mobilePlayer"] = this.tes3mobilePlayer,
    ["mobileProjectile"] = this.tes3mobileProjectile,
    ["mobileSpellProjectile"] = this.tes3mobileSpellProjectile,
    ["npc"] = this.tes3npc,
    ["pathGrid"] = this.tes3pathGrid,
    ["probe"] = this.tes3probe,
    ["quest"] = this.tes3quest,
    ["race"] = this.tes3race,
    ["reference"] = this.tes3reference,
    ["region"] = this.tes3region,
    ["repairItem"] = this.tes3repairTool,
    ["script"] = this.tes3script,
    ["skill"] = this.tes3skill,
    ["sound"] = this.tes3sound,
    ["soundGenerator"] = this.tes3soundGenerator,
    ["spell"] = this.tes3spell,
    ["startScript"] = this.tes3startScript,
    ["static"] = this.tes3static,
    ["weapon"] = this.tes3weapon,
}

---@param i tes3baseObject|tes3mobileObject?
---@param o MCP.AnyMap?
function this.tes3anyObject(i, o)
    if not i then
        return nil
    end
    local objectType = enumname.objectType(i.objectType)
    if not objectType then
        logger:error("Unknown object type: %s", i.objectType)
        return nil
    end
    local handler = objectHandler[objectType]
    if not handler then
        logger:warn("No serializer for object type: %s", objectType)
        return nil
    end
    --duck typing
    ---@diagnostic disable-next-line: param-type-mismatch
    return handler(i, o)
end

return this
