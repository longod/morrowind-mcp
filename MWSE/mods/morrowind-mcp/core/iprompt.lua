local promptvalidator = require("morrowind-mcp.core.promptvalidator")

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
---@param arguments table<string, string>
---@param context table?
---@return boolean
function this:CanExecute(arguments, context)
    return true
end

--- Validate standard prompts/get arguments before subclasses apply their own output-sink constraints.
---@public
---@param params MCP.GetPromptRequestParams?
---@return InputValidator.Result
function this:Validate(params)
    return promptvalidator.ValidateArguments(params and params.arguments or nil, self.definition and self.definition.arguments or nil)
end

---@public
---@param arguments table<string, string>
---@param context table?
---@return MCP.GetPromptResult?
function this:Execute(arguments, context)
end

return this
