local base = require("morrowind-mcp.core.itool")
local inputvalidator = require("morrowind-mcp.core.inputvalidator")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.Tools.DebugAction: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager TODO use MCP.IResourceManager
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DebugAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DebugAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "debug_action" })
    instance.definition = jsonrpc.Tool({
        name = "debug-action",
        description =
        "Perform a debug command.",
        inputSchema = jsonrpc.InputSchema(
            {
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "memory:SaveDebugDocuments"
                    },
                    "memory:SaveDebugDocuments",
                    "Dump all Memory documents to " .. settings.memoryDebugDumpDir
                ),
            },
            jsonrpc.array({ "action" }) -- TODO one of id or name. but specification is not exist.
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:CanExecute(params)
    return config.development.debug
end


function this:Execute(arguments, context)
    -- Argument validation already covered schema checks; this function performs the requested debug side effect.
    local action = arguments["action"]

    if action == "memory:SaveDebugDocuments" then
        self.resource.memory:SaveDebugDocuments()
    else
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent(string.format("Unknown action %s", action)), nil, true)
    end

    return jsonrpc.CallToolResult(
        jsonrpc.TextContent(string.format("Action %s performed successfully.", action)), nil, false)
end

return this

-- https://mwse.github.io/MWSE/types/tes3uiMenuController/
-- https://mwse.github.io/MWSE/types/tes3uiMenuInputController/
-- nameFormat.text = strings.defaultPotionName
