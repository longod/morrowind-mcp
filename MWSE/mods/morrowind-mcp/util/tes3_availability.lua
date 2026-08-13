local av = require("morrowind-mcp.core.tool_availability")

-- reusable function to check if a tool is available condittions.
---@class MCP.TES3Availability
local this = {}

-- ailas
this.reason = av.reason
this.Unavailable = av.Unavailable

---@return boolean
---@return MCP.ToolAvailability?
function this.AlwaysAvailable()
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
function this.AlwaysUnavailable()
    return false,
        av.Unavailable(
            av.reason.unsupported,
            "It's unsupported.")
end

---@return boolean
---@return MCP.ToolAvailability?
function this.IsInitialized()
    if not tes3.isInitialized() then
        return false,
        av.Unavailable(
            av.reason.uninitialized,
            "Wait a moment while the system initialized."
        )
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
function this.IsInGame()
    if tes3.onMainMenu() then
        return false,
            av.Unavailable(
                av.reason.not_in_game,
                "Start, load or continue a game."
            )
    end
    if not tes3.player or not tes3.mobilePlayer or not tes3.getActiveCells() then
        return false,
            av.Unavailable(
                av.reason.not_in_game,
                "Wait until the game has loaded."
            )
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
function this.PausedInMenuMode()
    -- tes3.menuMode() contains on main menu.
    if not tes3.menuMode() then
        return false,
            av.Unavailable(
                av.reason.not_in_menu_mode,
                "Enter the menu mode using `mw-player-action`. This action with args is available only when the menu is displayed in the menu mode."
            )
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
function this.NotInMenuMode()
    -- tes3.menuMode() contains on main menu.
    if tes3.menuMode() then
        return false,
            av.Unavailable(
                av.reason.paused_in_menu_mode,
                "Leave the menu mode or close dialog. This action with args is available only when the menu mode is not paused. Call `mw-meun-fetch` to get the menu path of the element you want to interact with."
            )
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
function this.IsCharGenFinished()
    if not tes3.isCharGenFinished() then
        return false,
            av.Unavailable(
                av.reason.character_generation_unfinished,
                "Finish character generation first."
            )
    end
    return true
end
return this
