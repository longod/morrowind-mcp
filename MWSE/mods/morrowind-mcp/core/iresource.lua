---@class MCP.IResourceManager
local this = {}

---@param params table?
---@return MCP.IResourceManager
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, params)
    end
    ---@type MCP.IResourceManager
    setmetatable(instance, { __index = this })
    return instance
end

---@public
function this:Release()
end

---@param resource MCP.ResourceEntry
---@return MCP.ResourceUri
function this:PublishResource(resource)
    return ""
end

---@param uri MCP.ResourceUri
---@return boolean
function this:UnpublishResource(uri)
    return false
end

return this
