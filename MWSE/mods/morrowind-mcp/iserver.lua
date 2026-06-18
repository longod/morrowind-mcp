---@class MCP.IServer
local this = {}

---@protected
---@param params table?
---@return MCP.IServer
function this.new(params)
    ---@type MCP.IServer
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end

return this

