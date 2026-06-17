local this = {}
this.metadata = toml.loadFile("Data Files\\morrowind-mcp-metadata.toml") ---@type MWSE.Metadata?
this.modName = this.metadata.package.name
this.version = this.metadata.package.version
this.description = this.metadata.package.description
this.configPath = "morrowind-mcp"

---@class Config
this.defaultConfig = {
    server = {
        address = "localhost",
        port = 33427, -- 3E427
    },

    ---@class Config.Development
    development = {
        logLevel = mwse.logLevel.info, ---@type mwseLogger.logLevel
        logToConsole = false,
        -- test
    },
}

return this
