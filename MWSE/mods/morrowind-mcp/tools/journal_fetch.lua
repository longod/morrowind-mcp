local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local datetime = require("morrowind-mcp.datetime")
local journal = require("morrowind-mcp.resources.journal")

-- improving resource management then maybe no nessessary to fetch some data.
-- possibly too many tools cause dump AI decision.
-- but manual fetch is useful for debugging and testing.


---@class MCP.JournalFetch: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager TODO use MCP.IResourceManager
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.JournalFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.JournalFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "journal_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "journal-fetch",
        description =
        "Fetch active journal entries.",
        inputSchema = jsonrpc.InputSchema(
        -- active,
        -- finished, unfinished
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                entries = jsonrpc.JsonArraySchema(),
                current_time = jsonrpc.JsonObjectSchema(),
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
    -- exclude tutorial?
    return true
end

function this:Execute(params, context)

    local entries = journal.ReadJournal()
    if not entries then
        local errorContent = jsonrpc.TextContent("Failed to read journal entries.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local currentTime = datetime.InGameNow()
    local structuredContent = jsonrpc.object({
        entries = entries,
        current_time = currentTime,
    })
    return jsonrpc.CallToolResult(nil, structuredContent)

end

return this
