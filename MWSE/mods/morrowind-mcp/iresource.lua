---@class IResource
local this = {}

---@protected
---@param params table?
---@return IResource
function this.new(params)
    ---@type IResource
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end


return this
