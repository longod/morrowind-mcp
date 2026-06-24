
local base = require("morrowind-mcp.core.itool")
local mime = require("morrowind-mcp.core.mime")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")


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
        description = "Takes a screenshot of the current game state",
        inputSchema = jsonrpc.InputSchema(
            {
                captureWithUI = jsonrpc.BooleanSchema(
                    "Capture with UI",
                    "The screenshot will include the user interface.",
                    true
                ),
                fileName = jsonrpc.StringSchema(
                    "File Name",
                    "Optional screenshot file name (without extension).",
                    1,
                    nil,
                    nil,
                    nil
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
    local arguments = params.arguments or {}

    local ms = math.floor((os.clock() % 1) * 1000)
    local default_name = os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms)
    local name = default_name
    local filename = arguments["fileName"]
    self.logger:debug("arguments fileName=%s, extension=%s, captureWithUI=%s", tostring(arguments["fileName"]), tostring(arguments["extension"]), tostring(arguments["captureWithUI"]))

    if type(filename) == "string" and filename ~= "" then
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
    local dir = settings.screenshotDir
    pcall(lfs.mkdir, dir)
    local path = dir .. name .. extension
    local captureWithUI = arguments["captureWithUI"]
    if captureWithUI == nil then
        captureWithUI = true
    end
    mge.saveScreenshot({path = path,  captureWithUI = captureWithUI})
    local resourcePath = string.sub(path, string.len(settings.dataFiles) + 1)
    -- This custom URI is resolved by resources/read as a Data Files-relative path.
    local uri = settings.resourceUriPrefix .. string.gsub(resourcePath, "\\", "/")


    self.logger:info("Screenshot taken: path=%s, uri=%s", path, uri)

    local mimeType = mime.ResolveMimeTypeFromExtension(extension)
    local content = jsonrpc.ResourceLink(name .. extension, uri, "Screenshot taken at " .. os.date("%Y-%m-%d %H:%M:%S"), nil, mimeType)
    return jsonrpc.CallToolResult(content)
end



return this
