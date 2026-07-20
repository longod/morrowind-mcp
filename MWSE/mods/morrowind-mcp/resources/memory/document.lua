local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local pathutil = require("morrowind-mcp.core.pathutil")
local mcp = require("morrowind-mcp.core.mcp")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")
local datetime = require("morrowind-mcp.util.datetime")
local enumname = require("morrowind-mcp.tes3.enumname")

--- Shared constructors and constants for Memory resource JSON documents.
--- This module keeps the runtime document shape close to the Lua annotations in core.imemory.
local this = {}

this.schemaVersion = 1

---@type table<number, string>
local subjectTypeByObjectType = {}

--- Create every missing directory segment in a Windows-style path.
--- Debug dumps are written outside the normal resource root, so this avoids relying on MCP resource path helpers.
---@param directoryPath string
---@return boolean
local function EnsureDirectoryPath(directoryPath)
    local normalizedPath = string.gsub(directoryPath, "/", "\\")
    local prefix = ""
    local startIndex = 1
    if string.match(normalizedPath, "^%a:\\") then
        prefix = string.sub(normalizedPath, 1, 3)
        startIndex = 4
    end

    local currentPath = prefix
    for pathPart in string.gmatch(string.sub(normalizedPath, startIndex), "[^\\]+") do
        currentPath = currentPath .. pathPart .. "\\"
        if lfs.attributes(currentPath, "mode") ~= "directory" then
            pcall(lfs.mkdir, currentPath)
        end
        if lfs.attributes(currentPath, "mode") ~= "directory" then
            return false
        end
    end
    return true
end

--- Ensure the parent directory exists before writing one debug dump file.
---@param filePath string
---@return boolean
local function EnsureDirectoryForFile(filePath)
    local directoryPath = string.match(filePath, "^(.*\\)[^\\]*$")
    if not directoryPath then
        return true
    end
    return EnsureDirectoryPath(directoryPath)
end

--- Broad Memory document role used by clients to decide how to interpret the envelope.
---@enum MCP.MemoryDocumentType
local documentType = {
    index = "memory.index",
    entity = "memory.entity",
    collection = "memory.collection",
    observation = "memory.observation",
}
this.documentType = documentType

--- Cache behavior for Memory resource entries.
--- Live entries rebuild only after their owning module marks them dirty.
---@enum MCP.MemoryReadPolicy
local readPolicy = {
    live = "live",
    snapshot = "snapshot",
}
this.readPolicy = readPolicy

--- Boundary kind that identifies which loaded-game context a Memory document belongs to.
---@enum MCP.MemoryScopeKind
local scopeKind = {
    currentLoadedGame = "current_loaded_game",
}
this.scopeKind = scopeKind

--- Provenance category for the data inside a Memory document.
---@enum MCP.MemorySourceKind
local sourceKind = {
    event = "event",
    resource = "resource",
    file = "file",
    liveState = "live_state",
    -- Expected future examples: dialogue_event, ui_observation, snapshot_capture.
}
this.sourceKind = sourceKind

--- Domain-specific payload shape inside the common Memory document envelope.
---@enum MCP.MemoryDataType
local dataType = {
    memoryRoots = "memory_roots",
    playerSummary = "player_summary",
    journalEntries = "journal_entries",
    questEntries = "quest_entries",
    actorIndex = "actor_index",
    npcSummary = "npc_summary",
    creatureSummary = "creature_summary",
    -- Expected future examples: inventory_items, dialogue_topics, container_items, reference_location.
}
this.dataType = dataType

--- Relationship label used by Memory links between documents.
---@enum MCP.MemoryLinkRel
local linkRel = {
    self = "self",
    player = "player",
    journal = "journal",
    quests = "quests",
    actors = "actors",
    actor = "actor",
    -- Expected future examples: inventory, dialogue, container, reference, location.
}
this.linkRel = linkRel

