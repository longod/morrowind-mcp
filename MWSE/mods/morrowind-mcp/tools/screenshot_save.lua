local base = require("morrowind-mcp.core.itool")
local inputvalidator = require("morrowind-mcp.core.inputvalidator")
local mimeutil = require("morrowind-mcp.core.mimeutil")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local pathutil = require("morrowind-mcp.core.pathutil")
local datetime = require("morrowind-mcp.util.datetime")
local settings = require("morrowind-mcp.settings")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.Tools.ScreenshotSave: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager
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
                    "Screenshot file name without extension. If not specified, a timestamp will be used.",
                    minMenuNameLength, -- minimum length
                    maxMenuNameLength  -- maximum length
                ),
                -- automatically select extension based on game situation, so the extension option is removed.
                -- extension = jsonrpc.UntitledSingleSelectEnumSchema(
                --     { ".jpg", ".png", ".bmp", ".tga", ".dds" },
                --     "Extension",
                --     "Select screenshot file extension.",
                --     ".jpg"
                -- ),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)

    })
    return instance
end

function this:CanExecute(arguments, context)
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

local notifyMenus = {
    tes3ui.registerID("MenuNotify1"),
    tes3ui.registerID("MenuNotify2"),
    tes3ui.registerID("MenuNotify3"),
}

--- Select extension based on game situation
---@param captureWithUI boolean
---@return string
local function GetExtension(captureWithUI)
    if captureWithUI then
        -- recognize text
        if tes3.menuMode() then
            return ".png"
        end

        -- for _, id in ipairs(notifyMenus) do
        --     local e = tes3ui.findHelpLayerMenu(id)
        --     if e and e.visible then
        --         return ".png"
        --     end
        -- end

        -- and tooltips?

        -- if tes3.onMainMenu() then
        --     return ".png"
        -- end
    end
    return ".jpg"
end

function this:Execute(arguments, context)
    -- Argument validation already rejected unsafe caller-provided names; execution resolves defaults and collisions.
    local ms = math.floor((os.clock() % 1) * 1000)
    local default_name = os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms)
    local name = default_name
    local filename = arguments["file_name"]

    if filename ~= nil then
        name = filename
    end
    local capture_with_ui = arguments["capture_with_ui"]
    local extension = GetExtension(capture_with_ui)

    local dir = settings.resourceRootDir .. "screenshot\\"
    pcall(lfs.mkdir, dir)
    local file = name .. extension
    local path = dir .. file
    if lfs.attributes(path) then
        self.logger:warn("Screenshot file already exists: %s.", path)
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Screenshot file already exists: " .. path), nil, true)
    end

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
    local now = datetime.ToISO8601(datetime.UTCNow())
    local res = {
        name = file,
        title = file,
        uri = resourceUri,
        description = "Screenshot taken at " .. now,
        mimeType = mimeType,
        annotations = jsonrpc.Annotations(nil, nil, now),
    }

    if self.resource then
        ---@type MCP.ResourceEntry
        local entry = {
            descriptor = res,
            handler = function(desc)
                local resourceContent = self.resource:LoadFileContent(desc)
                if not resourceContent then
                    return nil
                end
                return { resourceContent }
            end,
        }
        self.resource:PublishResource(entry)
        self.logger:debug("Published screenshot resource entry: %s", resourceUri)
    end

    local content = jsonrpc.ResourceLink(res.name, res.uri, res.title, res.description, res.mimeType, res.annotations)
    return jsonrpc.CallToolResult(content)
end

return this
