
local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")

--- plan to go to destination. how to get there.
---@class MCP.Prompts.Navigate : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Navigate
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Navigate
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "navigte" })

    instance.definition = jsonrpc.Prompt({
        name = "navigate",
        description = "Find directions to your destination.",
        -- arguments = jsonrpc.PromptArgument(),
    })

    return instance
end

function this:CanExecute(arguments, context)
    if tes3.onMainMenu() then
        return false
    end
    -- exclude tutorial?
    return true
end

function this:Execute(arguments, context)
    -- if on mainmenu, search save data?
    if tes3.onMainMenu() then
        return nil
    end
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("Navigate to a destination. Give me directions to a location or quest objective.")
            ),
        },
        nil
    )
end

return this
