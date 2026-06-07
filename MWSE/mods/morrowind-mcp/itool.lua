---@class ITool
local this = {}

---@protected
---@param params table?
---@return ITool
function this.new(params)
    ---@type ITool
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end


return this
