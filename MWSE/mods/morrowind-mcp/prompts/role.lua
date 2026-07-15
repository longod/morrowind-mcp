

local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")


---@class MCP.Prompts.Role : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Role
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Role
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "role" })

    instance.definition = jsonrpc.Prompt({
        name = "role",
        description = "Role-play the character in Morrowind.",
        -- arguments = jsonrpc.PromptArgument(), -- what
    })

    -- role-play character from background.
    -- or assistant avator in game
    -- or general chat

    -- player character, specific character, or random character
    -- game master. system guide.tour guide.
    -- book, journal writer, or quest giver. random npc.

    return instance
end

function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    -- on loaded
    -- done tutorial character making
    return true
end

function this:Execute(params, context)
    if tes3.onMainMenu() then
        return nil -- error
    end
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("In this session, you are a player character in the world of Morrowind. You will read `player.json` and adopt that character's tone and behavior.")
            ),
            -- add assistant message?
        },
        nil
    )
end

return this
