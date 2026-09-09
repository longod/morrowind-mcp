local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local cellutil = require("morrowind-mcp.tes3.cell")

---@class MCP.Tools.RouteNavigate: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

--- Serialize travel-node candidates for a failed route start.
---@param nodes MCP.PathfindingTravelNode[]?
---@return table
local function SerializeTravelNodes(nodes)
    local output = jsonrpc.array()
    for _, node in ipairs(nodes or {}) do
        local destinations = jsonrpc.array()
        for _, destination in ipairs(node.destinations) do
            table.insert(destinations, jsonrpc.object({ cell_id = destination.cellId }))
        end
        table.insert(output, jsonrpc.object({
            reference_id = node.referenceId,
            kind = node.kind,
            position = jsonrpc.object(node.position),
            destinations = destinations,
            walk_distance = node.walkDistance,
        }))
    end
    return output
end

--- Return a stable non-moving response for every failed navigation start.
---@param message string
---@param failure MCP.NavigatorStartFailure?
---@return MCP.CallToolResult
local function NavigationStartFailure(message, failure)
    return jsonrpc.CallToolResult(jsonrpc.TextContent(message), jsonrpc.object({
        reason = failure and failure.reason or nil,
        movement_started = false,
        travel_nodes = SerializeTravelNodes(failure and failure.travelNodes or nil),
    }), true)
end

---@param params table?
---@return MCP.Tools.RouteNavigate
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.RouteNavigate
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "route_navigate" })
    instance.definition = jsonrpc.Tool({
        name = "route-navigate",
        description =
        "Navigate the player character through the game world toward an intentional destination, " ..
        "such as an observed NPC, reference, location, or world-space coordinate. " ..
        "Navigation returns route node and waypoint counts; verify arrival with player, reference, or world state. " ..
        "When navigation does not start, movement_started is false and travel_nodes contains compact reachable transitions " ..
        "with reference_id, kind, position, destination cell_id, and walk_distance; use mw-route-fetch for details. " ..
        "Use cancel_navigation to stop an active route.",
        inputSchema = jsonrpc.InputSchema({
            action = jsonrpc.UntitledSingleSelectEnumSchema({ "navigate", "cancel_navigation" }, "Action",
                "Method to navigate the player character or cancel active navigation.", "navigate"),
            position_x = jsonrpc.NumberSchema("Destination X", "Destination X coordinate in world space, in Morrowind game units."),
            position_y = jsonrpc.NumberSchema("Destination Y", "Destination Y coordinate in world space, in Morrowind game units."),
            position_z = jsonrpc.NumberSchema("Destination Z", "Destination Z coordinate in world space, in Morrowind game units."),
            cell_id = jsonrpc.StringSchema("Destination Cell", "Optional cell containing the destination.", nil, 64),
        }, jsonrpc.array({ "action" })),
        outputSchema = jsonrpc.OutputSchema({
            route_node_count = jsonrpc.NumberSchema("Route Node Count", "Number of pathgrid nodes in the started route.", 1),
            waypoint_count = jsonrpc.NumberSchema("Waypoint Count", "Number of waypoints in the started route.", 1),
            reason = jsonrpc.StringSchema("Reason", "Why navigation did not start."),
            movement_started = jsonrpc.BooleanSchema("Movement Started", "False when no route was started."),
            travel_nodes = jsonrpc.JsonArraySchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and the player must be loaded. Without a walk-only route, the tool returns reachable travel nodes instead of moving."
end

function this:CanExecute(arguments, context)
    if arguments["action"] == "cancel_navigation" then
        if not context or not context.CancelPlayerNavigation or not context.HasActivePlayerNavigation then
            return false, availability.Unavailable(availability.reason.navigation_unavailable, {
                unavailableBecause = "Route-navigation cancellation services are unavailable in the execution context.",
                availableWhen = "The execution context provides route-navigation cancellation and active-route services.",
            })
        end
        if not context.HasActivePlayerNavigation() then
            return false, availability.Unavailable(availability.reason.no_active_navigation, {
                unavailableBecause = "No route-navigation route is active.",
                availableWhen = "A route-navigation route is active.",
            })
        end
        return true
    end
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, availability.WithRelatedTools(reason, {
            { name = "mw-reference-fetch", relationship = "reports destination references in active cells." },
        })
    end
    ok, reason = availability.NotInMenuMode()
    if not ok then
        return false, availability.WithRelatedTools(reason, {
            { name = "mw-reference-fetch", relationship = "reports destination references in active cells." },
        })
    end
    if arguments["action"] == "navigate" and (not context or not context.NavigatePlayer) then
        return false, availability.Unavailable(availability.reason.navigation_unavailable, {
            unavailableBecause = "Route-navigation services are unavailable in the execution context.",
            availableWhen = "The execution context provides the route-navigation service.",
        })
    end
    return true
end

--- Validate coordinates only when the requested action needs a navigation destination.
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end
    local arguments = params.arguments or {}
    if arguments["action"] == "navigate" then
        for _, name in ipairs({ "position_x", "position_y", "position_z" }) do
            if arguments[name] == nil then
                table.insert(result.errors, { path = name, message = "Required argument is missing for navigation." })
                result.valid = false
            end
        end
    end
    return result
end

--- Execute one route navigation action or return travel-node guidance before movement starts.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local action = arguments["action"]
    if action == "cancel_navigation" then
        if not context or not context.CancelPlayerNavigation then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Route navigation is unavailable on this server."), nil, true)
        end
        if context.CancelPlayerNavigation() then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Route navigation cancelled."), jsonrpc.object(), false)
        end
        return jsonrpc.CallToolResult(jsonrpc.TextContent("There is no active route navigation."), jsonrpc.object(), true)
    end
    if action == "navigate" then
        if not context or not context.NavigatePlayer then
            return NavigationStartFailure("Route navigation is unavailable on this server.")
        end
        local destinationCell = cellutil.ResolveOptionalId(arguments["cell_id"], tes3.player and tes3.player.cell or nil)
        if not destinationCell then
            return NavigationStartFailure("The requested destination cell could not be resolved.")
        end
        local position = tes3vector3.new(arguments["position_x"], arguments["position_y"], arguments["position_z"])
        local ok, message, navigation, failure = context.NavigatePlayer({ cell = destinationCell, position = position })
        if not ok then
            return NavigationStartFailure(message or "Failed to start route navigation.", failure)
        end
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Route navigation started."), jsonrpc.object({
            route_node_count = navigation and navigation.routeNodeCount or nil,
            waypoint_count = navigation and navigation.waypointCount or nil,
        }), false)
    end
    return jsonrpc.CallToolResult(jsonrpc.TextContent("Unknown action"), nil, true)
end

return this