local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.Tools.DialogueAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DialogueAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DialogueAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue_action" })
    instance.definition = jsonrpc.Tool({
        name = "dialogue-action",
        description =
        "Select... use mw-dialogue-fetch before this tool",
        inputSchema = jsonrpc.InputSchema(
        -- topic
        -- choice
        ),
        outputSchema = jsonrpc.OutputSchema({
            -- returning responce if available in this frame...
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Dialogue Menu must be displayed."
end

function this:CanExecute(arguments, context)
    -- TODO menu visibility availability by name, helper function.
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

function this:Execute(arguments, context)
    return jsonrpc.CallToolResult(
        jsonrpc.TextContent("not yet implemented."),
        nil,
        true
    )
end

return this
