local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local serializer = require("morrowind-mcp.serializer")


---@class MCP.ActivatorFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.ActivatorFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.ActivatorFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "activator_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "activator-fetch",
        description =
        "Fetch active activators in current cells.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                activators = jsonrpc.JsonArraySchema(),
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
    -- it seems always returns non nil array, but it contains only valid references.
    local cells = tes3.getActiveCells()
    if not cells then
        local errorContent = jsonrpc.TextContent("no active cells found. Please enter a cell first.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    local size = 0
    for _, cell in ipairs(cells) do
        size = size + cell.activators.size
    end
    local activators = jsonrpc.array(size)
    for _, cell in ipairs(cells) do
        for ref in serializer.ForEachReferenceList(cell.activators) do
            if ref:isValid() then
                local o = serializer.tes3reference(ref)
                if o then
                    table.insert(activators, o)
                end
            end
        end
    end

    local structuredContent = jsonrpc.object({ activators = activators })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
