

local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")


-- prompt to translate dialogue.
-- re-write text in menu if possible, multibyte character (CJK) is not supported.

---@class MCP.Prompts.Translate : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Translate
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Translate
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "translate" })

    instance.definition = jsonrpc.Prompt({
        name = "translate",
        description = "Translate it!",
        -- arguments = jsonrpc.PromptArgument(), -- what
    })

    -- target?
    -- other specific language. or auto detect.
    return instance
end

function this:CanExecute(params)
    return true
end

function this:Execute(params, context)
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("In this session, always speak using the system language set in your OS settings. Translate this into the system language.")
            ),
            -- add assistant message?
        },
        nil
    )
end

return this
