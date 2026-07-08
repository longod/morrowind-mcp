local this = {}
local bit = require("bit")

local logger = require("morrowind-mcp.logger").Get({ moduleName = "tes3enum" })


-- This module intentionally exposes enum-specific functions while sharing internals.
-- Non-bitflag enums return a single canonical name (string|nil).
-- Bitflag enums return all matching names as string[].

---@type table<table, table<number, string>>
local _nameCacheByTable = {}
---@type table<table, table[]>
local _bitFlagEntryCacheByTable = {}
---@type table<table, string>
local _enumTableNameByTable = {}

-- Resolve a human-readable enum table name for diagnostics.
-- Cache the result because wrappers repeatedly pass the same tes3 enum tables.
---@param enumTable table
---@return string
local function GetEnumTableName(enumTable)
    local enumName = _enumTableNameByTable[enumTable]
    if enumName then
        return enumName
    end

    for k, v in pairs(tes3) do
        if v == enumTable then
            enumName = k
            _enumTableNameByTable[enumTable] = enumName
            return enumName
        end
    end

    enumName = "<unknown enum table>"
    _enumTableNameByTable[enumTable] = enumName
    return enumName
end

-- Build a value -> name cache for non-bitflag enums.
-- We collect and sort keys first because Lua `pairs()` traversal order is not stable.
-- Sorting guarantees deterministic canonical-name selection for duplicate numeric values.
---@param enumTable table
---@return table<number, string>
local function BuildNameCache(enumTable)
    local orderedKeys = {}
    for k, v in pairs(enumTable) do
        if type(k) == "string" and type(v) == "number" then
            table.insert(orderedKeys, k)
        end
    end
    if table.size(orderedKeys) == 0 then
        logger:error("BuildNameCache found no string->number entries for %s", GetEnumTableName(enumTable))
    end
    table.sort(orderedKeys)

    local nameCache = {}
    for _, k in ipairs(orderedKeys) do
        local v = enumTable[k]
        if nameCache[v] == nil then
            -- Keep the first name in sorted-key order for stable duplicate-value canonicalization.
            nameCache[v] = k
        end
    end
    return nameCache
end

-- Resolve a single canonical name for non-bitflag enums.
-- Returns nil when the table/value is invalid or no matching value exists.
---@param enumTable table
---@param value number
---@return string|nil
local function EnumName(enumTable, value)
    if type(enumTable) ~= "table" then
        logger:error("EnumName expected table, got %s", type(enumTable))
        return nil
    end
    -- allow nil
    if value == nil then
        return nil
    end
    if type(value) ~= "number" then
        logger:error("EnumName expected number for %s, got %s", GetEnumTableName(enumTable), type(value))
        return nil
    end

    local nameCache = _nameCacheByTable[enumTable]
    if not nameCache then
        nameCache = BuildNameCache(enumTable)
        _nameCacheByTable[enumTable] = nameCache
    end

    local name = nameCache[value]
    if name == nil then
        -- possible modding extend enum value, or invalid value
        logger:warn("EnumName found no mapping for %s value=%s", GetEnumTableName(enumTable), value)
    end
    return name
end

-- Precompute sortable bitflag entries for deterministic decode order.
-- Entries are ordered by numeric value, then by name for stable output.
---@param enumTable table
---@return table[]
local function BuildBitFlagEntries(enumTable)
    local entries = {}
    for k, v in pairs(enumTable) do
        if type(k) == "string" and type(v) == "number" then
            table.insert(entries, { name = k, value = v })
        end
    end
    if table.size(entries) == 0 then
        logger:error("BuildBitFlagEntries found no string->number entries for %s", GetEnumTableName(enumTable))
    end
    table.sort(entries, function(a, b)
        if a.value == b.value then
            return a.name < b.name
        end
        return a.value < b.value
    end)
    return entries
end

-- Decode a bitmask value into all matching bitflag names.
-- Returns an empty array for invalid input or when no flags match.
-- For value == 0, only explicit zero-valued flags are returned.
---@param enumTable table
---@param value number
---@return string[]|nil
local function BitFlagNames(enumTable, value)
    if type(enumTable) ~= "table" then
        logger:error("BitFlagNames expected table, got %s", type(enumTable))
        return nil
    end
    -- allow nil
    if value == nil then
        return nil
    end
    if type(value) ~= "number" then
        logger:error("BitFlagNames expected number for %s, got %s", GetEnumTableName(enumTable), type(value))
        return nil
    end

    local entries = _bitFlagEntryCacheByTable[enumTable]
    if not entries then
        entries = BuildBitFlagEntries(enumTable)
        _bitFlagEntryCacheByTable[enumTable] = entries
    end

    local names = {}
    local matchedMask = 0
    if value == 0 then
        for _, entry in ipairs(entries) do
            if entry.value == 0 then
                table.insert(names, entry.name)
            end
        end
        if table.size(names) == 0 then
            -- Keep this at debug level because many enums intentionally use 0 as
            -- an unnamed "no flags" state without defining a zero-valued alias.
            logger:debug("BitFlagNames found no explicit zero-valued flag for %s", GetEnumTableName(enumTable))
        end
        return names
    end

    for _, entry in ipairs(entries) do
        if entry.value ~= 0 and bit.band(value, entry.value) == entry.value then
            table.insert(names, entry.name)
            matchedMask = bit.bor(matchedMask, entry.value)
        end
    end
    if table.size(names) == 0 then
        logger:error("BitFlagNames found no flags for %s value=%s", GetEnumTableName(enumTable), value)
    elseif matchedMask ~= value then
        logger:error("BitFlagNames left unmatched bits for %s value=%s matched=%s", GetEnumTableName(enumTable), value, matchedMask)
    end
    return names