--- Resolve a Memory subject type from a TES3 objectType enum value.
---@param objectType tes3.objectType?
---@return string?
function this.SubjectTypeFromObjectType(objectType)
    if objectType == nil then
        return nil
    end

    local subjectType = subjectTypeByObjectType[objectType]
    if subjectType then
        return subjectType
    end

    local objectTypeName = enumname.objectType(objectType)
    if not objectTypeName then
        return nil
    end
    subjectType = "tes3" .. objectTypeName
    subjectTypeByObjectType[objectType] = subjectType
    return subjectType
end

--- Resolve a Memory subject type from a TES3 object or reference-like value.
---@param object tes3object|tes3reference?
---@return string?
function this.SubjectTypeFromObject(object)
    if not object then
        return nil
    end
    if object.objectType == tes3.objectType.reference then
        return this.SubjectTypeFromReference(object)
    end
    if object.objectType ~= nil then
        return this.SubjectTypeFromObjectType(object.objectType)
    end

    return this.SubjectTypeFromReference(object)
end

--- Resolve a Memory subject type for an instance by using its base object instead of tes3reference.
---@param ref tes3reference?
---@return string?
function this.SubjectTypeFromReference(ref)
    if not ref then
        return nil
    end

    return this.SubjectTypeFromObject(ref.baseObject or ref.object)
end

--- Runtime constants for stable built-in Memory subject identifiers.
---@class MCP.MemorySubjectIds
---@field player string

---@type MCP.MemorySubjectIds
this.subjectId = {
    player = "player",
    -- Expected future examples: active_target, current_cell, opened_container.
}

--- Return JSON array links even when callers pass plain Lua tables or nil.
---@param links MCP.MemoryLink[]?
---@return MCP.MemoryLink[]
local function NormalizeLinks(links)
    if not links then
        return jsonrpc.array()
    end
    local mt = getmetatable(links)
    if mt and mt.__jsontype == "array" then
        return links
    end
    return jsonrpc.array(links)
end

--- Return a JSON object payload even when callers pass plain Lua tables or nil.
---@param data table?
---@return table
local function NormalizeData(data)
    if not data then
        return jsonrpc.object()
    end
    local mt = getmetatable(data)
    if mt and mt.__jsontype == "object" then
        return data
    end
    return jsonrpc.object(data)
end

--- Build a Memory timestamp using current UTC time and optional in-game time.
---@param inGameTime MCP.DateTimeInGame?
---@return MCP.MemoryTimestamp
function this.TimestampNow(inGameTime)
    return jsonrpc.object({
        system_time = datetime.ToISO8601(datetime.UTCNow()),
        in_game_time = inGameTime,
    })
end

--- Build a loaded-game scope marker shared by all Memory documents in the current save context.
---@param generation integer
---@param saveName string?
---@param playerName string?
---@return MCP.MemoryScope
function this.Scope(generation, saveName, playerName)
    return jsonrpc.object({
        kind = this.scopeKind.currentLoadedGame,
        generation = generation,
        save_name = saveName,
        player_name = playerName,
    })
end

--- Build a Memory subject identity for an in-game object or concept.
---@param tes3Type string
---@param id string|number
---@param title string?
---@param base MCP.MemorySubject?
---@return MCP.MemorySubject
function this.Subject(tes3Type, id, title, base)
    return jsonrpc.object({
        tes3_type = tes3Type,
        id = id,
        title = title,
        base = base,
    })
end

--- Build a lightweight relationship to another Memory or resource URI.
---@param rel MCP.MemoryLinkRel
---@param uri MCP.ResourceUri
---@param title string?
---@param description string?
---@return MCP.MemoryLink
function this.Link(rel, uri, title, description)
    return jsonrpc.object({
        rel = rel,
        uri = uri,
        title = title,
        description = description,
    })
end

--- Build provenance metadata for the source of a Memory document.
---@param kind MCP.MemorySourceKind
---@param uri MCP.ResourceUri?
---@param eventName string?
---@param description string?
---@return MCP.MemorySource
function this.Source(kind, uri, eventName, description)
    return jsonrpc.object({
        kind = kind,
        uri = uri,
        event = eventName,
        description = description,
    })
end

