local this = {}
this.metadata = toml.loadFile("Data Files\\morrowind-mcp-metadata.toml") ---@type MWSE.Metadata?
this.modName = this.metadata.package.name
this.version = this.metadata.package.version
this.description = this.metadata.package.description
this.repository = this.metadata.package.repository

this.shortModName = "morrowind-mcp"
this.configPath = "morrowind-mcp"
this.dataFiles = "Data Files\\"
this.modDirRelative = "MWSE\\mods\\morrowind-mcp\\"
this.modDir = this.dataFiles .. this.modDirRelative
this.resourceRootDir = this.dataFiles .. this.modDirRelative .. "temp\\"
this.memoryDebugDumpDir = this.dataFiles .. this.modDirRelative .. "memory-dump\\"
this.uriScheme = "morrowind://"
this.name_prefix = "mw-"
this.title_prefix = "[Morrowind] "
this.description_prefix = "[Morrowind] "

---@class MCP.MWSEConfig
this.defaultConfig = {
    disclaimer = 0, -- 0 is not accepted, 1 and above is accepted version.
    server = {
        address = "localhost",
        port = 33427, -- 3E427
    },

    autoplay = {
        skipMainMenu = false,
    },

    development = {
        logLevel = mwse.logLevel.info, ---@type mwseLogger.logLevel
        logToConsole = false,
        unitTest = false,
        debug = false,
    },
}

return this
