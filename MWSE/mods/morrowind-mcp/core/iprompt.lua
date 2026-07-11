---@class MCP.IPrompt
---@field definition MCP.Prompt
local this = {}

---@param params table?
---@return MCP.IPrompt
function this.new(params)
    local instance = {}
    if params then
        -- Keep injected dependencies by reference so shared managers remain shared.
        table.copymissing(instance, params)
    end
    ---@type MCP.IPrompt
    setmetatable(instance, { __index = this })
    return instance
end

---@public
function this:Release()
end

---@public
---@param params table
---@return boolean
function this:CanExecute(params)
    return true
end

---@public
---@param params MCP.GetPromptRequestParams
---@return MCP.GetPromptResult?
function this:Execute(params)
end

return this
