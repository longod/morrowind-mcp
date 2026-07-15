local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")
local journal = require("morrowind-mcp.resources.journal")
local quest = require("morrowind-mcp.resources.quest")

---@class MCP.Prompts.Todo : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Todo
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Todo
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "todo" })

    instance.definition = jsonrpc.Prompt({
        name = "todo",
        description = "Tell me what to do next.",
        -- arguments = jsonrpc.PromptArgument(),
    })

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
    -- if on mainmenu, search save data?
    if tes3.onMainMenu() then
        return jsonrpc.GetPromptResult(
            {
                jsonrpc.PromptMessage(
                    mcp.role.user,
                    jsonrpc.TextContent("Tell me what to do next on main menu.")
                ),
                -- save list?
                -- menu?
            },
            nil
        )
    end
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("Tell me what to do next. read journal and active_quest resources")
            ),
            -- depends on client implementation?
            jsonrpc.PromptMessage(
                mcp.role.user,
                journal.link
            ),
            jsonrpc.PromptMessage(
                mcp.role.user,
                quest.active_link
            ),
        },
        nil
    )
end

return this
