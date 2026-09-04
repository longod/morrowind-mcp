local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local availability = require("morrowind-mcp.core.tool_availability")

    unitwind:start("morrowind-mcp.core.tool_availability")

    unitwind:test("formats required availability lines", function()
        local unavailable = availability.Unavailable(availability.reason.not_in_game, {
            unavailableBecause = "No game is active.",
            availableWhen = "An active game session is loaded.",
        })

        unitwind:expect(unavailable.guidance).toBe(
            "Unavailable because: No game is active.\nAvailable when: An active game session is loaded.")
    end)

    unitwind:test("formats optional related tool lines", function()
        local unavailable = availability.Unavailable(availability.reason.target_not_found, {
            unavailableBecause = "No current activatable target is selected.",
            availableWhen = "The player has a current activatable target.",
            relatedTools = {
                {
                    name = "mw-player-look",
                    relationship = "controls the player's view direction.",
                },
                {
                    name = "mw-target-fetch",
                    relationship = "reports the current target state.",
                },
            },
        })

        unitwind:expect(unavailable.guidance).toBe(
            "Unavailable because: No current activatable target is selected.\n" ..
            "Available when: The player has a current activatable target.\n" ..
            "Related tool: `mw-player-look` controls the player's view direction.\n" ..
            "Related tool: `mw-target-fetch` reports the current target state.")
    end)

    unitwind:test("adds related tools to a shared availability result", function()
        local unavailable = availability.Unavailable(availability.reason.not_in_menu_mode, {
            unavailableBecause = "The game is not in menu mode.",
            availableWhen = "The game is in menu mode.",
        })
        local relatedUnavailable = availability.WithRelatedTools(unavailable, {
            {
                name = "mw-player-fetch",
                relationship = "reports whether the active game is in menu mode.",
            },
        })

        unitwind:expect(unavailable.guidance).toBe(
            "Unavailable because: The game is not in menu mode.\n" ..
            "Available when: The game is in menu mode.")
        unitwind:expect(relatedUnavailable.guidance).toBe(
            "Unavailable because: The game is not in menu mode.\n" ..
            "Available when: The game is in menu mode.\n" ..
            "Related tool: `mw-player-fetch` reports whether the active game is in menu mode.")
    end)

    unitwind:test("formats optional related resource lines", function()
        local unavailable = availability.Unavailable(availability.reason.character_generation_unfinished, {
            unavailableBecause = "Character generation is not complete.",
            availableWhen = "Character generation is complete.",
            relatedResources = {
                {
                    uri = "morrowind://memory/player/index.json",
                    relationship = "reports character-generation state.",
                },
            },
        })

        unitwind:expect(unavailable.guidance).toBe(
            "Unavailable because: Character generation is not complete.\n" ..
            "Available when: Character generation is complete.\n" ..
            "Related resource: `morrowind://memory/player/index.json` reports character-generation state.")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
