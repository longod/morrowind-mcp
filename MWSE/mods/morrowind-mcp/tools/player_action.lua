local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local input_action = require("morrowind-mcp.util.input_action")

local minHoldSeconds = 2.0 / 60.0
local maxHoldSeconds = 10
local defaultHoldSeconds = 1.0

-- keybinding based action to player character. not menu.
-- TODO command list or something for smooth controll. but need to task or own system like the coroutine.

---@class MCP.Tools.PlayerAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.PlayerAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.PlayerAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "player_action" })
    instance.definition = jsonrpc.Tool({
        name = "player_action",
        description =
        "Perform an action on the player. This is the player character that the user is controlling.",
        inputSchema = jsonrpc.InputSchema(
            {
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "forward",
                        "back",
                        "left",
                        "right",
                        "use",
                        "activate",
                        "readyWeapon",
                        "readyMagic",
                        "sneak",
                        "run",
                        "alwaysRun",
                        "autoRun",
                        "jump",
                        "nextWeapon",
                        "previousWeapon",
                        "nextSpell",
                        "previousSpell",
                        "togglePOV",
                        "menuMode",
                        "journal",
                        "rest",
                        "quickMenu",
                        "quick1",
                        "quick2",
                        "quick3",
                        "quick4",
                        "quick5",
                        "quick6",
                        "quick7",
                        "quick8",
                        "quick9",
                        "quick10",
                        "quickSave",
                        "quickLoad",
                        "escape",
                        -- "console",
                        "screenshot",
                        "readyMagicMCP",
                    },
                    "Action",
                    "Action to perform on the player character.",
                    "activate"
                ),
                how = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "tap",
                        "push",
                        "hammer",
                    },
                    "How to perform",
                    "How to perform the action. Tap is a single press, push is a press and hold, hammer is a rapid repeat.",
                    "tap"
                ),
                seconds = jsonrpc.NumberSchema(
                    "Seconds",
                    "Time in seconds to hold the action. Only used for push and hammer.",
                    minHoldSeconds,
                    maxHoldSeconds,
                    defaultHoldSeconds
                ),
            },
            jsonrpc.array({ "action", "how" })
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

function this:Execute(params, context)
    local arguments = params.arguments or {}
    local action = arguments["action"]
    local how = arguments["how"]
    local seconds = arguments["seconds"] or defaultHoldSeconds

    local key = tes3.keybind[action]
    if key == nil then
        local errorContent = jsonrpc.TextContent(string.format("Action %s is not a valid keybinding action.", action))
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end


    local binding = tes3.getInputBinding(key)
    if binding == nil then
        local errorContent = jsonrpc.TextContent(string.format("No binding found for action %s.", action))
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    -- we can know actions available per keybindings before performs?

    if how ~= "tap" then
        if how == "push" then
            local ok = input_action.Push(binding, seconds)
            if not ok then
                local errorContent = jsonrpc.TextContent(string.format("Failed to perform action %s.", action))
                return jsonrpc.CallToolResult(errorContent, nil, true)
            end
        elseif how == "hammer" then
            local ok = input_action.Hammer(binding, seconds)
            if not ok then
                local errorContent = jsonrpc.TextContent(string.format("Failed to perform action %s.", action))
                return jsonrpc.CallToolResult(errorContent, nil, true)
            end
        end
    else
        local ok = input_action.Tap(binding)
        if not ok then
            local errorContent = jsonrpc.TextContent(string.format("Failed to perform action %s.", action))
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end
    end

    local successMessage = string.format("Action %s performed as %s.", action, how)
    if how ~= "tap" then
        successMessage = successMessage .. string.format(" Hold seconds=%.3f.", seconds)
    end
    successMessage = successMessage
        .. string.format(" Keybinding=%d (device=%s, code=%d).", key, input_action.GetDeviceName(binding.device), binding.code)

    return jsonrpc.CallToolResult(jsonrpc.TextContent(successMessage), nil, false)

end

return this
