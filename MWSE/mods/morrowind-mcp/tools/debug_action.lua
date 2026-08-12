local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")
local terrainSource = require("morrowind-mcp.navigation.terrain.source")

---@class MCP.Tools.DebugAction: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager TODO use MCP.IResourceManager
---@field terrainGridManager MCP.TerrainGridManager
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
                        "memory:SaveDebugDocuments",
                        "terrain:ProbeRuntimeAccess",
                        "terrain:GetGridStatus",
                        "terrain:StartQualityComparison",
                        "terrain:GetQualityStatus",
                    },
                    "Action",
                    "Debug command to perform."
                ),
            },
            jsonrpc.array({ "action" }) -- TODO one of id or name. but specification is not exist.
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:IsPublished()
    return config.development.debug
end


function this:Execute(arguments, context)
    -- Argument validation already covered schema checks; this function performs the requested debug side effect.
    local action = arguments["action"]

    if action == "memory:SaveDebugDocuments" then
        self.resource.memory:SaveDebugDocuments()
    elseif action == "terrain:ProbeRuntimeAccess" then
        local result = terrainSource.ProbeRuntimeAccess()
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent("Terrain runtime access probe completed."),
            jsonrpc.object(result),
            false
        )
    elseif action == "terrain:GetGridStatus" then
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent("Terrain grid status fetched."),
            jsonrpc.object(self.terrainGridManager:GetStatus()),
            false
        )
    elseif action == "terrain:StartQualityComparison" then
        local cell = tes3.player and tes3.player.cell or nil
        local started, errorMessage = self.terrainGridManager:StartQualityComparison(cell)
        if not started then
            return jsonrpc.CallToolResult(jsonrpc.TextContent(errorMessage or "Failed to start terrain quality comparison."),
                nil, true)
        end
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent("Terrain quality comparison started."),
            jsonrpc.object(self.terrainGridManager:GetQualityStatus()),
            false
        )
    elseif action == "terrain:GetQualityStatus" then
        return jsonrpc.CallToolResult(
            jsonrpc.TextContent("Terrain quality comparison status fetched."),
            jsonrpc.object(self.terrainGridManager:GetQualityStatus()),
            false
        )
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
