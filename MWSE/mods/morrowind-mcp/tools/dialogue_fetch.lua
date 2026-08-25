local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.Tools.DialogueFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DialogueFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DialogueFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "dialogue-fetch",
        description =
        "Fetch the content of the current conversation with the actor you're talking to from the dialogue menu. Only the content of this conversation can be fetched. To access past conversations, read from the memory resource.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema({
            actor = jsonrpc.JsonObjectSchema(),
            dialogues = jsonrpc.JsonArraySchema(),
            topics = jsonrpc.JsonArraySchema(),
            -- choices (1, 2, 3.. choices)
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
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
