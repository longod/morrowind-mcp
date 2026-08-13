---@class MCP.ToolAvailability
---@field reason MCP.ToolAvailabilityReason
---@field guidance string

local this = {}

---@enum MCP.ToolAvailabilityReason
local reason = {
    uninitialized = "uninitialized",
    not_in_game = "not_in_game",
    not_in_menu_mode = "not_in_menu_mode",
    paused_in_menu_mode = "paused_in_menu_mode",
    menu_unavailable = "menu_unavailable",
    character_generation_unfinished = "character_generation_unfinished",
    unsupported = "unsupported",
    -- specified reasons below
    input_binding_unavailable = "input_binding_unavailable",
    target_not_found = "target_not_found",
    movement_unavailable = "movement_unavailable",
    navigation_unavailable = "navigation_unavailable",
    no_active_navigation = "no_active_navigation",
    journal_unavailable = "journal_unavailable",
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
