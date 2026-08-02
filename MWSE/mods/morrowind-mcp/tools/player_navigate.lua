local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local input_action = require("morrowind-mcp.util.input_action")

local minHoldSeconds = 2.0 / 60.0
local maxHoldSeconds = 10
local defaultHoldSeconds = 1.0



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
        "Navigate the player character. Looking and Locomotion.",
        inputSchema = jsonrpc.InputSchema(
            {
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "teleport",
                    },
                    "Method",
                    "Method to navigate the player character.",
                    "teleport"
                ),
                -- array, object schema are in specification, but it seems client view is not supported.
                position_x = jsonrpc.NumberSchema("X", "X coordinate in world space.", nil, nil, 0),
                position_y = jsonrpc.NumberSchema("Y", "Y coordinate in world space.", nil, nil, 0),
                position_z = jsonrpc.NumberSchema("Z", "Z coordinate in world space.", nil, nil, 0),
            },
            jsonrpc.array({ "action", "position_x", "position_y", "position_z" })
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),

    })
    return instance
end

function this:CanExecute(params)
    -- can get on main menu?
    if tes3.onMainMenu() then
        return false
    end
    return true
end

function this:Execute(arguments, context)
    local method = arguments["method"]
    local position = tes3vector3.new(arguments["position_x"], arguments["position_y"], arguments["position_z"])

    local result = tes3.positionCell({
        --      reference = tes3.mobilePlayer,
        --      cell = tes3.getPlayerCell(),
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
