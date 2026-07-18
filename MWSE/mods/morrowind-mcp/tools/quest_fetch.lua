local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local quest = require("morrowind-mcp.resources.quest")

---@class MCP.Tools.QuestFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.QuestFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.QuestFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "quest_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "quest-fetch",
        description =
        "Fetch active quests.",
        inputSchema = jsonrpc.InputSchema(
            {
                is_started = jsonrpc.BooleanSchema(
                    "Is Started",
                    "Filter quests by started state. If not specified, quests will not be filtered by started state."
                ),
                is_active = jsonrpc.BooleanSchema(
                    "Is Active",
                    "Filter quests by active state. If not specified, quests will not be filtered by active state."
                ),
                is_finished = jsonrpc.BooleanSchema(
                    "Is Finished",
                    "Filter quests by finished state. If not specified, quests will not be filtered by finished state."
                ),
            }
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                quests = jsonrpc.JsonArraySchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    return true
end

function this:Execute(params, context)
    local arguments = params.arguments or {}
    local isStarted = arguments["is_started"]
    local isActive = arguments["is_active"]
    local isFinished = arguments["is_finished"]

    local entries = quest.FindQuests(isStarted, isActive, isFinished)

    local structuredContent = jsonrpc.object({ quests = entries })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
