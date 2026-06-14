---@class IResource
---@field name string
local this = {}

---@protected
---@param params table?
---@return IResource
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type IResource
    setmetatable(instance, { __index = this })
    return instance
end


return this
