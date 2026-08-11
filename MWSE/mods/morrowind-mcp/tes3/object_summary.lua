local config = require("morrowind-mcp.config")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local object = require("morrowind-mcp.tes3.object")
local enumname = require("morrowind-mcp.tes3.enumname")
local iter = require("morrowind-mcp.tes3.iterator")
local distanceutil = require("morrowind-mcp.util.distance")

---@diagnostic disable: need-check-nil, undefined-field

--- Request-scoped serializer for shallow exploration-oriented TES3 object output.
---@class MCP.TES3.ObjectSummarySerializer
---@field detailLevel "minimal"|"standard"|"full"
---@field origin tes3vector3?
---@field stack table<any, boolean>
local this = {}

this.level = {
    minimal = "minimal",
    standard = "standard",
    full = "full",
}

-- Keep this manifest aligned with object.lua so a missing extension point is visible in tests.
this.supportedMethods = {
    "tes3bountyData",
    "tes3fader",
    "tes3itemData",
    "tes3inventoryTile",
    "tes3statistic",
    "tes3weather",
    "tes3weatherController",
    "tes3worldController",
    "tes3travelDestinationNode",
    "tes3globalVariable",
    "tes3effect",
    "tes3soulGemData",
    "tes3activator",
    "tes3alchemy",
    "tes3apparatus",
    "tes3armor",
    "tes3birthsign",
    "tes3bodyPart",
    "tes3book",
    "tes3cell",
    "tes3class",
    "tes3clothing",
    "tes3container",
    "tes3creature",
    "tes3dialogue",
    "tes3dialogueInfo",
    "tes3door",
    "tes3enchantment",
    "tes3faction",
    "tes3gameSetting",
    "tes3ingredient",
    "tes3land",
    "tes3landTexture",
    "tes3leveledCreature",
    "tes3leveledItem",
    "tes3light",
    "tes3lockpick",
    "tes3magicEffect",
    "tes3misc",
    "tes3mobileActor",
    "tes3mobileCreature",
    "tes3mobileNPC",
    "tes3mobilePlayer",
    "tes3mobileProjectile",
    "tes3mobileSpellProjectile",
    "tes3npc",
    "tes3pathGrid",
    "tes3probe",
    "tes3quest",
    "tes3race",
    "tes3reference",
    "tes3region",
    "tes3repairTool",
    "tes3script",
    "tes3skill",
    "tes3sound",
    "tes3soundGenerator",
    "tes3spell",
    "tes3startScript",
    "tes3static",
    "tes3weapon",
    "tes3anyObject",
}

---@param params { detailLevel: "minimal"|"standard"|"full"?, origin: tes3vector3? }?
---@return MCP.TES3.ObjectSummarySerializer
function this.new(params)
    params = params or {}
    local detailLevel = params.detailLevel or this.level.minimal
    if detailLevel ~= this.level.minimal and detailLevel ~= this.level.standard and detailLevel ~= this.level.full then
        error("Unknown detail level: " .. tostring(detailLevel))
    end
    local instance = {
        detailLevel = detailLevel,
        origin = params.origin,
        stack = setmetatable({}, { __mode = "k" }),
    }
    return setmetatable(instance, {
        __index = function(serializer, key)
            local summaryMethod = this[key]
            local fullMethod = object[key]
            local fullMethodMetatable = type(fullMethod) == "table" and getmetatable(fullMethod) or nil
            if serializer.detailLevel == this.level.full and type(key) == "string" and key:sub(1, 4) == "tes3" and
                (type(fullMethod) == "function" or (fullMethodMetatable and type(fullMethodMetatable.__call) == "function")) then
                return function(_, value)
                    return fullMethod(value)
                end
            end
            return summaryMethod
        end,
    })
end

---@return boolean
function this:IsStandard()
    return self.detailLevel == this.level.standard
end

---@return boolean
function this:IsFull()
    return self.detailLevel == this.level.full
end

---@return MCP.AnyMap
function this:GetMetadata()
    return jsonrpc.object({
        detailLevel = self.detailLevel,
        availableDetailLevels = jsonrpc.array({ self.level.minimal, self.level.standard, self.level.full }),
    })
