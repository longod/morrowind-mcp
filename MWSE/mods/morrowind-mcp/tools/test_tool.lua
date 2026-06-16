
local base = require("morrowind-mcp.itool")


---@param def MCP.ToolDefinition
local function AddTypes(def)
    -- recursive, input, outputSchema
end

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

function this:Execute(params)
end



return this
