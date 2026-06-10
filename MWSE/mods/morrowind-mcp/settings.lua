local this = {}
this.metadata = toml.loadFile("Data Files\\morrowind-mcp-metadata.toml") ---@type MWSE.Metadata?
this.modName = this.metadata.package.name
this.version = this.metadata.package.version
this.configPath = "morrowind-mcp"

---@class Config
this.defaultConfig = {
    port = 45024,

    ---@class Config.Development
    development = {
        logLevel = mwse.logLevel.info, ---@type mwseLogger.logLevel
        logToConsole = false,
    }
}

return this
