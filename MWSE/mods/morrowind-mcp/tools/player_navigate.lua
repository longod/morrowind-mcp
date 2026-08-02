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
                        "look_at",
                    },
                    "Action",
                    "Action to perform on the player character.",
                    "activate"
                ),
            },
            jsonrpc.array({ "action" })
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
    local action = arguments["action"]

    -- tes3.positionCell

    return nil


end

return this
