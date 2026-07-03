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
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type MCP.ITool
    setmetatable(instance, { __index = this })
    return instance
end

---@public
---@param params table
---@return boolean
function this:CanExecute(params)
    return true
end

---@public
---@param params MCP.CallToolRequestParams
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult?
function this:Execute(params, context)
    -- if context and context.progressToken then
    --     context.NotifyProgress(0.5, 1, "Halfway done")
    -- end
end

-- need signal function, status changed handler?

return this
