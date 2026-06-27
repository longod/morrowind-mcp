
local base = require("morrowind-mcp.core.itool")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local pathutil = require("morrowind-mcp.core.pathutil")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.TakeScreenshot: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.TakeScreenshot
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.TakeScreenshot
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "take_screenshot" })
    instance.definition = jsonrpc.Tool({
        name = "take_screenshot",
        description = "Take a screenshot of the current game state",
        inputSchema = jsonrpc.InputSchema(
            {
                captureWithUI = jsonrpc.BooleanSchema(
                    "Capture with UI",
                    "The screenshot will include the user interface.",
                    true
                ),
                fileName = jsonrpc.StringSchema(
                    "File Name",
                    "Screenshot file name (without extension). If not specified, a timestamp will be used.",
                    minMenuNameLength, -- minimum length
                    maxMenuNameLength -- maximum length
                ),
                extension = jsonrpc.UntitledSingleSelectEnumSchema(
                    { ".jpg", ".png", ".bmp", ".tga", ".dds" },
                    "Extension",
                    "Select screenshot file extension.",
                    ".jpg"
                ),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)

    })
    return instance
end

function this:CanExecute(params)
    return true -- tes3.game.screenShotsEnabled does not work.
end

function this:Execute(params)
    -- TODO validation for injection
    local arguments = params.arguments or {}

    local ms = math.floor((os.clock() % 1) * 1000)
    local default_name = os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms)
    local name = default_name
    local filename = arguments["fileName"]
    self.logger:debug("arguments fileName=%s, extension=%s, captureWithUI=%s", tostring(arguments["fileName"]), tostring(arguments["extension"]), tostring(arguments["captureWithUI"]))

    if type(filename) == "string" and #filename >= minMenuNameLength and #filename <= maxMenuNameLength then
        -- or sanitize...
        local has_invalid_char = false
        for _, ch in ipairs({ "\\", "/", ":", "*", "?", "\"", "<", ">", "|" }) do
            if string.find(filename, ch, 1, true) then
                has_invalid_char = true
                break
            end
        end
        if not has_invalid_char then
            name = filename
        else
            self.logger:warn("Invalid fileName: %s. Fallback to auto-generated name.", filename)
        end
    end
    local extension = arguments["extension"] or ".jpg"
    local settings = require("morrowind-mcp.settings")
    local dir = settings.resourceRootDir
    pcall(lfs.mkdir, dir)
    local path = dir .. name .. extension
    local captureWithUI = arguments["captureWithUI"]
    if captureWithUI == nil then
        captureWithUI = true
    end
    mge.saveScreenshot({path = path,  captureWithUI = captureWithUI})
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
    local content = jsonrpc.ResourceLink(name .. extension, resourceUri, "Screenshot taken at " .. os.date("%Y-%m-%d %H:%M:%S"), nil, mimeType)
    return jsonrpc.CallToolResult(content)
end



return this
