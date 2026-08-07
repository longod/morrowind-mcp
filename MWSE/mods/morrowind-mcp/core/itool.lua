local toolvalidator = require("morrowind-mcp.core.toolvalidator")

---@class MCP.ITool
---@field definition MCP.Tool
local this = {}

---@class MCP.ToolExecutionContext
---@field sessionId string?
---@field progressToken MCP.ProgressToken?
---@field NotifyProgress fun(progress: number, total: number?, message: string?): boolean
-- TODO: Move runtime operations into an MCP.ToolExecutionServices interface so the generic tool context does not depend on concrete game actions.
---@field NavigatePlayer fun(destination: MCP.PathfindingLocator): boolean, string?, MCP.NavigatorStartResult?
---@field CancelPlayerNavigation fun(): boolean
---@field HasActivePlayerNavigation fun(): boolean

---@param params table?
---@return MCP.ITool
function this.new(params)
    local instance = {}
    if params then
        -- Keep injected dependencies by reference so shared managers remain shared.
        table.copymissing(instance, params)
    end
    ---@type MCP.ITool
    setmetatable(instance, { __index = this })
    return instance
end

---@public
function this:Release()
end

--- Return whether this tool belongs to the server's static public API.
---@public
---@return boolean
function this:IsPublished()
    return true
end

--- Describe the general conditions under which this tool can be used.
---@public
---@return string
function this:GetCapabilityConditions()
    return "This tool has no additional runtime conditions."
end

---@public
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    return true
end

---@public
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    -- Subclasses should call this first, then append checks that depend on a specific tool sink.
    return toolvalidator.ValidateArguments(params and params.arguments or nil, self.definition.inputSchema)
end

---@public
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult?
function this:Execute(arguments, context)
    -- if context and context.progressToken then
    --     context.NotifyProgress(0.5, 1, "Halfway done")
    -- end
end

-- need signal function, status changed handler?

return this
