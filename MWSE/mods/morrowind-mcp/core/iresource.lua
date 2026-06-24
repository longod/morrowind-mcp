---@class MCP.IResource
---@field definition MCP.Resource
local this = {}

---@param params table?
---@return MCP.IResource
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type MCP.IResource
    setmetatable(instance, { __index = this })
    return instance
end

---@public
---@param params table
---@return boolean
function this:CanExecute(params)
    return true
end


return this
