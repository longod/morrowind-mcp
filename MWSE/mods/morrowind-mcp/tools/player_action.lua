local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.core.toolavailability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local input_action = require("morrowind-mcp.util.input_action")

local minHoldSeconds = 2.0 / 60.0
local maxHoldSeconds = 10
local defaultHoldSeconds = 1.0

-- keybinding based action to player character. not menu.
-- TODO command list or something for smooth controll. but need to task or own system like the coroutine.

-- TODO rename much better name for this tool. player-action is not good. maybe player-control or player-command or player-input

-- item control.. use?
-- tes3.dropItem
-- tes3.equip
-- tes3.payMerchant
-- tes3.persuade
-- tes3.transferInventory
-- tes3.transferItem



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
        name = "player-action",
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
                        -- "autoRun",
                        "jump",
                        -- "nextWeapon",
                        -- "previousWeapon",
                        -- "nextSpell",
                        -- "previousSpell",
                        -- "togglePOV",
                        "menuMode",
                        "journal",
                        "rest",
                        -- "quickMenu",
                        -- "quick1",
                        -- "quick2",
                        -- "quick3",
                        -- "quick4",
                        -- "quick5",
                        -- "quick6",
                        -- "quick7",
                        -- "quick8",
                        -- "quick9",
                        -- "quick10",
                        -- "quickSave",
                        -- "quickLoad",
                        -- "escape",
                        -- "console",
                        -- "screenshot",
                        -- "readyMagicMCP",
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

function this:GetCapabilityConditions()
    return
    "A game must be active and the player must be loaded. Individual actions can have additional menu or input-binding requirements."
end

---@return boolean
---@return MCP.ToolAvailability?
local function AlwaysOK()
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
local function AlwaysNO()
    return false,
        availability.Unavailable(availability.reason.unsupported,
            "It's unsupported.")
end

---@return boolean
---@return MCP.ToolAvailability?
local function TestNotMenu()
    -- Messages should ideally be instructions.
    return (not tes3.menuMode()),
        availability.Unavailable(availability.reason.pausedInMenu,
            "This action is available only when menu mode is not active.")
end

---@return boolean
---@return MCP.ToolAvailability?
local function TestMove()
    local ok, reason = TestNotMenu()
    if not ok then
        return ok, reason
    end
    -- Messages should ideally be instructions. but the reasons for being unable to act are varied.
    return (tes3.mobilePlayer.canMove),
        availability.Unavailable(availability.reason.movementUnavailable,
            "This action is available only when the player is able to move.")
end

---@type table<tes3.keybind, (fun(): boolean, MCP.ToolAvailability?)?>
local testActionHandler = {
    [tes3.keybind.forward] = TestMove,
    [tes3.keybind.back] = TestMove,
    [tes3.keybind.left] = TestMove,
    [tes3.keybind.right] = TestMove,
    [tes3.keybind.use] = AlwaysNO,
    [tes3.keybind.activate] = AlwaysOK, -- TODO target or activatable menus...
    [tes3.keybind.readyWeapon] = AlwaysNO,
    [tes3.keybind.readyMagic] = AlwaysNO,
    [tes3.keybind.sneak] = AlwaysNO,
    [tes3.keybind.run] = AlwaysNO,
    [tes3.keybind.alwaysRun] = AlwaysNO,
    [tes3.keybind.autoRun] = AlwaysNO,
    [tes3.keybind.jump] = AlwaysNO,
    [tes3.keybind.nextWeapon] = AlwaysNO,
    [tes3.keybind.previousWeapon] = AlwaysNO,
    [tes3.keybind.nextSpell] = AlwaysNO,
    [tes3.keybind.previousSpell] = AlwaysNO,
    [tes3.keybind.togglePOV] = AlwaysNO,
    [tes3.keybind.menuMode] = AlwaysNO,
    [tes3.keybind.journal] = AlwaysNO,
    [tes3.keybind.rest] = AlwaysNO,
    [tes3.keybind.quickMenu] = AlwaysNO,
    [tes3.keybind.quick1] = AlwaysNO,
    [tes3.keybind.quick2] = AlwaysNO,
    [tes3.keybind.quick3] = AlwaysNO,
    [tes3.keybind.quick4] = AlwaysNO,
    [tes3.keybind.quick5] = AlwaysNO,
    [tes3.keybind.quick6] = AlwaysNO,
    [tes3.keybind.quick7] = AlwaysNO,
    [tes3.keybind.quick8] = AlwaysNO,
    [tes3.keybind.quick9] = AlwaysNO,
    [tes3.keybind.quick10] = AlwaysNO,
    [tes3.keybind.quickSave] = AlwaysNO,
    [tes3.keybind.quickLoad] = AlwaysNO,
    [tes3.keybind.escape] = AlwaysNO,
    [tes3.keybind.console] = AlwaysNO,
    [tes3.keybind.screenshot] = AlwaysNO,
    [tes3.keybind.readyMagicMCP] = AlwaysNO,
}

function this:CanExecute(arguments, context)
    if tes3.onMainMenu() then
        return false, availability.Unavailable(availability.reason.gameNotActive, "Start or continue a game.")
    end
    if not tes3.player or not tes3.mobilePlayer then
        return false,
            availability.Unavailable(availability.reason.playerUnavailable, "Wait until the player has loaded.")
    end
    local action = arguments["action"]
    local key = tes3.keybind[action]
    if key == nil or tes3.getInputBinding(key) == nil then
        return false, availability.Unavailable(
            availability.reason.inputBindingUnavailable,
            "Configure a key binding for the requested player action."
        )
    end

    local handler = testActionHandler[action]
    if handler then
        return handler()
    end

    return true
end

function this:Execute(arguments, context)
    local action = arguments["action"]
    local how = arguments["how"]
    local seconds = arguments["seconds"]

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
        .. string.format(" Keybinding=%d (device=%s, code=%d).", key, input_action.GetDeviceName(binding.device),
            binding.code)

    return jsonrpc.CallToolResult(jsonrpc.TextContent(successMessage), nil, false)
end

return this
