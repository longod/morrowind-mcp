local inputvalidator = require("morrowind-mcp.core.inputvalidator")

---@class MCP.ITool
---@field definition MCP.Tool
local this = {}

---@class MCP.ToolExecutionContext
---@field sessionId string?
---@field progressToken MCP.ProgressToken?
---@field NotifyProgress fun(progress: number, total: number?, message: string?): boolean

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

---@public
---@param params table
---@return boolean
function this:CanExecute(params)
    return true
end

---@public
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    -- Subclasses should call this first, then append checks that depend on a specific tool sink.
    return inputvalidator.ValidateArguments(params and params.arguments or nil, self.definition.inputSchema)
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
