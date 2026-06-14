---@class IPrompt
---@field name string
local this = {}

---@protected
---@param params table?
---@return IPrompt
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type IPrompt
    setmetatable(instance, { __index = this })
    return instance
end


return this
