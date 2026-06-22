
local base = require("morrowind-mcp.itool")


-- ---@param def MCP.Tool
-- local function AddTypes(def)
--     -- recursive, input, outputSchema
-- end

---@class MCP.TestTool: MCP.ITool
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.TestTool
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.TestTool
    instance.definition = {
        name = "test_tool", -- TODO need prefix?
        description = "Returns state of on main menu",
        inputSchema = {
            type = "object",
            additionalProperties = false,
        },
    }
    return instance
end

function this:CanExecute(params)
    -- only in development mode
    return true
end

function this:Execute(params)
    local menu = tes3.onMainMenu()
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")
    local content = jsonrpc.TextContent(tostring(menu))
    return jsonrpc.CallToolResult(content)
end



return this
