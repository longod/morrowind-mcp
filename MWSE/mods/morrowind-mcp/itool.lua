---@class ITool
---@field name string Unique identifier for the tool
---@field title string? Optional human-readable name of the tool for display purposes.
---@field description string Human-readable description of functionality
---@field icons table? Optional array of icons for display in user interfaces
---@field inputSchema table JSON Schema defining expected parameters
---@field outputSchema table? Optional JSON Schema defining expected output structure
---@field annotations table? Optional properties describing tool behavior
local this = {}

---@protected
---@param params table?
---@return ITool
function this.new(params)
    ---@type ITool
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end


return this
