local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")

-- rename player stats?

---@class MCP.Tools.PlayerFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.PlayerFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.PlayerFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "player_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "player-fetch",
        description =
        "Fetch current player state.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                player = jsonrpc.JsonObjectSchema(),
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

function this:Execute(arguments, context)
    local player = tes3.mobilePlayer
    if not player then
        local errorContent = jsonrpc.TextContent("No player found. Please enter the game.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    -- too many fields, maybe need to filter out some fields.

    local structuredContent = jsonrpc.object({ player = obj.tes3mobilePlayer(player) })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
