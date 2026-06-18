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
---@param params table
---@return MCP.CallToolResult?
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