end

-- Bitflag decoders: a single numeric value can contain multiple names.
---@param value number
---@return string[]|nil
function this.actionFlag(value)
    return BitFlagNames(tes3.actionFlag, value)
end

---@param value number
---@return string|nil
function this.activeBodyPart(value)
    return EnumName(tes3.activeBodyPart, value)
end

---@param value number
---@return string|nil
function this.activeBodyPartLayer(value)
    return EnumName(tes3.activeBodyPartLayer, value)
end

---@param value number
---@return string|nil
function this.actorType(value)
    return EnumName(tes3.actorType, value)
end

---@param value number
---@return string|nil
function this.aiBehaviorState(value)
    return EnumName(tes3.aiBehaviorState, value)
end

---@param value number
---@return string|nil
function this.aiPackage(value)
    return EnumName(tes3.aiPackage, value)
end

---@param value number
---@return string|nil
function this.animationBodySection(value)
    return EnumName(tes3.animationBodySection, value)
end

---@param value number
---@return string|nil
function this.animationGroup(value)
    return EnumName(tes3.animationGroup, value)
end

-- animationStartFlag is used as bitmask flags in MWSE APIs.
---@param value number
---@return string[]|nil
function this.animationStartFlag(value)
    return BitFlagNames(tes3.animationStartFlag, value)
end

---@param value number
---@return string|nil
function this.animationState(value)
    return EnumName(tes3.animationState, value)
end

---@param value number
---@return string|nil
function this.apparatusType(value)
    return EnumName(tes3.apparatusType, value)
end

---@param value number
---@return string|nil
function this.armorSlot(value)
    return EnumName(tes3.armorSlot, value)
end

---@param value number
---@return string|nil
function this.armorWeightClass(value)
    return EnumName(tes3.armorWeightClass, value)
end

---@param value number
---@return string|nil
function this.attachmentType(value)
    return EnumName(tes3.attachmentType, value)
end

---@param value number
---@return string|nil
function this.attribute(value)
    -- tes3.attributeName is a pre-built number->string table; direct lookup avoids inversion.
    return tes3.attributeName[value]
end

---@param value number
---@return string|nil
function this.attributeName(value)
    return this.attribute(value)
end

---@param value number
---@return string|nil
function this.bodyPartAttachment(value)
    return EnumName(tes3.bodyPartAttachment, value)
end

---@param value number
---@return string|nil
function this.bookType(value)
    return EnumName(tes3.bookType, value)
end

---@param value number
---@return string|nil
function this.clothingSlot(value)
    return EnumName(tes3.clothingSlot, value)
end

---@param value number
---@return string|nil
function this.codePatchFeature(value)
    return EnumName(tes3.codePatchFeature, value)
end

---@param value number
---@return string|nil
function this.compilerSource(value)
    return EnumName(tes3.compilerSource, value)
end

---@deprecated broken function; use tes3.contentType directly
---@param value number
---@return string|nil
function this.contentType(value)
    return EnumName(tes3.contentType, value)
end

---@param value number
---@return string|nil
function this.creatureType(value)
    return EnumName(tes3.creatureType, value)
end

---@param value number
---@return string|nil
function this.crimeType(value)
    return EnumName(tes3.crimeType, value)
end

---@param value number
---@return string|nil
function this.damageSource(value)
    return EnumName(tes3.damageSource, value)
end

---@param value number
---@return string|nil
function this.dialogueFilterContext(value)
    return EnumName(tes3.dialogueFilterContext, value)
end

---@param value number
---@return string|nil
function this.dialoguePage(value)
    return EnumName(tes3.dialoguePage, value)
end

---@param value number
---@return string|nil
function this.dialogueType(value)
    return EnumName(tes3.dialogueType, value)
end

---@param value number
---@return string|nil
function this.effect(value)
    return EnumName(tes3.effect, value)
end

---@param value number
---@return string|nil
function this.effectAttribute(value)
    return EnumName(tes3.effectAttribute, value)
end

---@param value number
---@return string|nil
function this.effectEventType(value)
    return EnumName(tes3.effectEventType, value)
end

---@param value number
---@return string|nil
function this.effectRange(value)
    return EnumName(tes3.effectRange, value)
end

---@param value number
---@return string|nil
function this.enchantmentType(value)
    return EnumName(tes3.enchantmentType, value)
end

---@param value number
---@return string|nil
function this.event(value)
    return EnumName(tes3.event, value)
end

---@param value number
---@return string|nil
function this.flowDirection(value)
    return EnumName(tes3.flowDirection, value)
