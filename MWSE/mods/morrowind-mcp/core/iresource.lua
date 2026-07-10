---@class MCP.IResourceManager
local this = {}

---@param params table?
---@return MCP.IResourceManager
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type MCP.IResourceManager
    setmetatable(instance, { __index = this })
    return instance
end

---@public
function this:Release()
end

return this
