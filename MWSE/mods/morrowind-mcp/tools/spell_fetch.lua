local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.Tools.SpellFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.SpellFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.SpellFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "spell_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "spell-fetch",
        description =
        "Fetch ",
        inputSchema = jsonrpc.InputSchema(
        -- filter, spell, power, magic item
        -- school, effect, range, target, duration, costs (currently castable)
        ),
        outputSchema = jsonrpc.OutputSchema({
            spells = jsonrpc.JsonArraySchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "game loaded"
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
