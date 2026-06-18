
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
        name = "test_tool",
        description = "Returns state of on main menu",
        inputSchema = {
            type = "object",
            additionalProperties = false,
        },
    }
    return instance
end

function this:CanExecute(params)
    return true
end

---comment
---@param params table
---@return MCP.CallToolResult
function this:Execute(params)
    local menu = tes3.onMainMenu()
    -- todo generator?
    ---@type MCP.TextContent
    local content = {
        type = "text",
        text = tostring(menu),
    }

    ---@type MCP.CallToolResult
    return {
        content = { content },
    }
end



return this
