--- @param e modConfigReadyEventData
local function OnModConfigReady(e)
    local config = require("morrowind-mcp.config")
    local settings = require("morrowind-mcp.settings")
    local template = mwse.mcm.createTemplate(settings.modName)
    template:saveOnClose(settings.configPath, config)
    template:register()

    local page = template:createSideBarPage({
        label = settings.modName,
    })
    local info = page.sidebar:createInfo({
        label = string.format("%s %s",settings.modName, settings.version),
        text = "description",
    })

    -- stop, start, restart buttons
    -- port, server status

    do
        local server = page:createCategory({
            label = "Server",
            description = "Settings for the MCP server.",
        })
        server:createTextField({
            label = "Address",
            description = "The address the server will listen on.",
            variable = mwse.mcm.createTableVariable({
                id = "address",
                table = config.server,
            }),
            restartRequired = true,
        })
        server:createTextField({
            label = "Port",
            description = "The port the server will listen on.",
            variable = mwse.mcm.createTableVariable({
                id = "port",
                table = config.server,
            }),
            restartRequired = true,
            numbersOnly = true,
            converter = function(text)
                local num = tonumber(text)
                if num then
                    --- clamp to valid port range
                    num = math.max(1024, math.min(65535, num))
                    return num
                end
                return config.server.port
            end,
        })
    end

    -- history
    -- dev menu
    do
        local dev = page:createCategory({
            label = "Development",
            description = "Features for development.",
        })
        dev:createDropdown({
            label = "Logging Level",
            description = "Set the logging level. TRACE is the most verbose, and NONE will disable logging.",
            options = {
                { label = "TRACE", value = mwse.logLevel.trace },
                { label = "DEBUG", value = mwse.logLevel.debug },
                { label = "INFO",  value = mwse.logLevel.info },
                { label = "WARN",  value = mwse.logLevel.warn },
                { label = "ERROR", value = mwse.logLevel.error },
                { label = "NONE",  value = mwse.logLevel.none },
            },
            variable = mwse.mcm.createTableVariable({
                id = "logLevel",
                table = config.development,
            }),
            callback = function(self)
                local logger = require("morrowind-mcp.logger")
                logger:setLevel(self.variable.value)
            end
        })
        dev:createOnOffButton({
            label = "Log to Console",
            description = "Log messages to the console.",
            variable = mwse.mcm.createTableVariable({
                id = "logToConsole",
                table = config.development,
            }),
            callback = function(self)
                local logger = require("morrowind-mcp.logger")
                logger.logToConsole = config.development.logToConsole
            end
        })
        dev:createOnOffButton({
            label = "Unit Test",
            description = "Run unit tests on startup.",
            variable = mwse.mcm.createTableVariable({
                id = "unitTest",
                table = config.development,
            }),
        })
        dev:createOnOffButton({
            label = "Debug Mode",
            description = "Enable debug mode.",
            variable = mwse.mcm.createTableVariable({
                id = "debug",
                table = config.development,
            }),
        })
    end

end

event.register(tes3.event.modConfigReady, OnModConfigReady)