end

--- Validate generated JSON values without suppressing any TES3 property read errors.
---@param value any
---@param path string
---@param ancestors table<any, boolean>
---@return nil
local function ValidateJsonValue(value, path, ancestors)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" or valueType == "string" then
        return
    end
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("Invalid JSON number at " .. path)
        end
        return
    end
    if valueType == "userdata" then
        local ok, metatable = pcall(getmetatable, value)
        if not ok or type(metatable) ~= "table" or type(metatable.__tojson) ~= "function" then
            error("Invalid JSON userdata at " .. path)
        end
        return
    end
    if valueType ~= "table" then
        error("Invalid JSON value of type " .. valueType .. " at " .. path)
    end
    if ancestors[value] then
        error("Circular JSON table at " .. path)
    end
    ancestors[value] = true
    for key, child in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            error("Invalid JSON key at " .. path)
        end
        ValidateJsonValue(child, path .. "." .. tostring(key), ancestors)
    end
    ancestors[value] = nil
end

---@param methodName string
---@param output MCP.AnyMap?
---@return MCP.AnyMap?
function this:Finish(methodName, output)
    if output and config.development.debug then
        ValidateJsonValue(output, methodName, {})
    end
    return output
end

---@param value tes3baseObject?
---@return MCP.AnyMap?
function this:BaseObject(value)
    if not value then
        return nil
    end
    if value.isValid and not value:isValid() then
        return nil
    end
    if value.deleted or value.disabled then
        return nil
    end
    return jsonrpc.object({
        id = value.id,
        objectType = enumname.objectType(value.objectType),
        supportsActivate = value.supportsActivate == true or nil,
    })
end

---@param value tes3baseObject?
---@return MCP.AnyMap?
function this:ObjectSummary(value)
    local output = self:BaseObject(value)
    if not output then
        return nil
    end
    output.name = value.name
    if self:IsStandard() then
        output.mesh = value.mesh
        output.scale = value.scale
    end
    return output
end

