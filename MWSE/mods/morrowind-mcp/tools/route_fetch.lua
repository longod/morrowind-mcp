local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local cellutil = require("morrowind-mcp.tes3.cell")

---@class MCP.Tools.RouteFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

--- Serialize travel-node discovery without retaining graph or MWSE userdata.
---@param nodes MCP.PathfindingTravelNode[]
---@return table
local function SerializeTravelNodes(nodes)
    local output = jsonrpc.array()
    for _, node in ipairs(nodes) do
        local destinations = jsonrpc.array()
        for _, destination in ipairs(node.destinations) do
            table.insert(destinations, jsonrpc.object({
                cell_id = destination.cellId,
                marker_position = jsonrpc.object(destination.markerPosition),
                target_relation = destination.targetRelation,
            }))
        end
        table.insert(output, jsonrpc.object({
            reference_id = node.referenceId,
            kind = node.kind,
            source_cell_id = node.sourceCellId,
            position = jsonrpc.object(node.position),
            destinations = destinations,
            walk_distance = node.walkDistance,
            route_node_count = node.routeNodeCount,
        }))
    end
    return output
end

---@param params table?
---@return MCP.Tools.RouteFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.RouteFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "route_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "route-fetch",
        description =
        "Fetch travel transitions that are reachable on foot from the player's current position, and whether an optional destination is walkable. " ..
        "Travel nodes include reference_id, kind, source_cell_id, position, destinations with cell_id and marker_position, target_relation, walk_distance, and route_node_count. " ..
        "Travel transitions currently come from doors leading to another cell. This tool does not move the player.",
        inputSchema = jsonrpc.InputSchema({
            position_x = jsonrpc.NumberSchema("Destination X", "Optional destination X coordinate in world space, in Morrowind game units."),
            position_y = jsonrpc.NumberSchema("Destination Y", "Optional destination Y coordinate in world space, in Morrowind game units."),
            position_z = jsonrpc.NumberSchema("Destination Z", "Optional destination Z coordinate in world space, in Morrowind game units."),
            cell_id = jsonrpc.StringSchema("Destination Cell", "Optional cell containing the destination.", nil, 64),
        }),
        outputSchema = jsonrpc.OutputSchema({
            destination_walkable = jsonrpc.BooleanSchema("Destination Walkable", "Whether the optional destination has a known walk-only route."),
            travel_nodes = jsonrpc.JsonArraySchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false),
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and the player must be loaded. The tool only reads current route information."
end

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    ok, reason = availability.NotInMenuMode()
    if not ok then
        return false, reason
    end
    if not context or not context.IsDestinationWalkable or not context.FindReachableTravelNodes then
        return false, availability.Unavailable(availability.reason.navigation_unavailable, {
            unavailableBecause = "Route discovery is unavailable in this server.",
            availableWhen = "The server provides route-discovery services.",
        })
    end
    return true
end

--- Require complete destination coordinates whenever route discovery receives a destination.
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end
    local arguments = params.arguments or {}
    local hasDestination = arguments["cell_id"] ~= nil or arguments["position_x"] ~= nil or arguments["position_y"] ~= nil or arguments["position_z"] ~= nil
    if hasDestination then
        for _, name in ipairs({ "position_x", "position_y", "position_z" }) do
            if arguments[name] == nil then
                table.insert(result.errors, { path = name, message = "Required argument is missing for destination discovery." })
                result.valid = false
            end
        end
    end
    return result
end

--- Return walk-only reachability and frontier travel nodes without moving the player.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    if not context or not context.IsDestinationWalkable or not context.FindReachableTravelNodes then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Route discovery is unavailable on this server."), nil, true)
    end
    local start = { cell = tes3.player.cell, position = tes3.player.position }
    local destination = nil
    if arguments["position_x"] ~= nil then
        local destinationCell = cellutil.ResolveOptionalId(arguments["cell_id"], tes3.player.cell)
        if not destinationCell then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("The requested destination cell could not be resolved."), nil, true)
        end
        destination = {
            cell = destinationCell,
            position = tes3vector3.new(arguments["position_x"], arguments["position_y"], arguments["position_z"]),
        }
    end
    local destinationWalkable = nil
    if destination then
        destinationWalkable = context.IsDestinationWalkable(start, destination)
    end
    local nodes = context.FindReachableTravelNodes(start, destination)
    return jsonrpc.CallToolResult(nil, jsonrpc.object({
        destination_walkable = destinationWalkable,
        travel_nodes = SerializeTravelNodes(nodes),
    }), false)
end

return this
