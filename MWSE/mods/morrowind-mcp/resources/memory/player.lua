local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local obj = require("morrowind-mcp.tes3.object")
local document = require("morrowind-mcp.resources.memory.document")
local enumname = require("morrowind-mcp.tes3.enumname")

--- Memory module for the single current player entity.
---@class MCP.Resources.Memory.Player: MCP.Resources.MemoryModule
---@field playerEntry MCP.MemoryResourceEntry
---@field progressionEntry MCP.MemoryResourceEntry
---@field vitalsEntry MCP.MemoryResourceEntry
---@field vitalsSnapshot MCP.AnyMap?
---@field progressionSnapshot MCP.AnyMap?
---@field charGenFinishedCallback fun(e: table)?
---@field damagedCallback fun(e: table)?
---@field damagedHandToHandCallback fun(e: table)?
---@field deathCallback fun(e: table)?
---@field levelUpCallback fun(e: table)?
---@field skillRaisedCallback fun(e: table)?
---@field simulatedCallback fun(e: table)?
local this = {}
setmetatable(this, { __index = base })

local vitalThreshold = 0.05

local playerDescriptor = document.Descriptor(
    "memory/player/index.json",
    "Player Memory",
    "Memory entity for the current player."
)
this.uri = playerDescriptor.uri

local progressionDescriptor = document.Descriptor(
    "memory/player/progression.json",
    "Player Progression Memory",
    "Current player level, attributes, and skills."
)

local vitalsDescriptor = document.Descriptor(
    "memory/player/vitals.json",
    "Player Vitals Memory",
    "Current player health, magicka, fatigue, and life state."
)

this.link = document.Link(document.linkRel.player, playerDescriptor.uri, playerDescriptor.title, playerDescriptor.description)
local progressionLink = document.Link(document.linkRel.progression, progressionDescriptor.uri, progressionDescriptor.title,
    progressionDescriptor.description)
local vitalsLink = document.Link(document.linkRel.vitals, vitalsDescriptor.uri, vitalsDescriptor.title, vitalsDescriptor.description)

--- Read fragile TES3 fields without letting menu or load-state errors break the Memory response.
---@param callback fun(): any
---@return any
local function ReadValue(callback)
    local ok, result = pcall(callback)
    if ok then
        return result
    end
    return nil
end

--- Read one statistic into primitive values suitable for change detection.
---@param statistic table?
---@return MCP.AnyMap?
local function StatisticSnapshot(statistic)
    if not statistic then
        return nil
    end
    return {
        base = statistic.base,
        current = statistic.current,
        normalized = statistic.normalized,
    }
end

--- Return whether a vital needs immediate publication despite the normal change threshold.
---@param previous MCP.AnyMap?
---@param current MCP.AnyMap?
---@return boolean
local function IsVitalBoundaryChanged(previous, current)
    if previous == nil or current == nil then
        return previous ~= current
    end
    if previous.base ~= current.base then
        return true
    end
    local wasEmpty = previous.current <= 0
    local isEmpty = current.current <= 0
    local wasFull = previous.normalized >= 1
    local isFull = current.normalized >= 1
    return wasEmpty ~= isEmpty or wasFull ~= isFull
end

--- Return whether a vital changed enough from the last published value to rebuild its live resource.
---@param previous MCP.AnyMap?
---@param current MCP.AnyMap?
---@return boolean
local function IsVitalChanged(previous, current)
    if IsVitalBoundaryChanged(previous, current) then
        return true
    end
    if previous == nil or current == nil then
        return false
    end
    return math.abs(previous.normalized - current.normalized) >= vitalThreshold
end

--- Return whether any primitive statistic value differs from the last published progression snapshot.
---@param previous MCP.AnyMap?
---@param current MCP.AnyMap?
---@return boolean
local function IsProgressionChanged(previous, current)
    if previous == nil or current == nil then
        return previous ~= current
    end
    for key, value in pairs(current) do
        if previous[key] ~= value then
            return true
        end
    end
    for key in pairs(previous) do
        if current[key] == nil then
            return true
        end
    end
    return false
end

--- Create the player entity module; it appears after game load and owns player child links.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Player
function this.new(params)
    params.publishOnLoaded = true
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_player" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Player
    instance.playerEntry = document.LiveEntry(playerDescriptor, function()
        return instance:BuildPlayerDocument()
    end)
    instance.progressionEntry = document.LiveEntry(progressionDescriptor, function()
        return instance:BuildProgressionDocument()
    end)
    instance.vitalsEntry = document.LiveEntry(vitalsDescriptor, function()
        return instance:BuildVitalsDocument()
    end)
    instance.entries = jsonrpc.array({
        instance.playerEntry,
        instance.progressionEntry,
        instance.vitalsEntry,
    })
    instance.links = jsonrpc.array({ this.link })
    return instance
