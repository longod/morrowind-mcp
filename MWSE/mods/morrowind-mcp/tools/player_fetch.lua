local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local summary = require("morrowind-mcp.tes3.object_summary")

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
        inputSchema = jsonrpc.InputSchema({
            detail_level = jsonrpc.UntitledSingleSelectEnumSchema(
                { "minimal", "standard", "full" },
                "Detail Level",
                "Serialization detail for game objects. The default is standard.",
                "standard"
            ),
        }),
        outputSchema = jsonrpc.OutputSchema(
            {
                player = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and the player character must be loaded."
end

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

function this:Execute(arguments, context)
    local player = tes3.player
    local mobilePlayer = tes3.mobilePlayer
    if not player or not mobilePlayer then
        local errorContent = jsonrpc.TextContent("No player found. Please enter the game.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local serializer = summary.new({
        detailLevel = arguments["detail_level"] or summary.level.standard, -- need distance
    })

    -- TODO too many fields, maybe need to filter out some fields.

    local structuredContent = jsonrpc.object({
        player = serializer:tes3mobilePlayer(mobilePlayer),
    })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
