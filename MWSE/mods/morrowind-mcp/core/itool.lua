---@class MCP.ITool
---@field definition MCP.Tool
local this = {}

---@param params table?
---@return MCP.ITool
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    ---@type MCP.ITool
    setmetatable(instance, { __index = this })
    return instance
end


---@public
---@param params table
---@return boolean
function this:CanExecute(params)
    return true
end

---@public
---@param params MCP.CallToolRequestParams
---@return MCP.CallToolResult?
function this:Execute(params)
end

return this
