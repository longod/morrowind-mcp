local av = require("morrowind-mcp.core.tool_availability")

-- reusable function to check if a tool is available condittions.
---@class MCP.TES3Availability
local this = {}

-- ailas
this.reason = av.reason
this.Unavailable = av.Unavailable
this.WithRelatedTools = av.WithRelatedTools

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
            {
                unavailableBecause = "The requested action is unsupported by this tool.",
                availableWhen = "The tool exposes support for the requested action.",
            })
end

---@return boolean
---@return MCP.ToolAvailability?
function this.IsInitialized()
    if not tes3.isInitialized() then
        return false,
        av.Unavailable(
            av.reason.uninitialized,
            {
                unavailableBecause = "The Morrowind runtime is not initialized.",
                availableWhen = "The Morrowind runtime is initialized.",
            }
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
                {
                    unavailableBecause = "The game is on the main menu.",
                    availableWhen = "An active game session is loaded.",
                }
            )
    end
    if not tes3.player or not tes3.mobilePlayer or not tes3.getActiveCells() then
        return false,
            av.Unavailable(
                av.reason.not_in_game,
                {
                    unavailableBecause = "The game is still loading.",
                    availableWhen = "Game loading is complete.",
                }
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
                {
                    unavailableBecause = "The game is not in menu mode.",
                    availableWhen = "The game is in menu mode.",
                    relatedTools = {
                        {
                            name = "mw-player-fetch",
                            relationship = "reports whether the active game is in menu mode.",
                        },
                    },
                }
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
                {
                    unavailableBecause = "The game is in menu mode.",
                    availableWhen = "The game is outside menu mode.",
                    relatedTools = {
                        {
                            name = "mw-player-fetch",
                            relationship = "reports whether the active game is in menu mode.",
                        },
                    },
                }
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
                {
                    unavailableBecause = "Character generation is not complete.",
                    availableWhen = "Character generation is complete.",
                    relatedResources = {
                        {
                            uri = "morrowind://memory/player/index.json",
                            relationship = "reports character-generation state.",
                        },
                    },
                }
            )
    end
    return true
end
return this
