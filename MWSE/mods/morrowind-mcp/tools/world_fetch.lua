local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")


---@class MCP.WorldFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.WorldFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.WorldFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "world_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "world-fetch",
        description =
        "Fetch the world state.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                world = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    return true
end

function this:Execute(params, context)
    local world = tes3.worldController
    if not world then
        local errorContent = jsonrpc.TextContent("No world found. Please enter the game.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    -- static state, dynamic state?
    -- and cellls

    -- fetch sound state? AI cant listen sounds directly
    -- sound state should be handled sound events. and  evens accumulated sounds, then flush them periodically.
    -- therefore state present to listen sounds during some interval.

    local structuredContent = jsonrpc.object({ world = obj.tes3worldController(world) })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
