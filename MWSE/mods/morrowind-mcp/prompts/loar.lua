local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")

-- prompt to search loar from UESP.
-- https://www.mediawiki.org/wiki/API:REST_API
-- https://en.uesp.net/wiki/Main_Page
-- https://elderscrolls.fandom.com/wiki/The_Elder_Scrolls_Wiki
-- only in morrowind era
-- only in game time
-- contain old and future

-- search api or just suggest url?
-- do not spam, need to cache and interval.
-- convert space to underscore, and remove special characters.

-- target or pointing

-- just search uesp.net, ok.


---@class MCP.Prompts.Loar : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Loar
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Loar
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "loar" })

    instance.definition = jsonrpc.Prompt({
        name = "loar",
        description = "Tell me about loar of this.",
        -- arguments = jsonrpc.PromptArgument(), -- what
    })
    -- or random entity?
    -- search wiki is optional?
    -- only in game info option? from current active dilaogue info.
    -- or non loar info. (prompt name mismatch)

    return instance
end

function this:CanExecute(params)
    -- if tes3.onMainMenu() then
    --     return false
    -- end
    -- exclude tutorial?
    return true
end

function this:Execute(params, context)
    if tes3.onMainMenu() then
        return jsonrpc.GetPromptResult(
            {
                jsonrpc.PromptMessage(
                    mcp.role.user,
                    jsonrpc.TextContent("Tell me about loar of Morrowind.")
                ),
            },
            nil
        )
    end
    -- TODO last targeting entity, fill this name
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("Tell me about loar of this. search loar page on `uesep.net` or `elderscrolls.fandom.com`")
            ),
        },
        nil
    )
end

return this
