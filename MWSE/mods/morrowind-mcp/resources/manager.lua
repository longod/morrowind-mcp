local base = require("morrowind-mcp.core.iresource")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local http = require("morrowind-mcp.server.http")
local pathutil = require("morrowind-mcp.core.pathutil")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local settings = require("morrowind-mcp.settings")
local base64 = require("morrowind-mcp.core.base64")
local datetime = require("morrowind-mcp.datetime")

local journal = require("morrowind-mcp.resources.journal")

--- I want to idendify same or difference character.
---@class MCP.SaveGameState
---@field playerName string
-----@field modifiedTime string
-----@field filename string
-----@field fileSize number

-- IGT useful for loading save game.

---@class MCP.ResourceCacheState
---@field save MCP.SaveGameState
---@field lastModifiedInSystemTime number
---@field lastModifiedInGameTime number
---@field lastAccessedInSystemTime number
---@field lastAccessedInGameTime number

---@alias MCP.ResourceContentHandler fun(desc: MCP.Resource): MCP.ResourceContent[]

---@class MCP.ResourceEntry
---@field descriptor MCP.Resource
---@field handler MCP.ResourceContentHandler
---content cache

---@class MCP.ResourceManager: MCP.IResourceManager
---@field logger mwseLogger
---@field resources table<MCP.ResourceUri, MCP.ResourceEntry>
---@field changed integer for list changed
---@field updated table<MCP.ResourceUri, boolean> for subscription
---@field loadedCallback fun(e : loadedEventData)
local this = {}
setmetatable(this, { __index = base })

-- TODO cache resource list and resources.

---@param params table?
---@return MCP.ResourceManager
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.ResourceManager
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "resource" })
    instance.resources = {}
    instance.updated = {}
    instance.changed = 0

    instance.loadedCallback = function(e)
        instance:OnLoaded(e)
    end
    -- fastest in this server. because resource manager reset resource cache state. then any resources update on loaded.
    event.register(tes3.event.loaded, instance.loadedCallback, { priority = 100 })

    journal.RegisterEvent(instance) -- register journal resource
    return instance
end

function this:Release()
    journal.UnregisterEvent() -- unregister journal resource

    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end

    self.resources = nil
    self.updated = nil
    self.changed = 0
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnResourcesList(params)
    -- crawl files from resource directory, or maybe only registered resources
    -- TODO implementation to resources/
    -- TODO pagenation support

    ---@type MCP.ListResourcesResult
    local result = jsonrpc.ListResourcesResult()

    -- add virtual resources
    for _, r in pairs(self.resources) do
        table.insert(result.resources, r.descriptor)
    end

    self.logger:debug("List resources count=%d, virutal=%d", #result.resources, table.size(self.resources))

    ---@param currentDir string
    ---@param relativeDir string
    local function CollectResources(currentDir, relativeDir)
        for file in lfs.dir(currentDir) do
            if file ~= "." and file ~= ".." then
                local currentPath = currentDir .. file
                local mode = lfs.attributes(currentPath, "mode")
                if mode == "directory" then
                    CollectResources(currentPath .. "\\", relativeDir .. file .. "/")
                elseif mode == "file" then
                    local relativePath = relativeDir .. file
                    local resourceUri = pathutil.ToUri(relativePath, settings.uriScheme)
                    if resourceUri then
                        -- UTC, ISO 8601
                        local modification = lfs.attributes(currentPath, "modification")
                        local utcISO8601 = os.date("!%Y-%m-%dT%H:%M:%SZ", modification)

                        ---@type MCP.Resource
                        local resource = {
                            name = relativePath,
                            uri = resourceUri,
                            mimeType = mimeutil.ResolveMimeTypeFromResourcePath(relativePath),
                            size = lfs.attributes(currentPath, "size"),
                            annotations = jsonrpc.Annotations(nil, nil, utcISO8601),
                        }
                        table.insert(result.resources, resource)
                    else
                        self.logger:warn("Skip invalid resource path: %s", relativePath)
                    end
                end
            end
        end
    end

    local rootDir = settings.resourceRootDir
    CollectResources(rootDir, "")
    table.sort(result.resources, function(a, b)
        return a.uri < b.uri
    end)

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnResourcesTemplatesList(params)
    ---@type MCP.ListResourceTemplatesResult
    local result = jsonrpc.ListResourceTemplatesResult()

    -- TODO present templete path for resource finding.
    -- TODO implementation to resources/

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.ReadResourceRequestParams
---@return MCP.MethodResult
function this:OnResourcesRead(params)
    if not params or type(params.uri) ~= "string" then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- try read virtual resources
    local entry = self.resources[params.uri]
    if entry then
        -- handler for virtual resource access
        -- or cache
        -- TODO current datetime in game
        local contents = entry.handler(entry.descriptor)
        if not contents or #contents == 0 then
            ---@type MCP.MethodResult
            return {
                http_response = http.response_code.not_found, -- ?
                error = jsonrpc.error_code.invalid_params,
            }
        end
        return {
            http_response = http.response_code.ok,
            result = jsonrpc.ReadResourceResult(contents),
        }
    end

    local resourcePath = pathutil.FromUri(params.uri, settings.uriScheme)
    if not resourcePath then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local resourceFilePath = pathutil.ToResourceFilePath(resourcePath, settings.resourceRootDir)
    if not resourceFilePath then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local file = io.open(resourceFilePath, "rb")
    if not file then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local data = file:read("*a")
    file:close()

    local mimeType = mimeutil.ResolveMimeTypeFromResourcePath(resourcePath)
    local content = jsonrpc.BlobResourceContents(params.uri, base64.encode(data), mimeType)

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = jsonrpc.ReadResourceResult({ content }),
    }
end


---@param e loadedEventData
function this:OnLoaded(e)
    -- reset resource cache state on game load.
    -- keeping no IGT resources?
end


-- register path for tools
-- hook tools response then manage tools's resource. save and cache


---@param resource MCP.ResourceEntry
---@return string MCP.ResourceUri
function this:PublishResource(resource)
    -- any state, hints.
    -- per player? in-game? write to file?

    local entry = self.resources[resource.descriptor.uri]

    if entry then
        -- check conflict?
        -- reset cache
        self.updated[resource.descriptor.uri] = true
        self.logger:debug("Updated a resource: %s  total=%d", resource.descriptor.uri, table.size(self.resources))
    else
        self.changed = self.changed + 1
        self.logger:debug("Published a new resource: %s changed=%d total=%d", resource.descriptor.uri, self.changed, table.size(self.resources))
    end
    self.resources[resource.descriptor.uri] = resource -- copy is better?
    entry = self.resources[resource.descriptor.uri]
    -- update modified datetime
    entry.descriptor.annotations = jsonrpc.Annotations(entry.descriptor.annotations.audience, entry.descriptor.annotations.priority,  datetime.UTCNow())
    return resource.descriptor.uri
end

function this:UnpublishResource(uri)

    if not self.resources[uri] then
        return false
    end
    self.resources[uri] = nil
    self.changed = self.changed + 1
    -- need updated list for subscription?
    self.logger:debug("Unpublished a resource: %s changed=%d", uri, self.changed)
    return true
end

return this
