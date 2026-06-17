---@class MCP.ITool
---@field definition MCP.ToolDefinition
local this = {}

---@class MCP.PrimitiveDefinition
---@field name string Unique identifier for the tool
---@field title string? Optional human-readable name of the tool for display purposes.
---@field description string Human-readable description of functionality
---@field icons MCP.Icon[]? Optional array of icons for display in user interfaces


---https://modelcontextprotocol.io/specification/2025-11-25/server/tools#tool
---@class MCP.ToolDefinition: MCP.PrimitiveDefinition
---@field inputSchema MCP.InputSchema JSON Schema defining expected parameters
---@field outputSchema MCP.OutputSchema? Optional JSON Schema defining expected output structure
---@field annotations table? Optional properties describing tool behavior


---https://modelcontextprotocol.io/specification/2025-11-25/basic#schema-dialect
---@class MCP.JSONSchema2020-12
---@field type string


---@class MCP.InputSchema: MCP.JSONSchema2020-12
---@field properties table<MCP.JSONSchema2020-12>?
---@field required string[]?
---@field additionalProperties boolean?

---@class MCP.OutputSchema: MCP.JSONSchema2020-12
---@field properties table<MCP.JSONSchema2020-12>
---@field required string[]?

--- https://modelcontextprotocol.io/specification/2025-11-25/schema

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
---@param params table
---@return table?
function this:Execute(params)
end

return this


--[[
{
  "name": "get_weather_data",
  "title": "Weather Data Retriever",
  "description": "Get current weather data for a location",
  "inputSchema": {
    "type": "object",
    "properties": {
      "location": {
        "type": "string",
        "description": "City name or zip code"
      }
    },
    "required": ["location"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "temperature": {
        "type": "number",
        "description": "Temperature in celsius"
      },
      "conditions": {
        "type": "string",
        "description": "Weather conditions description"
      },
      "humidity": {
        "type": "number",
        "description": "Humidity percentage"
      }
    },
    "required": ["temperature", "conditions", "humidity"]
  },
  "icons": [
    {
      "src": "https://example.com/weather-icon.png",
      "mimeType": "image/png",
      "sizes": ["48x48"]
    }
  ],
  "execution": {
    "taskSupport": "optional"
  }
}
--]]
