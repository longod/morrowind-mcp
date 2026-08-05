local base = require("morrowind-mcp.core.iresource")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local http = require("morrowind-mcp.server.http")
local pathutil = require("morrowind-mcp.core.pathutil")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local settings = require("morrowind-mcp.settings")
local mcp = require("morrowind-mcp.core.mcp")
local base64 = require("morrowind-mcp.core.base64")
local datetime = require("morrowind-mcp.util.datetime")
local memory = require("morrowind-mcp.resources.memory.manager")


---@alias MCP.ResourceContentHandler fun(desc: MCP.Resource): MCP.ResourceContent[]?

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
---@field memory MCP.Resources.MemoryManager?
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

    instance.memory = memory.new({ resource = instance })
    instance.memory:RegisterEvent()
    return instance
end

function this:Release()
    if self.memory then
        self.memory:UnregisterEvent()
        self.memory = nil
    end

    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end

    self.resources = nil
    self.updated = nil
    self.changed = 0
end

---@param currentDir string
---@param relativeDir string
---@param resources MCP.Resource[]
local function CollectResources(currentDir, relativeDir, resources)
    for file in lfs.dir(currentDir) do
        if file ~= "." and file ~= ".." then
            local currentPath = currentDir .. file
            local mode = lfs.attributes(currentPath, "mode")
            if mode == "directory" then
                CollectResources(currentPath .. "\\", relativeDir .. file .. "/", resources)
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
                    table.insert(resources, resource)
                else
                    -- self.logger:warn("Skip invalid resource path: %s", relativePath)
                end
            end
        end
    end
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

    -- persistent file resources are not available. no need for agent.
    -- local rootDir = settings.resourceRootDir
    -- CollectResources(rootDir, "", result.resources)

    table.sort(result.resources, function(a, b)
        return a.uri < b.uri
    end)

    self.logger:debug("List resources count=%d", #result.resources)

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

---@param desc MCP.Resource
---@return MCP.ResourceContent?
function this:LoadFileContent(desc)
    local resourcePath = pathutil.FromUri(desc.uri, settings.uriScheme)
    if not resourcePath then
        self.logger:warn("Cannot read resource with an invalid URI: %s", tostring(desc.uri))
        return nil
    end

    local resourceFilePath = pathutil.ToResourceFilePath(resourcePath, settings.resourceRootDir)
    if not resourceFilePath then
        self.logger:warn("Cannot resolve resource file path: %s", tostring(desc.uri))
        return nil
    end

    local mimeType = desc.mimeType or mimeutil.ResolveMimeTypeFromResourcePath(resourcePath)
    if not mimeType then
        self.logger:warn("Cannot resolve resource MIME type: %s", tostring(desc.uri))
        return nil
    end
    local textType = mimeutil.IsTextMimeType(mimeType)
    local mode = textType and "r" or "rb"

    local file = io.open(resourceFilePath, mode)
    if not file then
        self.logger:warn("Cannot open resource file: uri=%s path=%s", tostring(desc.uri), resourceFilePath)
        return nil
    end

    local data = file:read("*a")
    file:close()

    if textType then
        return jsonrpc.TextResourceContents(desc.uri, data, mimeType)
    else
        return jsonrpc.BlobResourceContents(desc.uri, base64.encode(data), mimeType)
    end
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

    local entry = self.resources[params.uri]
    local contents = nil
    if entry then
        -- Registered resources control their descriptor and may generate their contents lazily.
        self.logger:debug("Read registered resource: %s", params.uri)
        contents = entry.handler(entry.descriptor)
    else
        -- File-backed resources remain readable without being exposed by resources/list.
        self.logger:debug("Read file resource fallback: %s", params.uri)
        local content = self:LoadFileContent({ name = params.uri, uri = params.uri })
        if content then
            contents = { content }
        end
    end

    if not contents or table.size(contents) == 0 then
        self.logger:warn("Resource is unavailable: %s", params.uri)
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.not_found,
            error = jsonrpc.ErrorWithMessage(jsonrpc.error_code.invalid_params,
                string.format("Resource is unavailable: %s. Call %s to confirm current availability.",
                    tostring(params.uri), mcp.method.resources_list)),
        }
    end

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = jsonrpc.ReadResourceResult(contents),
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
        self.logger:debug("Published a new resource: %s changed=%d total=%d", resource.descriptor.uri, self.changed,
            table.size(self.resources))
    end
    self.resources[resource.descriptor.uri] = resource -- copy is better?
    entry = self.resources[resource.descriptor.uri]
    -- update modified datetime
    entry.descriptor.annotations = jsonrpc.Annotations(entry.descriptor.annotations.audience,
        entry.descriptor.annotations.priority, datetime.UTCNow())
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

function this:IsChangedResourceList()
    return self.changed > 0
end

function this:ResetChangedResourceList()
    self.logger:debug("resource list changed, changed=%d total=%d", self.changed, table.size(self.resources))
    self.changed = 0
end

function this:GetUpdatedResources()
    return self.updated
end

function this:ResetUpdatedResources()
    self.logger:debug("resource updated, updated=%d total=%d", table.size(self.updated), table.size(self.resources))
    table.clear(self.updated)
end

return this
