---@class MCP.IPrompt
---@field definition MCP.PromptDefinition
local this = {}

---@class MCP.PromptDefinition: MCP.PrimitiveDefinition

---@param params table?
---@return MCP.IPrompt
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type MCP.IPrompt
    setmetatable(instance, { __index = this })
    return instance
end


return this
