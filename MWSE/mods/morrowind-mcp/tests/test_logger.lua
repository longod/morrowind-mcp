local this = {}

local function WithMocks(mockConfig, mockSettings, mockLogging, mockDebugGetInfo, callback)
    local originalGetInfo = debug.getinfo
    local originalConfig = package.loaded["morrowind-mcp.config"]
    local originalSettings = package.loaded["morrowind-mcp.settings"]
    local originalLogging = package.loaded["logging.logger"]
    local originalLoggerModule = package.loaded["morrowind-mcp.logger"]

    package.loaded["morrowind-mcp.config"] = mockConfig
    package.loaded["morrowind-mcp.settings"] = mockSettings
    package.loaded["logging.logger"] = mockLogging
    package.loaded["morrowind-mcp.logger"] = nil
    debug.getinfo = mockDebugGetInfo

    local ok, result = pcall(function()
        local loggerFactory = require("morrowind-mcp.logger")
        return callback(loggerFactory)
    end)

    debug.getinfo = originalGetInfo
    package.loaded["morrowind-mcp.config"] = originalConfig
    package.loaded["morrowind-mcp.settings"] = originalSettings
    package.loaded["logging.logger"] = originalLogging
    package.loaded["morrowind-mcp.logger"] = originalLoggerModule

    if not ok then
        error(result)
    end

    return result
end

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    unitwind:start("morrowind-mcp.logger")

    unitwind:test("Get resolves caller filepath automatically", function()
        local captured = nil
        local mockConfig = {
            development = {
                logLevel = mwse.logLevel.info,
                logToConsole = false,
            },
        }
        local mockSettings = {
            modName = "Test Mod",
            modDirRelative = "MWSE\\mods\\sample-mod\\",
            modDir = "Data Files\\MWSE\\mods\\sample-mod\\",
        }
        local mockLogging = {
            new = function(params)
                captured = params
                return {
                    logToConsole = params.logToConsole,
                    setLevel = function()
                    end,
                }
            end,
            getLoggers = function()
                return {}
            end,
        }

        local function MockGetInfo(level, fields)
            if level == 3 then
                return { source = "@E:/tmp/MWSE/mods/sample-mod/logger.lua" }
            end
            if level == 4 then
                return { source = "@E:/tmp/MWSE/mods/sample-mod/subsystems/alpha.lua" }
            end
            return nil
        end

        WithMocks(mockConfig, mockSettings, mockLogging, MockGetInfo, function(loggerFactory)
            loggerFactory.Get({ moduleName = "alpha_module" })
        end)

        unitwind:expect(captured).NOT.toBe(nil)
        if captured then
            unitwind:expect(captured.filepath).toBe("subsystems/alpha.lua")
            unitwind:expect(captured.moduleName).toBe("alpha_module")
            unitwind:expect(captured.modDir).toBe("MWSE\\mods\\sample-mod\\")
            unitwind:expect(captured.level).toBe(mwse.logLevel.info)
            unitwind:expect(captured.logToConsole).toBe(false)
        end
    end)

    unitwind:test("Get keeps explicit filepath when provided", function()
        local captured = nil
        local mockConfig = {
            development = {
                logLevel = mwse.logLevel.debug,
                logToConsole = true,
            },
        }
        local mockSettings = {
            modName = "Test Mod",
            modDirRelative = "MWSE\\mods\\sample-mod\\",
            modDir = "Data Files\\MWSE\\mods\\sample-mod\\",
        }
        local mockLogging = {
            new = function(params)
                captured = params
                return {
                    logToConsole = params.logToConsole,
                    setLevel = function()
                    end,
                }
            end,
            getLoggers = function()
                return {}
            end,
        }

        local function MockGetInfo(level, fields)
            return nil
        end

        WithMocks(mockConfig, mockSettings, mockLogging, MockGetInfo, function(loggerFactory)
            loggerFactory.Get({ moduleName = "custom", filepath = "custom\\path.lua" })
        end)

        unitwind:expect(captured).NOT.toBe(nil)
        if captured then
            unitwind:expect(captured.filepath).toBe("custom/path.lua")
            unitwind:expect(captured.moduleName).toBe("custom")
            unitwind:expect(captured.level).toBe(mwse.logLevel.debug)
            unitwind:expect(captured.logToConsole).toBe(true)
        end
    end)

    unitwind:test("ApplyConfigToAll applies level and logToConsole to all loggers", function()
        local loggerA = {
            logToConsole = false,
            setLevel = function(self, level)
                self.lastLevel = level
            end,
        }
        local loggerB = {
            logToConsole = false,
            setLevel = function(self, level)
                self.lastLevel = level
            end,
        }

        local mockConfig = {
            development = {
                logLevel = mwse.logLevel.info,
                logToConsole = false,
            },
        }
        local mockSettings = {
            modName = "Test Mod",
            modDirRelative = "MWSE\\mods\\sample-mod\\",
            modDir = "Data Files\\MWSE\\mods\\sample-mod\\",
        }
        local mockLogging = {
            new = function(params)
                return {
                    logToConsole = params.logToConsole,
                    setLevel = function()
                    end,
                }
            end,
            getLoggers = function(modDir)
                if modDir == "MWSE\\mods\\sample-mod\\" then
                    return { loggerA, loggerB }
                end
                return {}
            end,
        }

        local function MockGetInfo(level, fields)
            return nil
        end

        WithMocks(mockConfig, mockSettings, mockLogging, MockGetInfo, function(loggerFactory)
            loggerFactory.ApplyConfigToAll({
                level = mwse.logLevel.warn,
                logToConsole = true,
            })
        end)

        unitwind:expect(loggerA.lastLevel).toBe(mwse.logLevel.warn)
        unitwind:expect(loggerB.lastLevel).toBe(mwse.logLevel.warn)
        unitwind:expect(loggerA.logToConsole).toBe(true)
        unitwind:expect(loggerB.logToConsole).toBe(true)
    end)

    unitwind:finish()
end

return this