--- Build the common Memory document envelope around domain-specific data.
---@param type MCP.MemoryDocumentType
---@param dataType MCP.MemoryDataType
---@param title string
---@param data table?
---@param params MCP.MemoryDocumentParams?
---@return MCP.MemoryDocument
function this.Document(type, dataType, title, data, params)
    params = params or {}
    return jsonrpc.object({
        schema_version = this.schemaVersion,
        type = type,
        data_type = dataType,
        title = title,
        subject = params.subject,
        scope = params.scope,
        source = params.source,
        links = NormalizeLinks(params.links),
        observed_at = params.observed_at,
        updated_at = params.updated_at or this.TimestampNow(params.in_game_time),
        data = NormalizeData(data),
    })
end

--- Build an application/json virtual resource descriptor for a Memory document path.
---@param relativePath string
---@param title string
---@param description string
---@return MCP.Resource
function this.Descriptor(relativePath, title, description)
    local uri = pathutil.ToUri(relativePath, settings.uriScheme)
    return {
        name = relativePath,
        title = title,
        uri = uri,
        description = description,
        mimeType = mcp.mimeType.application_json,
        annotations = jsonrpc.Annotations(nil, nil, nil),
    }
end

--- Resource entry whose handler lazily builds and caches one Memory document.
---@class MCP.MemoryResourceEntry: MCP.ResourceEntry
---@field cache MCP.MemoryCacheState
---@field debugHandler (fun(desc: MCP.Resource): table[])? Optional handler used only when writing debug dump files.

--- Create a live Memory resource entry that rebuilds JSON only when marked dirty.
---@param descriptor MCP.Resource
---@param buildDocument fun(): MCP.MemoryDocument?
---@return MCP.MemoryResourceEntry
function this.LiveEntry(descriptor, buildDocument)
    ---@type MCP.MemoryCacheState
    local cache = {
        read_policy = this.readPolicy.live,
        dirty = true,
    }

    local indent = config.development.debug

    ---@type MCP.MemoryResourceEntry
    local entry = {
        descriptor = descriptor,
        handler = function(desc)
            if cache.dirty or not cache.cached_json then
                local memoryDocument = buildDocument()
                cache.cached_document = memoryDocument
                cache.cached_json = json.encode(memoryDocument, { indent = indent })
                cache.dirty = false
                cache.built_at = this.TimestampNow()
            end
            return { jsonrpc.TextResourceContents(desc.uri, cache.cached_json, desc.mimeType) }
        end,
        cache = cache,
    }
    return entry
end

--- Invalidate a live Memory entry so the next read rebuilds its JSON document.
---@param entry MCP.MemoryResourceEntry?
function this.MarkDirty(entry)
    if entry and entry.cache then
        entry.cache.dirty = true
    end
end

--- Save one Memory resource entry to a debug JSON file outside MCP resource discovery.
---@param entry MCP.MemoryResourceEntry
---@param rootDir string
---@return MCP.MemoryDebugSaveResult?
function this.SaveEntry(entry, rootDir)
    if not entry or not entry.descriptor or not entry.handler then
        return nil
    end

    local normalizedRootDir = string.gsub(rootDir or "", "/", "\\")
    if normalizedRootDir == "" then
        return nil
    end
    if not string.endswith(normalizedRootDir, "\\") then
        normalizedRootDir = normalizedRootDir .. "\\"
    end

    local filePath = pathutil.ToResourceFilePath(entry.descriptor.name, normalizedRootDir)
    if not filePath or not EnsureDirectoryForFile(filePath) then
        return nil
    end

    local handler = entry.debugHandler or entry.handler
    local contents = handler(entry.descriptor)
    local content = contents and contents[1]
    if not content or type(content.text) ~= "string" then
        return nil
    end

    local file = io.open(filePath, "wb")
    if not file then
        return nil
    end
    file:write(content.text)
    file:close()

    return jsonrpc.object({
        uri = entry.descriptor.uri,
        file_path = filePath,
        bytes = string.len(content.text),
    })
end

return this
