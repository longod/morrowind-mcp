
local base = require("morrowind-mcp.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

---@class MCP.TestTool: MCP.ITool
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.TestTool
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.TestTool
    instance.definition = jsonrpc.Tool({
        name = "test_tool",
        description = "Returns state of on main menu",
        inputSchema = jsonrpc.InputSchema(),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    local config = require("morrowind-mcp.config")
    return config.development.debug
end

function this:Execute(params)
    local menu = tes3.onMainMenu()
    local content = jsonrpc.TextContent(tostring(menu))
    return jsonrpc.CallToolResult(content)
end



return this
