local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

---@class MCP.Tools.CapabilitiesFetch: MCP.ITool
---@field logger mwseLogger
---@field GetPublishedTools fun(): table<string, MCP.ITool>
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.CapabilitiesFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.CapabilitiesFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "capabilities_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "capabilities-fetch",
        description = "Fetch general conditions for published tools. We recommend using this tool to check then.",
        inputSchema = jsonrpc.InputSchema({
            tool_name = jsonrpc.StringSchema(
                "Tool Name",
                "Optional published tool name to filter by.",
                1,
                255
            ),
        }),
        outputSchema = jsonrpc.OutputSchema({
            tools = jsonrpc.JsonArraySchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false),
    })
    return instance
end

--- Return the static conditions for published tools without evaluating their current runtime state.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local toolName = arguments["tool_name"]
    local publishedTools = self.GetPublishedTools and self:GetPublishedTools() or {}
    local tools = jsonrpc.array()

    for name, tool in pairs(publishedTools) do
        -- This discovery tool has no actionable conditions and is not part of its own catalogue.
        if tool ~= self and (toolName == nil or toolName == name) then
            table.insert(tools, jsonrpc.object({
                name = name,
                conditions = tool:GetCapabilityConditions(),
            }))
        end
    end

    table.sort(tools, function(left, right)
        return left.name < right.name
    end)

    return jsonrpc.CallToolResult(nil, jsonrpc.object({ tools = tools }))
end

return this
