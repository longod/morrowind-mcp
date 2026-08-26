
-- teach basic system rules?
-- Z-up 3D open world role-playing game.

-- agent agressivly use morrowind mcp, first read resources, then use tools.

-- Autonomy is defined by required user involvement, not by tool capability.
-- https://arxiv.org/html/2506.12469v2
-- Level 1 Operator: execute only explicitly requested actions; the user owns planning and choices.
-- Level 2 Collaborator: share planning and progress; execute delegated multi-step work and hand back meaningful choices.
-- Level 3 Consultant: plan and execute most work; request preferences, missing information, or direction-changing decisions.
-- Level 4 Approver: complete the objective independently; request approval only for blockers, credentials, consequential actions, or predeclared approval conditions.
-- This interactive Player does not use the paper's Level 5 Observer, where the user can only stop the agent.

-- how to use resources.

-- player agent, game progress skill.


local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")

---@class MCP.Prompts.Instruct : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Instruct
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Instruct
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "instruct" })

    instance.definition = jsonrpc.Prompt({
        name = "instruct",
        description = "Instruct the agent on Morrowind, the MCP, and the autonomy level.",
        -- arguments = jsonrpc.PromptArgument(),
    })

    return instance
end

function this:CanExecute(arguments, context)
    return true
end

function this:Execute(arguments, context)
    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent("placeholder.")
            ),
        },
        nil
    )
end

return this
