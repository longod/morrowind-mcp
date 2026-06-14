---@class IServer
local this = {}

---@protected
---@param params table?
---@return IServer
function this.new(params)
    ---@type IServer
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end

return this

