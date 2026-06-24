local this = {}
this.metadata = toml.loadFile("Data Files\\morrowind-mcp-metadata.toml") ---@type MWSE.Metadata?
this.modName = this.metadata.package.name
this.version = this.metadata.package.version
this.description = this.metadata.package.description
this.repository = this.metadata.package.repository
this.configPath = "morrowind-mcp"
this.dataFiles = "Data Files\\"
this.modDirRelative = "MWSE\\mods\\morrowind-mcp\\"
this.modDir = this.dataFiles .. this.modDirRelative
this.screenshotDir = this.dataFiles .. "mworrowind-mcp\\"
this.resourceUriPrefix = "mwmcp://data-files/"
this.name_prefix = "mw_"
this.title_prefix = "[Morrowind] "
this.description_prefix = "[Morrowind] "

---@class MCP.MWSEConfig
this.defaultConfig = {
    server = {
        address = "localhost",
        port = 33427, -- 3E427
    },

    ---@class MCP.MWSEConfig.Development
    development = {
        logLevel = mwse.logLevel.info, ---@type mwseLogger.logLevel
        logToConsole = false,
        unitTest = false,
        debug = false,
    },
}

return this
