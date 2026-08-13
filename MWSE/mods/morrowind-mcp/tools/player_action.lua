local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local input_action = require("morrowind-mcp.util.input_action")
local distanceUtil = require("morrowind-mcp.util.distance")

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
            "Perform direct player input such as movement keys, activation, jumping, sneaking, combat preparation, " ..
            "or other short manual actions. Use this for interaction, immediate input, or fine movement adjustment. " ..
            "For intentional travel toward a known world destination, player-navigate may be more suitable.",
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
local function InGameAvailable()
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
local function ActivateAvailable()
    local ok, reason = InGameAvailable()
    if not ok then
        return ok, reason
    end

    -- it seems better to disallow in menu mode. some dialogs can be activated, but agent counfused because activate becomes always available.
    local target = tes3.getPlayerTarget()
    if not target then
        local distanceUnit = tes3.getPlayerActivationDistance()
        local distanceMeter =  distanceUtil.ToMeters(distanceUnit)
        -- tes3.rayTest()
        return false, availability.Unavailable(
            availability.reason.target_not_found,
            "Action activate is only available when the player is looking at a `supportsActivate` reference object within " ..
            string.format("%.2f meters.", distanceMeter) ..
            " And Use the mw-target-fetch tool to find the current target reference object."
        )
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
local function MovementAvailable()
    local ok, reason = InGameAvailable()
    if not ok then
        return ok, reason
    end

    -- Messages should ideally be instructions. but the reasons for being unable to act are varied.
    return tes3.mobilePlayer.canMove,
        availability.Unavailable(
            availability.reason.movement_unavailable,
            "This action is available only when the player is able to move.")
end

---@return boolean
---@return MCP.ToolAvailability?
local function MenuModeAvailable()
    local ok, reason = InGameAvailable()
    if not ok then
        return ok, reason
    end
    ok, reason = availability.IsCharGenFinished()
    if not ok then
        return ok, reason
    end
    return true
end

---@type table<tes3.keybind, (fun(): boolean, MCP.ToolAvailability?)?>
local testActionHandler = {
    [tes3.keybind.forward] = MovementAvailable,
    [tes3.keybind.back] = MovementAvailable,
    [tes3.keybind.left] = MovementAvailable,
    [tes3.keybind.right] = MovementAvailable,
    [tes3.keybind.use] = availability.AlwaysUnavailable,
    [tes3.keybind.activate] = ActivateAvailable,
    [tes3.keybind.readyWeapon] = availability.AlwaysUnavailable,
    [tes3.keybind.readyMagic] = availability.AlwaysUnavailable,
    [tes3.keybind.sneak] = availability.AlwaysUnavailable,
    [tes3.keybind.run] = availability.AlwaysUnavailable,
    [tes3.keybind.alwaysRun] = availability.AlwaysUnavailable,
    [tes3.keybind.autoRun] = availability.AlwaysUnavailable,
    [tes3.keybind.jump] = availability.AlwaysUnavailable,
    [tes3.keybind.nextWeapon] = availability.AlwaysUnavailable,
    [tes3.keybind.previousWeapon] = availability.AlwaysUnavailable,
    [tes3.keybind.nextSpell] = availability.AlwaysUnavailable,
    [tes3.keybind.previousSpell] = availability.AlwaysUnavailable,
    [tes3.keybind.togglePOV] = availability.AlwaysUnavailable,
    [tes3.keybind.menuMode] = MenuModeAvailable,
    [tes3.keybind.journal] = MenuModeAvailable, -- later, after got first quest.
    [tes3.keybind.rest] = availability.AlwaysUnavailable, -- later, go outside from office
    [tes3.keybind.quickMenu] = availability.AlwaysUnavailable,
    [tes3.keybind.quick1] = availability.AlwaysUnavailable,
    [tes3.keybind.quick2] = availability.AlwaysUnavailable,
    [tes3.keybind.quick3] = availability.AlwaysUnavailable,
    [tes3.keybind.quick4] = availability.AlwaysUnavailable,
    [tes3.keybind.quick5] = availability.AlwaysUnavailable,
    [tes3.keybind.quick6] = availability.AlwaysUnavailable,
    [tes3.keybind.quick7] = availability.AlwaysUnavailable,
    [tes3.keybind.quick8] = availability.AlwaysUnavailable,
    [tes3.keybind.quick9] = availability.AlwaysUnavailable,
    [tes3.keybind.quick10] = availability.AlwaysUnavailable,
    [tes3.keybind.quickSave] = availability.AlwaysUnavailable,
    [tes3.keybind.quickLoad] = availability.AlwaysUnavailable,
    [tes3.keybind.escape] = availability.AlwaysUnavailable,
    [tes3.keybind.console] = availability.AlwaysUnavailable,
    [tes3.keybind.screenshot] = availability.AlwaysUnavailable,
    [tes3.keybind.readyMagicMCP] = availability.AlwaysUnavailable,
}

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end

    local action = arguments["action"]
    local key = tes3.keybind[action]
    if key == nil or tes3.getInputBinding(key) == nil then
        return false, availability.Unavailable(
            availability.reason.input_binding_unavailable,
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