---@param value tes3item?
---@return MCP.AnyMap?
function this:ItemSummary(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.value = value.value
        output.weight = value.weight
    end
    return output
end

---@param cell tes3cell?
---@return MCP.AnyMap?
function this:CellSummary(cell)
    local output = self:BaseObject(cell)
    if not output then
        return nil
    end
    output.displayName = cell.displayName
    output.name = cell.name
    output.isInterior = cell.isInterior
    output.gridX = cell.gridX
    output.gridY = cell.gridY
    if self:IsStandard() then
        output.behavesAsExterior = cell.behavesAsExterior
        output.hasMapMarker = cell.hasMapMarker
        output.hasWater = cell.hasWater
        output.restingIsIllegal = cell.restingIsIllegal
        output.waterLevel = cell.waterLevel
    end
    return self:Finish("tes3cell", output)
end

---@param value tes3itemData?
---@return MCP.AnyMap?
function this:ItemDataSummary(value)
    if not value then
        return nil
    end
    return jsonrpc.object({
        charge = value.charge,
        condition = value.condition,
        count = value.count,
        timeLeft = value.timeLeft,
    })
end

---@param value tes3lockNode?
---@return MCP.AnyMap?
function this:LockSummary(value)
    if not value then
        return nil
    end
    return jsonrpc.object({
        locked = value.locked,
        level = value.level,
        key = self:ObjectSummary(value.key),
        trap = self:ObjectSummary(value.trap),
    })
end

---@param value tes3travelDestinationNode?
---@return MCP.AnyMap?
function this:DestinationSummary(value)
    if not value then
        return nil
    end
    return jsonrpc.object({
        cell = self:CellSummary(value.cell),
        marker = value.marker and jsonrpc.object({ id = value.marker.id, position = value.marker.position }) or nil,
    })
end

---@param reference tes3reference?
---@return MCP.AnyMap?
function this:Reference(reference)
    if not reference then
        return nil
    end
    if self:IsFull() then
        return object.tes3reference(reference)
    end
    if not reference:isValid() then
        return nil
    end
    if self.stack[reference] then
        return jsonrpc.object({ circularReference = true, id = reference.id })
    end

    self.stack[reference] = true
    local baseObject = reference.baseObject or reference.object
    local output = jsonrpc.object({
        id = reference.id,
        type = baseObject and enumname.objectType(baseObject.objectType) or nil,
        name = baseObject and baseObject.name or nil,
        position = reference.position,
        cell = self:CellSummary(reference.cell),
        supportsActivate = reference.supportsActivate == true or nil,
        isDead = reference.isDead,
        isEmpty = reference.isEmpty == true or nil,
        isLeveledSpawn = reference.isLeveledSpawn == true or nil,
        stackSize = reference.stackSize,
    })
    if self.origin and reference.position then
        local distanceUnits = self.origin:distance(reference.position)
        output.distance = jsonrpc.object({
            units = distanceUnits,
            meters = distanceutil.ToMeters(distanceUnits),
        })
    end
    if self:IsStandard() then
        output.facing = reference.facing
        output.forwardDirection = reference.forwardDirection
        output.hasNoCollision = reference.hasNoCollision == true or nil
        output.isRespawn = reference.isRespawn == true or nil
        output.destination = self:DestinationSummary(reference.destination)
        output.itemData = self:ItemDataSummary(reference.itemData)
        output.lockNode = self:LockSummary(reference.lockNode)
        output.object = self:AnyObject(baseObject)
    else
        output.hasDestination = reference.destination ~= nil or nil
        output.locked = reference.lockNode and reference.lockNode.locked or nil
    end
    self.stack[reference] = nil
    return self:Finish("tes3reference", output)
end

---@param value tes3baseObject?
---@return MCP.AnyMap?
function this:AnyObject(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3anyObject(value)
    end
    local objectType = enumname.objectType(value.objectType)
    if not objectType then
        error("Unknown TES3 object type: " .. tostring(value.objectType))
    end
    local handler = self["tes3" .. objectType]
    if not handler then
        error("Missing summary serializer for TES3 object type: " .. objectType)
    end
    return handler(self, value)
end

---@param value tes3container?
---@return MCP.AnyMap?
function this:tes3container(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.capacity = value.capacity
        output.organic = value.organic
        output.respawns = value.respawns
    end
    return self:Finish("tes3container", output)
end

---@param value tes3creature?
---@return MCP.AnyMap?
function this:tes3creature(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.level = value.level
        output.health = value.health
        output.magicka = value.magicka
        output.fatigue = value.fatigue
        output.isEssential = value.isEssential
        output.walks = value.walks
        output.swims = value.swims
        output.flies = value.flies
        output.usesEquipment = value.usesEquipment
        output.soul = value.soul
    end
    return self:Finish("tes3creature", output)
end

---@param value tes3npc?
---@return MCP.AnyMap?
function this:tes3npc(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.class = self:ObjectSummary(value.class)
        output.faction = self:ObjectSummary(value.faction)
        output.factionRank = value.factionRank
        output.race = self:ObjectSummary(value.race)
        output.disposition = value.disposition
        output.isEssential = value.isEssential
        output.isGuard = value.isGuard
        output.level = value.level
        output.reputation = value.reputation
        output.health = value.health
        output.magicka = value.magicka
        output.fatigue = value.fatigue
    end
    return self:Finish("tes3npc", output)
end

---@param value tes3weapon?
---@return MCP.AnyMap?
function this:tes3weapon(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.maxCondition = value.maxCondition
        output.type = enumname.weaponType(value.type)
        output.reach = value.reach
        output.chopMin = value.chopMin
        output.chopMax = value.chopMax
        output.slashMin = value.slashMin
        output.slashMax = value.slashMax
        output.thrustMin = value.thrustMin
        output.thrustMax = value.thrustMax
    end
    return self:Finish("tes3weapon", output)
end

---@param value tes3armor?
---@return MCP.AnyMap?
function this:tes3armor(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.maxCondition = value.maxCondition
        output.armorRating = value.armorRating
        output.slot = enumname.armorSlot(value.slot)
    end
    return self:Finish("tes3armor", output)
end

---@param value tes3clothing?
---@return MCP.AnyMap?
function this:tes3clothing(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.slot = enumname.clothingSlot(value.slot)
    end
    return self:Finish("tes3clothing", output)
end

---@param value tes3effect?
---@return MCP.AnyMap?
function this:EffectSummary(value)
    if not value then
        return nil
    end
    return jsonrpc.object({
        id = enumname.effect(value.id) or value.id,
        range = enumname.effectRange(value.rangeType),
        radius = value.radius,
        duration = value.duration,
        min = value.min,
        max = value.max,
        attribute = enumname.attribute(value.attribute),
        skill = enumname.skill(value.skill),
    })
end

---@param value tes3alchemy|tes3ingredient?
---@return MCP.AnyMap?
function this:ItemWithEffects(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.effects = iter.ForEachObject(value.effects, function(effect)
            return self:EffectSummary(effect)
        end)
    end
    return output
end

---@param value tes3alchemy?
---@return MCP.AnyMap?
function this:tes3alchemy(value)
    return self:Finish("tes3alchemy", self:ItemWithEffects(value))
end

---@param value tes3activator?
---@return MCP.AnyMap?
-- TODO Add activator-specific summary fields.
function this:tes3activator(value)
    return self:Finish("tes3activator", self:ObjectSummary(value))
end

---@param value tes3apparatus?
---@return MCP.AnyMap?
function this:tes3apparatus(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.quality = value.quality
        output.type = enumname.apparatusType(value.type)
    end
    return self:Finish("tes3apparatus", output)
end

---@param value tes3birthsign?
---@return MCP.AnyMap?
-- TODO Add birthsign-specific summary fields.
function this:tes3birthsign(value)
    return self:Finish("tes3birthsign", self:ObjectSummary(value))
end

---@param value tes3bodyPart?
---@return MCP.AnyMap?
-- TODO Add body part-specific summary fields.
function this:tes3bodyPart(value)
    return self:Finish("tes3bodyPart", self:ObjectSummary(value))
end

---@param value tes3book?
---@return MCP.AnyMap?
function this:tes3book(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.type = enumname.bookType(value.type)
        output.skill = enumname.skill(value.skill)
    end
    return self:Finish("tes3book", output)
end

---@param value tes3cell?
---@return MCP.AnyMap?
function this:tes3cell(value)
    return self:CellSummary(value)
end

---@param value tes3class?
---@return MCP.AnyMap?
-- TODO Add class-specific summary fields.
function this:tes3class(value)
    return self:Finish("tes3class", self:ObjectSummary(value))
end

---@param value tes3dialogue?
---@return MCP.AnyMap?
-- TODO Add dialogue-specific summary fields.
function this:tes3dialogue(value)
    return self:Finish("tes3dialogue", self:ObjectSummary(value))
end

---@param value tes3dialogueInfo?
---@return MCP.AnyMap?
-- TODO Add dialogue-info-specific summary fields.
function this:tes3dialogueInfo(value)
    return self:Finish("tes3dialogueInfo", self:ObjectSummary(value))
end

---@param value tes3door?
---@return MCP.AnyMap?
-- TODO Add door-specific summary fields.
function this:tes3door(value)
    return self:Finish("tes3door", self:ObjectSummary(value))
end

---@param value tes3enchantment?
---@return MCP.AnyMap?
-- TODO Add enchantment-specific summary fields.
function this:tes3enchantment(value)
    return self:Finish("tes3enchantment", self:ObjectSummary(value))
end

---@param value tes3faction?
---@return MCP.AnyMap?
-- TODO Add faction-specific summary fields.
function this:tes3faction(value)
    return self:Finish("tes3faction", self:ObjectSummary(value))
end

---@param value tes3gameSetting?
---@return MCP.AnyMap?
-- TODO Add game-setting-specific summary fields.
function this:tes3gameSetting(value)
    return self:Finish("tes3gameSetting", self:ObjectSummary(value))
end

---@param value tes3ingredient?
---@return MCP.AnyMap?
function this:tes3ingredient(value)
    return self:Finish("tes3ingredient", self:ItemWithEffects(value))
end

---@param value tes3land?
---@return MCP.AnyMap?
-- TODO Add land-specific summary fields.
function this:tes3land(value)
    return self:Finish("tes3land", self:ObjectSummary(value))
end

---@param value tes3landTexture?
---@return MCP.AnyMap?
-- TODO Add land-texture-specific summary fields.
function this:tes3landTexture(value)
    return self:Finish("tes3landTexture", self:ObjectSummary(value))
end

---@param value tes3leveledCreature?
---@return MCP.AnyMap?
function this:tes3leveledCreature(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.calculateFromAllLevels = value.calculateFromAllLevels
        output.chanceForNothing = value.chanceForNothing
        output.count = value.count
    end
    return self:Finish("tes3leveledCreature", output)
end

---@param value tes3leveledItem?
---@return MCP.AnyMap?
function this:tes3leveledItem(value)
    local output = self:ObjectSummary(value)
    if output and self:IsStandard() then
        output.calculateForEachItem = value.calculateForEachItem
        output.calculateFromAllLevels = value.calculateFromAllLevels
        output.chanceForNothing = value.chanceForNothing
        output.count = value.count
    end
    return self:Finish("tes3leveledItem", output)
end

---@param value tes3light?
---@return MCP.AnyMap?
function this:tes3light(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.radius = value.radius
        output.time = value.time
    end
    return self:Finish("tes3light", output)
end

---@param value tes3lockpick?
---@return MCP.AnyMap?
function this:tes3lockpick(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.maxCondition = value.maxCondition
        output.quality = value.quality
    end
    return self:Finish("tes3lockpick", output)
end

---@param value tes3magicEffect?
---@return MCP.AnyMap?
-- TODO Add magic-effect-specific summary fields.
function this:tes3magicEffect(value)
    ---@diagnostic disable-next-line: param-type-mismatch
    return self:Finish("tes3magicEffect", self:ObjectSummary(value))
end

---@param value tes3misc?
---@return MCP.AnyMap?
function this:tes3misc(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.isGold = value.isGold
        output.isKey = value.isKey
        output.isSoulGem = value.isSoulGem
        output.soulGemCapacity = value.soulGemCapacity
    end
    return self:Finish("tes3misc", output)
end

---@param value tes3pathGrid?
---@return MCP.AnyMap?
-- TODO Add path-grid-specific summary fields.
function this:tes3pathGrid(value)
    return self:Finish("tes3pathGrid", self:ObjectSummary(value))
end

---@param value tes3probe?
---@return MCP.AnyMap?
function this:tes3probe(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.quality = value.quality
    end
    return self:Finish("tes3probe", output)
end

---@param value tes3quest?
---@return MCP.AnyMap?
-- TODO Add quest-specific summary fields.
function this:tes3quest(value)
    return self:Finish("tes3quest", self:ObjectSummary(value))
end

---@param value tes3race?
---@return MCP.AnyMap?
-- TODO Add race-specific summary fields.
function this:tes3race(value)
    return self:Finish("tes3race", self:ObjectSummary(value))
end

---@param value tes3region?
---@return MCP.AnyMap?
-- TODO Add region-specific summary fields.
function this:tes3region(value)
    return self:Finish("tes3region", self:ObjectSummary(value))
end

---@param value tes3repairTool?
---@return MCP.AnyMap?
function this:tes3repairTool(value)
    local output = self:ItemSummary(value)
    if output and self:IsStandard() then
        output.maxCondition = value.maxCondition
        output.quality = value.quality
    end
    return self:Finish("tes3repairTool", output)
end

---@param value tes3script?
---@return MCP.AnyMap?
-- TODO Add script summary fields when script data is safe to expose.
function this:tes3script(value)
    return self:Finish("tes3script", nil)
end

---@param value tes3skill?
---@return MCP.AnyMap?
-- TODO Add skill-specific summary fields.
function this:tes3skill(value)
    return self:Finish("tes3skill", self:ObjectSummary(value))
end

---@param value tes3sound?
---@return MCP.AnyMap?
-- TODO Add sound-specific summary fields.
function this:tes3sound(value)
    return self:Finish("tes3sound", self:ObjectSummary(value))
end

---@param value tes3soundGenerator?
---@return MCP.AnyMap?
-- TODO Add sound-generator-specific summary fields.
function this:tes3soundGenerator(value)
    return self:Finish("tes3soundGenerator", self:ObjectSummary(value))
end

---@param value tes3spell?
---@return MCP.AnyMap?
-- TODO Add spell-specific summary fields.
function this:tes3spell(value)
    return self:Finish("tes3spell", self:ObjectSummary(value))
end

---@param value tes3startScript?
---@return MCP.AnyMap?
-- TODO Add start-script-specific summary fields.
function this:tes3startScript(value)
    return self:Finish("tes3startScript", self:ObjectSummary(value))
end

---@param value tes3static?
---@return MCP.AnyMap?
-- TODO Add static-specific summary fields.
function this:tes3static(value)
    return self:Finish("tes3static", self:ObjectSummary(value))
end

---@param value tes3bountyData?
---@return MCP.AnyMap?
-- TODO Add a summary-level bounty-data serializer.
function this:tes3bountyData(value)
    return object.tes3bountyData(value)
end

---@param value tes3fader?
---@return MCP.AnyMap?
-- TODO Add a summary-level fader serializer.
function this:tes3fader(value)
    return object.tes3fader(value)
end

---@param value tes3inventoryTile?
---@return MCP.AnyMap?
-- TODO Add a summary-level inventory-tile serializer.
function this:tes3inventoryTile(value)
    return object.tes3inventoryTile(value)
end

---@param value tes3statistic?
---@return MCP.AnyMap?
-- TODO Add a summary-level statistic serializer.
function this:tes3statistic(value)
    return object.tes3statistic(value)
end

---@param value tes3weather?
---@return MCP.AnyMap?
-- TODO Add a summary-level weather serializer.
function this:tes3weather(value)
    return object.tes3weather(value)
end

---@param value tes3weatherController?
---@return MCP.AnyMap?
-- TODO Add a summary-level weather-controller serializer.
function this:tes3weatherController(value)
    return object.tes3weatherController(value)
end

---@param value tes3worldController?
---@return MCP.AnyMap?
-- TODO Add a summary-level world-controller serializer.
function this:tes3worldController(value)
    return object.tes3worldController(value)
end

---@param value tes3travelDestinationNode?
---@return MCP.AnyMap?
function this:tes3travelDestinationNode(value)
    return self:DestinationSummary(value)
end

---@param value tes3globalVariable?
---@return number?
-- TODO Add a summary-level global-variable serializer.
function this:tes3globalVariable(value)
    return object.tes3globalVariable(value)
end

---@param value tes3effect?
---@return MCP.AnyMap?
-- TODO Reuse EffectSummary for summary-level effect serialization.
function this:tes3effect(value)
    return object.tes3effect(value)
end

---@param value tes3soulGemData?
---@return MCP.AnyMap?
-- TODO Add a summary-level soul-gem-data serializer.
function this:tes3soulGemData(value)
    return object.tes3soulGemData(value)
end

---@param value tes3itemData?
---@return MCP.AnyMap?
function this:tes3itemData(value)
    return self:ItemDataSummary(value)
end

---@param value tes3mobileActor?
---@return MCP.AnyMap?
function this:tes3mobileActor(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobileActor(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3mobileCreature?
---@return MCP.AnyMap?
function this:tes3mobileCreature(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobileCreature(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3mobileNPC?
---@return MCP.AnyMap?
function this:tes3mobileNPC(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobileNPC(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3mobilePlayer?
---@return MCP.AnyMap?
function this:tes3mobilePlayer(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobilePlayer(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3mobileProjectile?
---@return MCP.AnyMap?
function this:tes3mobileProjectile(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobileProjectile(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3mobileSpellProjectile?
---@return MCP.AnyMap?
function this:tes3mobileSpellProjectile(value)
    if not value then
        return nil
    end
    if self:IsFull() then
        return object.tes3mobileSpellProjectile(value)
    end
    return self:Reference(value.reference)
end

---@param value tes3reference?
---@return MCP.AnyMap?
function this:tes3reference(value)
    return self:Reference(value)
end

---@param value tes3baseObject|tes3mobileObject|nil
---@return MCP.AnyMap?
function this:tes3anyObject(value)
    return self:AnyObject(value)
end

return this
