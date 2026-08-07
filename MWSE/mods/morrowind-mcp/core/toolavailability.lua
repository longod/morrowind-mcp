---@class MCP.ToolAvailability
---@field reason MCP.ToolAvailabilityReason
---@field guidance string

local this = {}

---@enum MCP.ToolAvailabilityReason
local reason = {
    gameNotActive = "game_not_active",
    menuControllerUnavailable = "menu_controller_unavailable",
    noActiveCells = "no_active_cells",
    playerUnavailable = "player_unavailable",
    inputBindingUnavailable = "input_binding_unavailable",
    navigationUnavailable = "navigation_unavailable",
    noActiveNavigation = "no_active_navigation",
}

this.reason = reason

--- Create the structured explanation returned when a tool cannot run.
---@param reason MCP.ToolAvailabilityReason
---@param guidance string
---@return MCP.ToolAvailability
function this.Unavailable(reason, guidance)
    return {
        reason = reason,
        guidance = guidance,
    }
end

return this
