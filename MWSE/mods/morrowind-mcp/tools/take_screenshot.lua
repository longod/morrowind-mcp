
local base = require("morrowind-mcp.core.itool")
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
                -- TODO name
                -- TODO extension
                captureWithUI = jsonrpc.BooleanSchema(
                    "Capture with UI",
                    "The screenshot will include the user interface.",
                    true
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
    local ms = math.floor((os.clock() % 1) * 1000)
    local name = os.date("%Y%m%d_%H%M%S") .. string.format("_%03d", ms)
    local extension = ".jpg"
    local settings = require("morrowind-mcp.settings")
    local dir = settings.screenshotDir
    pcall(lfs.mkdir, dir)
    local path = dir .. name .. extension
    local captureWithUI = params["captureWithUI"]
    if captureWithUI == nil then
        captureWithUI = true
    end
    mge.saveScreenshot({path = path,  captureWithUI = captureWithUI})
    local resourcePath = string.sub(path, string.len(settings.dataFiles) + 1)
    -- This custom URI is resolved by resources/read as a Data Files-relative path.
    local uri = settings.resourceUriPrefix .. string.gsub(resourcePath, "\\", "/")

    self.logger:info("Screenshot taken: path=%s, uri=%s, captureWithUI=%s", path, uri, tostring(captureWithUI))

    local content = jsonrpc.ResourceLink(name, uri, "Screenshot taken at " .. os.date("%Y-%m-%d %H:%M:%S"), nil, "image/png")
    return jsonrpc.CallToolResult(content)
end



return this
