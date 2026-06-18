local settings = require("morrowind-mcp.settings")
local config = nil ---@type MCP.MWSEConfig

---@return MCP.MWSEConfig
local function Load()
    config = config or mwse.loadConfig(settings.configPath, settings.defaultConfig)
    return config
end

return Load()
