local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.StaticFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.StaticFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.StaticFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "static_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "static-fetch",
        description =
        "Fetch active statics in current cells.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                statics = jsonrpc.JsonArraySchema(),
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
    local cells = tes3.getActiveCells()
    if not cells then
        local errorContent = jsonrpc.TextContent("no active cells found. Please enter a cell first.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    local size = 0
    for _, cell in ipairs(cells) do
        size = size + cell.statics.size
    end
    local statics = jsonrpc.array(size)
    for _, cell in ipairs(cells) do
        for ref in iter.ForEachReferenceList(cell.statics) do
            if ref:isValid() then
                local o = obj.tes3reference(ref)
                if o then
                    table.insert(statics, o)
                end
            end
        end
    end

    local structuredContent = jsonrpc.object({ statics = statics })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