end

---@param value number
---@return string|nil
function this.gmst(value)
    return EnumName(tes3.gmst, value)
end

---@param value number
---@return string|nil
function this.inventorySelectFilter(value)
    return EnumName(tes3.inventorySelectFilter, value)
end

---@param value number
---@return string|nil
function this.inventoryTileType(value)
    return EnumName(tes3.inventoryTileType, value)
end

---@param value number
---@return string|nil
function this.itemSoundState(value)
    return EnumName(tes3.itemSoundState, value)
end

---@param value number
---@return string|nil
function this.justifyText(value)
    return EnumName(tes3.justifyText, value)
end

---@param value number
---@return string|nil
function this.keybind(value)
    return EnumName(tes3.keybind, value)
end

---@param value number
---@return string|nil
function this.keyboardCode(value)
    return EnumName(tes3.keyboardCode, value)
end

---@param value number
---@return string|nil
function this.keyTransition(value)
    return EnumName(tes3.keyTransition, value)
end

---@param value number
---@return string|nil
function this.language(value)
    return EnumName(tes3.language, value)
end

---@param value number
---@return string|nil
function this.languageCode(value)
    return EnumName(tes3.languageCode, value)
end

---@param value number
---@return string|nil
function this.magicSchool(value)
    return EnumName(tes3.magicSchool, value)
end

---@param value number
---@return string|nil
function this.magicSourceType(value)
    return EnumName(tes3.magicSourceType, value)
end

---@param value number
---@return string[]|nil
function this.merchantService(value)
    return BitFlagNames(tes3.merchantService, value)
end

---@param value number
---@return string|nil
function this.musicSituation(value)
    return EnumName(tes3.musicSituation, value)
end

---@param value number
---@return string|nil
function this.niType(value)
    return EnumName(tes3.niType, value)
end

---@param value number
---@return string|nil
function this.objectType(value)
    return EnumName(tes3.objectType, value)
end

---@param value number
---@return string|nil
function this.palette(value)
    return EnumName(tes3.palette, value)
end

---@param value number
---@return string|nil
function this.partIndex(value)
    return EnumName(tes3.partIndex, value)
end

---@param value number
---@return string|nil
function this.physicalAttackType(value)
    return EnumName(tes3.physicalAttackType, value)
end

---@param value number
---@return string|nil
function this.quickKeyType(value)
    return EnumName(tes3.quickKeyType, value)
end

---@param value number
---@return string|nil
function this.scanCode(value)
    return EnumName(tes3.scanCode, value)
end

---@param value number
---@return string|nil
function this.scanCodeToNumber(value)
    return EnumName(tes3.scanCodeToNumber, value)
end

---@param value number
---@return string|nil
function this.skill(value)
    -- tes3.skillName is a pre-built number->string table with display names (e.g. "Medium Armor").
    -- Direct lookup avoids inversion and returns human-readable names.
    return tes3.skillName[value]
end

---@param value number
---@return string|nil
function this.skillName(value)
    return this.skill(value)
end

---@param value number
---@return string|nil
function this.skillRaiseSource(value)
    return EnumName(tes3.skillRaiseSource, value)
end

---@param value number
---@return string|nil
function this.skillType(value)
    return EnumName(tes3.skillType, value)
end

---@param value number
---@return string|nil
function this.soundGenType(value)
    return EnumName(tes3.soundGenType, value)
end

---@param value number
---@return string|nil
function this.soundMix(value)
    return EnumName(tes3.soundMix, value)
end

---@param value number
---@return string|nil
function this.specialization(value)
    -- tes3.specializationName is a pre-built number->string table; direct lookup avoids inversion.
    return tes3.specializationName[value]
end

---@param value number
---@return string|nil
function this.specializationName(value)
    return this.specialization(value)
end

---@param value number
---@return string|nil
function this.spellSource(value)
    return EnumName(tes3.spellSource, value)
end

---@param value number
---@return string|nil
function this.spellState(value)
    return EnumName(tes3.spellState, value)
end

---@param value number
---@return string|nil
function this.spellType(value)
    return EnumName(tes3.spellType, value)
end

---@deprecated broken function; use tes3.uiElementType directly
---@param value number
---@return string|nil
function this.uiElementType(value)
    return EnumName(tes3.uiElementType, value)
end

---@param value number
---@return string|nil
function this.uiEvent(value)
    return EnumName(tes3.uiEvent, value)
end

---@param value number
---@return string|nil
function this.uiProperty(value)
    return EnumName(tes3.uiProperty, value)
end

---@param value number
---@return string[]|nil
function this.uiState(value)
    return BitFlagNames(tes3.uiState, value)
end

---@param value number
---@return string|nil
function this.vfxContext(value)
    return EnumName(tes3.vfxContext, value)
end

---@param value number
---@return string|nil
function this.voiceover(value)
    return EnumName(tes3.voiceover, value)
end

---@param value number
---@return string|nil
function this.weaponType(value)
    return EnumName(tes3.weaponType, value)
end

---@param value number
---@return string|nil
function this.weather(value)
    return EnumName(tes3.weather, value)
end


return this
