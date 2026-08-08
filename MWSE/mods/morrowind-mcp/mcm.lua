--- @param e modConfigReadyEventData
local function OnModConfigReady(e)
    local config = require("morrowind-mcp.config")
    local disclaimer = require("morrowind-mcp.disclaimer")
    local settings = require("morrowind-mcp.settings")
    local template = mwse.mcm.createTemplate(settings.modName)
    template:saveOnClose(settings.configPath, config)
    template:register()

    local page = template:createSideBarPage({
        label = settings.modName,
    })
    page.sidebar:createInfo({
        label = string.format("%s Version: %s", settings.modName, settings.version),
        text = settings.description,
    })
    -- page.sidebar:createHyperlink({
    --     text = "Nexus Mods Page",
    --     url = settings.metadata.package.homepage,
    -- })
    page.sidebar:createHyperlink({
        text = "GitHub Repository",
        url = settings.metadata.package.repository,
    })
    page.sidebar:createInfo({
        label = string.format("%s Version: %d", disclaimer.header, disclaimer.version),
        text = disclaimer.text,
    })
    page.sidebar:createHyperlink({
        text = "Full Disclaimer (GitHub)",
        url = settings.metadata.package.repository .. "/blob/main/README.md#disclaimer",
    })
    -- stop, start, restart buttons
    -- port, server status

    do
        local server = page:createCategory({
            label = "Server",
            description = "Settings for this MCP server.",
        })
        server:createTextField({
            label = "Address",
            description = "The address this server will listen on.",
            variable = mwse.mcm.createTableVariable({
                id = "address",
                table = config.server,
            }),
            restartRequired = true,
        })
        server:createTextField({
            label = "Port",
            description = "The port this server will listen on.",
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

    do
        local notification = page:createCategory({
            label = "Notification",
            description = "Features for notifications.",
        })
        notification:createOnOffButton({
            label = "Show Subtitles (Recommended)",
            description =
            "Since the agent will be able to capture the speech as text, it will be able to recognize it.",
            variable = mwse.mcm.createTableVariable({
                id = "showSubtitles",
                table = config.notification,
            }),
            callback = function(self)
                -- no restore, original value is unknown.
                if self.variable.value then
                    tes3.showSubtitles = true
                end
            end
        })
        notification:createOnOffButton({
            label = "Navigation",
            description =
            "Notifies when navigation starts, ends, or is canceled. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "navigation",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Tools Call",
            description =
            "Notifies when a tool is called and executed. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "toolsCall",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Resources Read",
            description =
            "Notifies when a resource is read. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "resourcesRead",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Resources Subscribe",
            description =
            "Notifies when a resource is subscribed. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "resourcesSubscribe",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Resources Unsubscribe",
            description =
            "Notifies when a resource is unsubscribed. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "resourcesUnsubscribe",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Prompts Get",
            description =
            "Notifies when a prompt is got. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "promptsGet",
                table = config.notification,
            }),
        })
        notification:createOnOffButton({
            label = "Errors",
            description =
            "Notifies the client of request errors or internal server errors. While this is meaningful to the player, agents may misinterpret it.",
            variable = mwse.mcm.createTableVariable({
                id = "errors",
                table = config.notification,
            }),
        })
    end

    do
        local autoplay = page:createCategory({
            label = "Autoplay",
            description = "Features for autoplay support.",
        })
        autoplay:createOnOffButton({
            label = "Disable Vanity Camera (Recommended)",
            description =
            "This is effective in preventing the agent from mistakenly believing that the situation has changed due to its own actions when it transitions to vanity mode.",
            variable = mwse.mcm.createTableVariable({
                id = "vanityDisabled",
                table = config.autoplay,
            }),
            callback = function(self)
                -- no restore, original value is unknown.
                if self.variable.value then
                    tes3.vanityDisabled = true
                end
            end
        })
        autoplay:createOnOffButton({
            label = "Automatic Continue",
            description =
            "After launching the game, the main menu will be automatically skipped, and the latest save file will be loaded.\nImportant: If you want to disable this feature, press the ESC key to open the Options menu and navigate to “MOD Settings.” Alternatively, delete this MOD's configuration file (Data Files/MWSE/config/morrowind-mcp.json).",
            variable = mwse.mcm.createTableVariable({
                id = "skipMainMenu",
                table = config.autoplay,
            }),
            restartRequired = true,
        })
    end

    -- history
    -- dev menu
    do
        local dev = page:createCategory({
            label = "Development",
            description = "Features for development.",
        })
        dev:createOnOffButton({
            label = "Cell Borders",
            description = "Show cell borders in the world.",
            variable = mwse.mcm.createTableVariable({
                id = "cellBorder",
                table = config.notification,
            }),
            callback = function(self)
                tes3.worldController.menuController.bordersEnabled = self.variable.value
            end
        })
        dev:createOnOffButton({
            label = "Collision Boxes",
            description = "Show collision boxes in the world.",
            variable = mwse.mcm.createTableVariable({
                id = "collisionBox",
                table = config.notification,
            }),
            callback = function(self)
                tes3.worldController.menuController.collisionBoxesEnabled = self.variable.value
            end
        })
        dev:createOnOffButton({
            label = "Path Grid",
            description =
            "Show path grids in the world. but there is a bug where only pathgrids that have already been loaded are rendered.",
            variable = mwse.mcm.createTableVariable({
                id = "pathGrid",
                table = config.notification,
            }),
            callback = function(self)
                tes3.worldController.menuController.pathGridShown = self.variable.value
            end
        })
        dev:createLogLevelOptions({
            variable = mwse.mcm.createTableVariable({
                id = "logLevel",
                table = config.development,
            }),
            callback = function(self)
                local loggerFactory = require("morrowind-mcp.logger")
                loggerFactory.ApplyConfigToAll({ level = self.variable.value })
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
                local loggerFactory = require("morrowind-mcp.logger")
                loggerFactory.ApplyConfigToAll({ logToConsole = self.variable.value })
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