end

--- Return the character generation lifecycle state without failing outside an initialized game.
---@return MCP.AnyMap
local function CharacterGenerationState()
    return jsonrpc.object({
        started = ReadValue(function() return tes3.isCharGenStarted() end) == true,
        running = ReadValue(function() return tes3.isCharGenRunning() end) == true,
        finished = ReadValue(function() return tes3.isCharGenFinished() end) == true,
    })
end

--- Return current player availability outside menus and before fully initialized mobile state.
---@param mobilePlayer table?
---@return boolean
local function IsAvailable(mobilePlayer)
    return ReadValue(function() return tes3.onMainMenu() end) ~= true and mobilePlayer ~= nil
end

--- Build a compact player Memory entity without embedding large linked collections.
---@return MCP.MemoryDocument
function this:BuildPlayerDocument()
    local playerReference = ReadValue(function() return tes3.player end)
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    -- The player reference owns the actor instance; firstPerson is only the rendered NPC.
    local playerObject = ReadValue(function() return playerReference and playerReference.object end)
    local race = ReadValue(function() return playerObject and playerObject["race"] end)
    local class = ReadValue(function() return playerObject and playerObject["class"] end)
    local subjectType = document.SubjectTypeFromObject(playerReference)
    local characterGeneration = CharacterGenerationState()
    local available = IsAvailable(mobilePlayer)
    local ready = available and characterGeneration.finished == true
    local data = jsonrpc.object({
        available = available,
        ready = ready,
        character_generation = characterGeneration,
        name = ready and ReadValue(function() return playerObject and playerObject["name"] end) or nil,
        race = ready and ReadValue(function() return race and race["name"] end) or nil,
        gender = ready and ReadValue(function() return playerObject and playerObject["female"] and "female" or "male" end) or nil,
        class = ready and ReadValue(function() return obj.tes3class(class) end) or nil,
        birthsign = ready and ReadValue(function() return mobilePlayer and mobilePlayer["birthsign"] and mobilePlayer.birthsign.name end) or nil,
    })
    local links = self.manager:GetLinksForParent(playerDescriptor.uri)
    table.insert(links, progressionLink)
    table.insert(links, vitalsLink)

    return document.Document(
        document.documentType.entity,
        document.dataType.playerSummary,
        playerDescriptor.title,
        data,
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            links = links,
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player state summary."),
        }
    )
end

--- Capture all current player attributes and skills using display names as stable JSON keys.
---@param mobilePlayer table?
---@return MCP.AnyMap attributes
---@return MCP.AnyMap skills
---@return MCP.AnyMap snapshot
local function ProgressionValues(mobilePlayer)
    local attributes = jsonrpc.object()
    local skills = jsonrpc.object()
    local snapshot = {}
    for index = 0, 7 do
        local name = enumname.attribute(index)
        local statistic = ReadValue(function() return mobilePlayer and mobilePlayer.attributes[index] end)
        if name and statistic then
            attributes[name] = obj.tes3statistic(statistic)
            snapshot["attribute:" .. index .. ":base"] = statistic.base
            snapshot["attribute:" .. index .. ":current"] = statistic.current
        end
    end
    for index = 0, 26 do
        local name = enumname.skill(index)
        local statistic = ReadValue(function() return mobilePlayer and mobilePlayer.skills[index] end)
        if name and statistic then
            skills[name] = obj.tes3statistic(statistic)
            snapshot["skill:" .. index .. ":base"] = statistic.base
            snapshot["skill:" .. index .. ":current"] = statistic.current
        end
    end
    return attributes, skills, snapshot
end

--- Build the lower-frequency player level, attribute, and skill resource.
---@return MCP.MemoryDocument
function this:BuildProgressionDocument()
    local playerReference = ReadValue(function() return tes3.player end)
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    local attributes, skills, snapshot = ProgressionValues(mobilePlayer)
    snapshot.level = ReadValue(function() return mobilePlayer and mobilePlayer.level end)
    self.progressionSnapshot = snapshot
    local subjectType = document.SubjectTypeFromObject(playerReference)
    return document.Document(document.documentType.entity, document.dataType.playerProgression, progressionDescriptor.title,
        jsonrpc.object({
            available = IsAvailable(mobilePlayer),
            level = snapshot.level,
            attributes = attributes,
            skills = skills,
        }), {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player progression state."),
        })
end

