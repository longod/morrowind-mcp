---@class IPrompt
local this = {}

---@protected
---@param params table?
---@return IPrompt
function this.new(params)
    ---@type IPrompt
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end


return this
