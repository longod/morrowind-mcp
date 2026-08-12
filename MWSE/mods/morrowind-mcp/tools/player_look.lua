local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.core.tool_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local playerController = require("morrowind-mcp.util.player_controller")
local playerLook = require("morrowind-mcp.util.player_look")

local minimumYawDegrees = -180
local maximumYawDegrees = 180
local minimumPitchDegrees = -89
local maximumPitchDegrees = 89

---@class MCP.Tools.PlayerLook: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

--- Create the player-look tool definition and logger.
---@param params table?
---@return MCP.Tools.PlayerLook
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.PlayerLook
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "player_look" })
    instance.definition = jsonrpc.Tool({
        name = "player-look",
        description = "Direct the player view at an active reference or to absolute world-space angles. Any active player navigation is cancelled before the view is applied.",
        inputSchema = jsonrpc.InputSchema({
            mode = jsonrpc.UntitledSingleSelectEnumSchema(
                { "target", "angles" },
                "Mode",
                "target looks at the nearest active reference with target_id. angles uses absolute yaw and pitch in degrees.",
                "target"
            ),
            target_id = jsonrpc.StringSchema(
                "Target ID",
                "Required for target mode. Matches active-cell reference base IDs; nearest matching reference is used.",
                1,
                255
            ),
            yaw = jsonrpc.NumberSchema(
                "Yaw",
                "Required for angles mode. Absolute compass heading in degrees: 0 is north and 90 is east.",
                minimumYawDegrees,
                maximumYawDegrees
            ),
            pitch = jsonrpc.NumberSchema(
                "Pitch",
                "Required for angles mode. Absolute vertical angle in degrees; positive values look upward.",
                minimumPitchDegrees,
                maximumPitchDegrees
            ),
        }, jsonrpc.array({ "mode" })),
        outputSchema = jsonrpc.OutputSchema({
            yaw = jsonrpc.NumberSchema("Yaw", "Applied absolute yaw in degrees."),
            pitch = jsonrpc.NumberSchema("Pitch", "Applied absolute pitch in degrees."),
            target_id = jsonrpc.StringSchema("Target ID", "Resolved target ID when mode is target."),
            target_point_kind = jsonrpc.StringSchema("Target Point Kind", "Method used to select the target look point."),
            navigation_cancelled = jsonrpc.BooleanSchema("Navigation Cancelled", "Whether an active player navigation route was cancelled before looking."),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),
    })
    return instance
end

--- Describe the live-game state required to apply a player view change.
---@return string
function this:GetCapabilityConditions()
    return "A game must be active and the player must be loaded. Target mode requires a matching reference in an active cell."
end

--- Reject calls while no active player and player mobile are available.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    if tes3.onMainMenu() then
        return false, availability.Unavailable(availability.reason.gameNotActive, "Start or continue a game.")
    end
    if not tes3.player or not tes3.mobilePlayer then
        return false, availability.Unavailable(availability.reason.playerUnavailable, "Wait until the player has loaded.")
    end
    return true
end

--- Validate mutually exclusive mode-specific arguments that JSON Schema cannot express.
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    local arguments = params.arguments or {}
    if arguments["mode"] == "target" then
        if arguments["target_id"] == nil then
            table.insert(result.errors, { path = "target_id", message = "target_id is required for target mode." })
            result.valid = false
        end
        if arguments["yaw"] ~= nil or arguments["pitch"] ~= nil then
            table.insert(result.errors, { path = "$", message = "yaw and pitch are only valid for angles mode." })
            result.valid = false
        end
    elseif arguments["mode"] == "angles" then
        if arguments["yaw"] == nil or arguments["pitch"] == nil then
            table.insert(result.errors, { path = "$", message = "yaw and pitch are required for angles mode." })
            result.valid = false
        end
        if arguments["target_id"] ~= nil then
            table.insert(result.errors, { path = "target_id", message = "target_id is only valid for target mode." })
            result.valid = false
        end
    end
    return result
end

--- Cancel active server navigation before directly setting the view, then apply the requested look operation.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local target = nil
    if arguments["mode"] == "target" then
        -- Resolve the target before disrupting navigation so a missing ID has no movement side effect.
        target = playerLook.ResolveTarget(arguments["target_id"])
        if not target then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("The requested target was not found in active cells."), nil, true)
        end
    end

    local navigationCancelled = false
    if context and context.HasActivePlayerNavigation and context.HasActivePlayerNavigation() then
        if not context.CancelPlayerNavigation or not context.CancelPlayerNavigation() then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Failed to cancel active player navigation."), nil, true)
        end
        navigationCancelled = true
    end

    local controller = playerController.new()
    local ok = false
    local yaw = nil
    local pitch = nil
    local targetId = nil
    local targetPointKind = nil
    if arguments["mode"] == "target" then
        targetId = arguments["target_id"]
        target = target ---@cast target MCP.PlayerLookTarget
        ok, yaw, pitch = controller:LookAtPoint(target.point)
        targetPointKind = target.pointKind
    else
        ok, yaw, pitch = controller:SetLookAngles(arguments["yaw"], arguments["pitch"])
    end
    if not ok then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Failed to set the player view."), nil, true)
    end

    local structuredContent = jsonrpc.object({
        yaw = yaw,
        pitch = pitch,
        target_id = targetId,
        target_point_kind = targetPointKind,
        navigation_cancelled = navigationCancelled,
    })
    return jsonrpc.CallToolResult(jsonrpc.TextContent("Player view updated."), structuredContent, false)
end

return this
