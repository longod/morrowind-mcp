local base = require("morrowind-mcp.core.itool")
local inputvalidator = require("morrowind-mcp.core.inputvalidator")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local pathutil = require("morrowind-mcp.core.pathutil")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.Tools.ScreenshotSave: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.ScreenshotSave
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.ScreenshotSave
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "screenshot_save" })
    instance.definition = jsonrpc.Tool({
        name = "screenshot-save",
        description =
        "Save a screenshot of the current game state to a file. The screenshot will be saved to the resources",
        inputSchema = jsonrpc.InputSchema(
            {
                capture_with_ui = jsonrpc.BooleanSchema(
                    "Capture with UI",
                    "The screenshot will include the user interface.",
                    true
                ),
                file_name = jsonrpc.StringSchema(
                    "File Name",
                    "Screenshot file name (without extension). If not specified, a timestamp will be used.",
                    minMenuNameLength, -- minimum length
                    maxMenuNameLength  -- maximum length
                ),
                extension = jsonrpc.UntitledSingleSelectEnumSchema(
                    { ".jpg", ".png", ".bmp", ".tga", ".dds" },
                    "Extension",
                    "Select screenshot file extension.",
                    ".jpg"
                ),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)

    })
    return instance
end

function this:CanExecute(params)
    return true -- tes3.game.screenShotsEnabled does not work.
end

function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    -- The file name becomes one filesystem path segment; reject unsafe names instead of silently rewriting them.
    local arguments = params.arguments or {}
    local filename = arguments["file_name"]
    if filename ~= nil then
        local filenameResult = inputvalidator.ValidateFileName(filename, "file_name", { maxLength = maxMenuNameLength })
        for _, validationError in ipairs(filenameResult.errors) do
            table.insert(result.errors, validationError)
        end
        result.valid = result.valid and filenameResult.valid
    end
    return result
end

function this:Execute(params, context)
    -- Argument validation already rejected unsafe caller-provided names; execution resolves defaults and collisions.
    local arguments = assert(params.arguments, "tools/call must normalize arguments before Execute")

    local ms = math.floor((os.clock() % 1) * 1000)
    local default_name = os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms)
    local name = default_name
    local filename = arguments["file_name"]
    self.logger:debug("arguments file_name=%s, extension=%s, capture_with_ui=%s", tostring(arguments["file_name"]),
        tostring(arguments["extension"]), tostring(arguments["capture_with_ui"]))

    if filename ~= nil then
        name = filename
    end
    local extension = arguments["extension"]
    local settings = require("morrowind-mcp.settings")
    local dir = settings.resourceRootDir .. "screenshot\\"
    pcall(lfs.mkdir, dir)
    local path = dir .. name .. extension
    if lfs.attributes(path) then
        self.logger:warn("Screenshot file already exists: %s.", path)
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Screenshot file already exists: " .. path), nil, true)
    end

    local capture_with_ui = arguments["capture_with_ui"]

    -- it seems to save to files is no latency, syncronous. it can be readed immidiately.
    mge.saveScreenshot({ path = path, captureWithUI = capture_with_ui })

    local resourcePath = pathutil.FromResourceFilePath(path, settings.resourceRootDir)
    if not resourcePath then
        self.logger:error("Failed to convert screenshot file path to resource path: %s", path)
        local errorContent = jsonrpc.TextContent("Failed to resolve screenshot resource path")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local resourceUri = pathutil.ToUri(resourcePath, settings.uriScheme)
    if not resourceUri then
        self.logger:error("Failed to convert screenshot path to URI: %s", path)
        local errorContent = jsonrpc.TextContent("Failed to resolve screenshot URI")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end


    self.logger:info("Screenshot taken: path=%s, uri=%s", path, resourceUri)

    local mimeType = mimeutil.ResolveMimeTypeFromExtension(extension)
    local content = jsonrpc.ResourceLink(name .. extension, resourceUri,
        "Screenshot taken at " .. os.date("%Y-%m-%d %H:%M:%S"), nil, mimeType)
    return jsonrpc.CallToolResult(content)
end

return this
