local templates = require("morrowind-mcp.resources.templates")

--- Resource-template completion operates only on currently published resource URIs.
local this = {}

this.defaultResultLimit = 10
this.maxResultLimit = 100

---@class MCP.Resources.CompletionResult
---@field valid boolean
---@field errors string[]
---@field values string[]
---@field total integer
---@field hasMore boolean

--- Normalize an internal completion result limit without exposing it as user configuration.
---@param resultLimit any
---@return integer
function this.NormalizeResultLimit(resultLimit)
    if type(resultLimit) ~= "number" or resultLimit < 1 or math.floor(resultLimit) ~= resultLimit then
        return this.defaultResultLimit
    end
    return math.min(resultLimit, this.maxResultLimit)
end

---@param errors string[]
---@return MCP.Resources.CompletionResult
local function Invalid(errors)
    return {
        valid = false,
        errors = errors,
        values = {},
        total = 0,
        hasMore = false,
    }
end

--- Return a context argument only when it is a non-empty string.
---@param context any
---@param name string
---@return string?
local function ContextArgument(context, name)
    if type(context) ~= "table" or type(context.arguments) ~= "table" then
        return nil
    end
    local value = context.arguments[name]
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

--- Split a dynamic Memory entity URI into its three variable values.
---@param uri string
---@return string? collection
---@return string? entityId
---@return string? document
local function ParseMemoryEntityUri(uri)
    local prefix = "morrowind://memory/"
    if not string.startswith(uri, prefix) then
        return nil, nil, nil
    end

    local path = string.sub(uri, #prefix + 1)
    local firstSlash = string.find(path, "/", 1, true)
    if not firstSlash then
        return nil, nil, nil
    end
    local secondSlash = string.find(path, "/", firstSlash + 1, true)
    if not secondSlash or string.find(path, "/", secondSlash + 1, true) then
        return nil, nil, nil
    end

    local collection = string.sub(path, 1, firstSlash - 1)
    local entityId = string.sub(path, firstSlash + 1, secondSlash - 1)
    local fileName = string.sub(path, secondSlash + 1)
    local extension = ".json"
    if collection == "" or entityId == "" or not string.endswith(fileName, extension) then
        return nil, nil, nil
    end

    local document = string.sub(fileName, 1, #fileName - #extension)
    if document == "" then
        return nil, nil, nil
    end
    return collection, entityId, document
end

--- Extract one candidate value from a published URI for the requested template argument.
---@param templateUri string
---@param argumentName string
---@param context any
---@param uri string
---@return string?
local function ExtractCandidate(templateUri, argumentName, context, uri)
    if templateUri == templates.memoryEntity.uriTemplate then
        local collection, entityId, document = ParseMemoryEntityUri(uri)
        if not collection then
            return nil
        end
        if argumentName == "collection" then
            return collection
        end
        if argumentName == "entity_id" then
            if ContextArgument(context, "collection") == collection then
                return entityId
            end
            return nil
        end
        if argumentName == "document" then
            if ContextArgument(context, "collection") == collection and ContextArgument(context, "entity_id") == entityId then
                return document
            end
        end
        return nil
    end

    if templateUri == templates.screenshot.uriTemplate and argumentName == "file" then
        local prefix = "morrowind://screenshot/"
        if string.startswith(uri, prefix) then
            local fileName = string.sub(uri, #prefix + 1)
            if fileName ~= "" and not string.find(fileName, "/", 1, true) then
                return fileName
            end
        end
    end
    return nil
end

--- Validate a completion request before inspecting resource names.
---@param params any
---@return boolean
---@return string[]
local function Validate(params)
    local errors = {}
    if type(params) ~= "table" or type(params.ref) ~= "table" then
        return false, { "Expected completion reference." }
    end
    if params.ref.type ~= "ref/resource" then
        return false, { "Only resource-template completion is supported." }
    end
    if params.ref.uri ~= templates.memoryEntity.uriTemplate and params.ref.uri ~= templates.screenshot.uriTemplate then
        return false, { "Unknown resource template." }
    end
    if type(params.argument) ~= "table" or type(params.argument.name) ~= "string" or type(params.argument.value) ~= "string" then
        return false, { "Expected completion argument name and string value." }
    end

    local argumentName = params.argument.name
    if params.ref.uri == templates.memoryEntity.uriTemplate then
        if argumentName ~= "collection" and argumentName ~= "entity_id" and argumentName ~= "document" then
            return false, { "Unknown Memory template argument." }
        end
        if argumentName == "entity_id" and not ContextArgument(params.context, "collection") then
            return false, { "Memory entity_id completion requires context.arguments.collection." }
        end
        if argumentName == "document" and (not ContextArgument(params.context, "collection") or not ContextArgument(params.context, "entity_id")) then
            return false, { "Memory document completion requires context.arguments.collection and context.arguments.entity_id." }
        end
    elseif argumentName ~= "file" then
        return false, { "Unknown screenshot template argument." }
    end
    return true, errors
end

--- Complete one resource-template argument from the currently published resource set.
---@param params MCP.CompleteRequestParams
---@param resources table<MCP.ResourceUri, MCP.ResourceEntry>?
---@param resultLimit integer?
---@return MCP.Resources.CompletionResult
function this.Complete(params, resources, resultLimit)
    local valid, errors = Validate(params)
    if not valid then
        return Invalid(errors)
    end

    local query = params.argument.value
    local loweredQuery = string.lower(query)
    local candidates = {}
    local seen = {}
    for uri, _ in pairs(resources or {}) do
        local candidate = ExtractCandidate(params.ref.uri, params.argument.name, params.context, uri)
        if candidate and not seen[candidate] and string.startswith(string.lower(candidate), loweredQuery) then
            seen[candidate] = true
            table.insert(candidates, candidate)
        end
    end

    table.sort(candidates, function(a, b)
        local aExact = a == query
        local bExact = b == query
        if aExact ~= bExact then
            return aExact
        end
        local lowerA = string.lower(a)
        local lowerB = string.lower(b)
        if lowerA ~= lowerB then
            return lowerA < lowerB
        end
        return a < b
    end)

    local total = #candidates
    local limit = this.NormalizeResultLimit(resultLimit)
    local values = {}
    for index = 1, math.min(total, limit) do
        values[index] = candidates[index]
    end
    return {
        valid = true,
        errors = {},
        values = values,
        total = total,
        hasMore = total > #values,
    }
end

return this