--- Read the three player vital statistics into a compact comparison snapshot.
---@param mobilePlayer table?
---@return MCP.AnyMap
local function VitalValues(mobilePlayer)
    return {
        health = StatisticSnapshot(ReadValue(function() return mobilePlayer and mobilePlayer.health end)),
        magicka = StatisticSnapshot(ReadValue(function() return mobilePlayer and mobilePlayer.magicka end)),
        fatigue = StatisticSnapshot(ReadValue(function() return mobilePlayer and mobilePlayer.fatigue end)),
    }
end

--- Build the frequently changing player vital state resource.
---@return MCP.MemoryDocument
function this:BuildVitalsDocument()
    local playerReference = ReadValue(function() return tes3.player end)
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    self.vitalsSnapshot = VitalValues(mobilePlayer)
    local subjectType = document.SubjectTypeFromObject(playerReference)
    return document.Document(document.documentType.entity, document.dataType.playerVitals, vitalsDescriptor.title,
        jsonrpc.object({
            available = IsAvailable(mobilePlayer),
            alive = ReadValue(function() return playerReference and playerReference.isDead ~= true end),
            health = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer.health end)),
            magicka = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer.magicka end)),
            fatigue = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer.fatigue end)),
        }), {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player vital state."),
        })
end

--- Mark the vital resource dirty when game logic has moved it beyond its published threshold.
function this:CheckVitals()
    if self.vitalsEntry.cache.dirty then
        return
    end
    local current = VitalValues(ReadValue(function() return tes3.mobilePlayer end))
    for name, statistic in pairs(current) do
        if IsVitalChanged(self.vitalsSnapshot and self.vitalsSnapshot[name], statistic) then
            document.MarkDirty(self.vitalsEntry)
            return
        end
    end
end

--- Mark the progression resource dirty when any published level, attribute, or skill value changed.
function this:CheckProgression()
    if self.progressionEntry.cache.dirty then
        return
    end
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    local _, _, current = ProgressionValues(mobilePlayer)
    current.level = ReadValue(function() return mobilePlayer and mobilePlayer.level end)
    if IsProgressionChanged(self.progressionSnapshot, current) then
        document.MarkDirty(self.progressionEntry)
    end
end

--- Mark all player resources dirty after character generation finalizes identity and statistics.
function this:OnCharGenFinished()
    self:MarkDirty()
end

--- Invalidate player vitals after health damage, fatigue damage, or death events target the player.
---@param e table?
function this:OnVitalEvent(e)
    if e and e.reference == ReadValue(function() return tes3.player end) then
        document.MarkDirty(self.vitalsEntry)
    end
end

--- Invalidate progression when MWSE reports an earned level or skill increase.
function this:OnProgressionEvent()
    document.MarkDirty(self.progressionEntry)
end

--- Poll only clean live entries after game logic to cover mod, potion, and magic changes without dedicated events.
function this:OnSimulated()
    self:CheckVitals()
    self:CheckProgression()
end

--- Register player-only event invalidators and the simulated fallback after base loaded handling.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.simulatedCallback then
        return
    end
    self.charGenFinishedCallback = function(e) self:OnCharGenFinished() end
    self.damagedCallback = function(e) self:OnVitalEvent(e) end
    self.damagedHandToHandCallback = function(e) self:OnVitalEvent(e) end
    self.deathCallback = function(e) self:OnVitalEvent(e) end
    self.levelUpCallback = function(e) self:OnProgressionEvent() end
    self.skillRaisedCallback = function(e) self:OnProgressionEvent() end
    self.simulatedCallback = function(e) self:OnSimulated() end
    event.register(tes3.event.charGenFinished, self.charGenFinishedCallback)
    event.register(tes3.event.damaged, self.damagedCallback)
    event.register(tes3.event.damagedHandToHand, self.damagedHandToHandCallback)
    event.register(tes3.event.death, self.deathCallback)
    event.register(tes3.event.levelUp, self.levelUpCallback)
    event.register(tes3.event.skillRaised, self.skillRaisedCallback)
    event.register(tes3.event.simulated, self.simulatedCallback)
end

--- Unregister all player-specific handlers before releasing the Memory module.
function this:UnregisterEvent()
    local callbacks = {
        { tes3.event.charGenFinished, "charGenFinishedCallback" },
        { tes3.event.damaged, "damagedCallback" },
        { tes3.event.damagedHandToHand, "damagedHandToHandCallback" },
        { tes3.event.death, "deathCallback" },
        { tes3.event.levelUp, "levelUpCallback" },
        { tes3.event.skillRaised, "skillRaisedCallback" },
        { tes3.event.simulated, "simulatedCallback" },
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

--- Player links change only when a child module under the player resource becomes visible or hidden.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
    if module.parentUri == playerDescriptor.uri then
        document.MarkDirty(self.playerEntry)
    end
end

return this
