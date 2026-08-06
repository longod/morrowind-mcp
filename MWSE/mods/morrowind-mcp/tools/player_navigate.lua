local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.core.toolavailability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local cellutil = require("morrowind-mcp.tes3.cell")



---@class MCP.Tools.PlayerNavigate: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.PlayerNavigate
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.PlayerNavigate
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "player_navigate" })
    instance.definition = jsonrpc.Tool({
        name = "player-navigate",
        description =
        "Teleport or navigate the player character. Navigate returns route node and waypoint counts; teleport returns text only.",
        inputSchema = jsonrpc.InputSchema(
            {
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "teleport",
                        "navigate",
                    },
                    "Action",
                    "Method to navigate the player character.",
                    "teleport"
                ),
                -- array, object schema are in specification, but it seems client view is not supported.
                position_x = jsonrpc.NumberSchema("X", "X coordinate in world space.", nil, nil, 0),
                position_y = jsonrpc.NumberSchema("Y", "Y coordinate in world space.", nil, nil, 0),
                position_z = jsonrpc.NumberSchema("Z", "Z coordinate in world space.", nil, nil, 0),
                cell_id = jsonrpc.StringSchema("Cell ID", "Optional destination cell ID for navigation or teleport.", nil, 64),
            },
            jsonrpc.array({ "action", "position_x", "position_y", "position_z" })
        ),
        outputSchema = jsonrpc.OutputSchema({
            route_node_count = jsonrpc.NumberSchema("Route Node Count", "Number of pathgrid nodes in the started route.", 1),
            waypoint_count = jsonrpc.NumberSchema("Waypoint Count", "Number of waypoints in the started route.", 1),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),

    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and the player must be loaded. Navigation also requires a reachable destination."
end

function this:CanExecute(arguments, context)
    if tes3.onMainMenu() then
        return false, availability.Unavailable(availability.reason.gameNotActive, "Start or continue a game.")
    end
    if not tes3.player then
        return false, availability.Unavailable(availability.reason.playerUnavailable, "Wait until the player has loaded.")
    end
    if arguments["action"] == "navigate" and (not context or not context.NavigatePlayer) then
        return false, availability.Unavailable(
            availability.reason.navigationUnavailable,
            "Use a server that provides player navigation."
        )
    end
    return true
end

function this:Execute(arguments, context)
    local action = arguments["action"]
    local position = tes3vector3.new(arguments["position_x"], arguments["position_y"], arguments["position_z"])
    local cell_id = arguments["cell_id"]

    if action == "navigate" then
        if not context or not context.NavigatePlayer then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Player navigation is unavailable on this server."), nil, true)
        end
        local fallbackCell = tes3.player and tes3.player.cell or nil
        local destinationCell = cellutil.ResolveOptionalId(cell_id, fallbackCell)
        if not destinationCell then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("The requested destination cell could not be resolved."), nil,
                true)
        end
        local ok, message, navigation = context.NavigatePlayer({ cell = destinationCell, position = position })
        if not ok then
            return jsonrpc.CallToolResult(jsonrpc.TextContent(message or "Failed to start navigation."), nil, true)
        end
        local structuredContent = jsonrpc.object({
            route_node_count = navigation and navigation.routeNodeCount or nil,
            waypoint_count = navigation and navigation.waypointCount or nil,
        })
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Player navigation started."), structuredContent, false)
    end

    local result = tes3.positionCell({
        cell = cell_id,
        position = position,
    })

    if not result then
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent(string.format("Failed to teleport player to position: %s", tostring(position))),
            nil,
            true)
    end

    return jsonrpc.CallToolResult(
        jsonrpc.TextContent(string.format("Player was teleported to position: %s", tostring(position))), nil, false)
end

return this
