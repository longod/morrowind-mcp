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
                { label = "TRACE", value = "TRACE" },
                { label = "DEBUG", value = "DEBUG" },
                { label = "INFO",  value = "INFO" },
                { label = "WARN",  value = "WARN" },
                { label = "ERROR", value = "ERROR" },
                { label = "NONE",  value = "NONE" },
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
    end

end

event.register(tes3.event.modConfigReady, OnModConfigReady)
