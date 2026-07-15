
-- search and tell active quests walkthrough. how to do

local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")

---@class MCP.Prompts.Walkthrough : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Walkthrough
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Walkthrough
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "walkthrough" })

    instance.definition = jsonrpc.Prompt({
        name = "walkthrough",
        description = "Give me some tips on how to beat the game.",
        -- arguments = jsonrpc.PromptArgument(), -- what
    })

    -- in game only, reveal non started journal index. read script plain text.
    -- active, next quest estimation. main quest...
    return instance
end

function this:CanExecute(params)
    return true
end

function this:Execute(params, context)
    -- add quest name, id.
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("Give me some tips on how to beat the game. search a atctive quest on uesp.net.")
            ),
            -- add assistant message?
        },
        nil
    )
end

return this
