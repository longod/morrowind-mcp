local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local serializer = require("morrowind-mcp.serializer")


---@class MCP.QuestFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.QuestFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.QuestFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "quest_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "quest-fetch",
        description =
        "Fetch active quests.",
        inputSchema = jsonrpc.InputSchema(
            -- active,
            -- finished, unfinished
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
    -- in title?
    return true
end

function this:Execute(params, context)

    -- contain all quests.
    local quests = tes3.worldController.quests
    local array = jsonrpc.array(table.size(quests))
    for _, quest in ipairs(quests) do
        if quest:isValid() then
            local o = serializer.tes3quest(quest)
            if o then
                table.insert(array, o)
            end
        end
    end

    local structuredContent = jsonrpc.object({ quests = array })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
