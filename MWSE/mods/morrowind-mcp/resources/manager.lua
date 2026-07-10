local base = require("morrowind-mcp.core.iresource")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local http = require("morrowind-mcp.server.http")
local pathutil = require("morrowind-mcp.core.pathutil")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local settings = require("morrowind-mcp.settings")
local base64 = require("morrowind-mcp.core.base64")

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

---@class MCP.ResourceManager: MCP.IResourceManager
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

-- TODO cache resource list and resources.

---@param params table?
---@return MCP.ResourceManager
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.ResourceManager
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "resource" })
    return instance
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnResourcesList(params)
    -- crawl files from resource directory, or maybe only registered resources
    -- TODO implementation to resources/
    -- TODO pagenation support

    ---@type MCP.ListResourcesResult
    local result = jsonrpc.ListResourcesResult()

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
                        ---@type MCP.Resource
                        local resource = {
                            name = relativePath,
                            uri = resourceUri,
                            mimeType = mimeutil.ResolveMimeTypeFromResourcePath(relativePath),
                            size = lfs.attributes(currentPath, "size"),
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

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnResourcesTemplatesList(params)
    ---@type MCP.ListResourceTemplatesResult
    local result = jsonrpc.ListResourceTemplatesResult()

    -- TODO present templete path for resource finding.
    -- TODO implementation to resources/

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.ReadResourceRequestParams
---@return MethodResult
function this:OnResourcesRead(params)
    if not params or type(params.uri) ~= "string" then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local resourcePath = pathutil.FromUri(params.uri, settings.uriScheme)
    if not resourcePath then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local resourceFilePath = pathutil.ToResourceFilePath(resourcePath, settings.resourceRootDir)
    if not resourceFilePath then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local file = io.open(resourceFilePath, "rb")
    if not file then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local data = file:read("*a")
    file:close()

    local mimeType = mimeutil.ResolveMimeTypeFromResourcePath(resourcePath)
    local content = jsonrpc.BlobResourceContents(params.uri, base64.encode(data), mimeType)

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = jsonrpc.ReadResourceResult({ content }),
    }
end

-- register path for tools
-- hook tools response then manage tools's resource. save and cache

return this
