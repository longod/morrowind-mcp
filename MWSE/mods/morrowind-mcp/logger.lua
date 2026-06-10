local config = require("morrowind-mcp.config")

local logger = require("logging.logger").new({
    modName = "morrowind-mcp",
    level = config.development.logLevel,
    logToConsole = config.development.logToConsole,
    includeTimestamp = true,
})

return logger
