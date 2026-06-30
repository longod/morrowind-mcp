local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local serializer = require("morrowind-mcp.serializer")


---@class MCP.JournalFetch: MCP.ITool
---@field logger mwseLogger
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
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    -- in title?
    return true
end

function this:Execute(params)

    -- load <Morrowind>/Journal.htm ?
    -- perphaps, we can not access to journal entries in a save data.
    -- "JOUR"  recourds in ess stores just html same as journal.htm.
    -- https://en.uesp.net/morrow/tech/mw_esm.txt

    local path = tes3.installDirectory .. "\\Journal.htm"
    if lfs.attributes(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            -- TODO format markdown or json?
            local content = jsonrpc.TextContent(content)
            return jsonrpc.CallToolResult(content)
        else
            local errorContent = jsonrpc.TextContent("failed to open Journal.htm.")
            return jsonrpc.CallToolResult(errorContent, nil)
        end
    else
        local errorContent = jsonrpc.TextContent("Journal.htm not found.")
        return jsonrpc.CallToolResult(errorContent, nil)
    end

end

return this
