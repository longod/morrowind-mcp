local config = require("morrowind-mcp.config")
local settings = require("morrowind-mcp.settings")
local mwseLogger = require("logging.logger")

local this = {}

---@return string[]
local function BuildPathMarkers()
    local markers = {}
    if settings.modDirRelative then
        local normalizedRelative = settings.modDirRelative:gsub("\\", "/"):lower()
        table.insert(markers, normalizedRelative)
    end
    if settings.modDir then
        local normalizedModDir = settings.modDir:gsub("\\", "/"):lower()
        table.insert(markers, normalizedModDir)
    end
    return markers
end

local pathMarkers = BuildPathMarkers()

---@param path string
---@return string
local function NormalizePath(path)
    local normalizedPath = path:gsub("\\", "/")
    local lowerPath = normalizedPath:lower()
    for _, marker in ipairs(pathMarkers) do
        local markerIndex = lowerPath:find(marker, 1, true)
        if markerIndex then
            return normalizedPath:sub(markerIndex + #marker)
        end
    end
    return normalizedPath
end

---@return string?
local function ResolveCallerFilepath()
    -- Stack levels 3+ should include caller sites outside this factory.
    for stackLevel = 3, 12 do
        local info = debug.getinfo(stackLevel, "S")
        if info and info.source and info.source:sub(1, 1) == "@" then
            local source = info.source:sub(2)
            local normalizedPath = NormalizePath(source)
            local lowerPath = normalizedPath:lower()
            if lowerPath ~= "logger.lua" and not lowerPath:find("/logger.lua", 1, true) then
                return normalizedPath
            end
        end
    end
    return nil
end

---@class MCP.LoggerFactoryOptions
---@field moduleName string?
---@field filepath string?
---@field includeTimestamp boolean?

---@param options MCP.LoggerFactoryOptions?
---@return mwseLogger
function this.Get(options)
    options = options or {}
    local filepath = options.filepath and NormalizePath(options.filepath) or ResolveCallerFilepath()

    local logger = mwseLogger.new({
        modName = settings.modName,
        modDir = settings.modDirRelative,
        moduleName = options.moduleName,
        filepath = filepath,
        level = config.development.logLevel,
        logToConsole = config.development.logToConsole,
        includeTimestamp = options.includeTimestamp ~= false,
    })

    return logger
end

---@class MCP.ApplyLoggerConfigOptions
---@field level mwseLogger.logLevel?
---@field logToConsole boolean?

---@param options MCP.ApplyLoggerConfigOptions?
function this.ApplyConfigToAll(options)
    options = options or {}
    local level = options.level or config.development.logLevel
    local logToConsole = options.logToConsole
    if logToConsole == nil then
        logToConsole = config.development.logToConsole
    end

    local loggers = mwseLogger.getLoggers(settings.modDirRelative) or {}
    for _, logger in ipairs(loggers) do
        logger:setLevel(level)
        logger.logToConsole = logToConsole
    end
end

---@param level mwseLogger.logLevel
function this.SetLevel(level)
    this.ApplyConfigToAll({ level = level })
end

---@param logToConsole boolean
function this.SetLogToConsole(logToConsole)
    this.ApplyConfigToAll({ logToConsole = logToConsole })
end

return this
