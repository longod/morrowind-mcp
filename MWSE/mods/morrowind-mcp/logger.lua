local config = require("morrowind-mcp.config")

local logger = require("logging.logger").new({
    name = "morrowind-mcp",
    logLevel = config.development.logLevel,
    logToConsole = config.development.logToConsole,
    includeTimestamp = true,
})

return logger
