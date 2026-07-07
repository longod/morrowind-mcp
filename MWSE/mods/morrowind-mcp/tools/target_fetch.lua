local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local serializer = require("morrowind-mcp.serializer")


---@class MCP.TargetFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.TargetFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.TargetFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "target_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "target-fetch",
        description =
        "Fetch current target state. This is the object that the player is currently looking at or cursor is currently pointing at.",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                playerTarget = jsonrpc.JsonObjectSchema(), -- cant set description?
                -- helpLayerMenu = jsonrpc.JsonObjectSchema(),
                -- inventryTile = jsonrpc.JsonObjectSchema(),
                -- serviceActor = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    -- can get on main menu?
    -- if tes3.onMainMenu() then
    --     return false
    -- end
    return true
end

function this:Execute(params, context)
    local playerTarget = tes3.getPlayerTarget() -- not include non-activatable objects.
    local helpLayerMenu = tes3ui.getCursor() -- help layer menu
    local inventryTile = tes3ui.getCursorTile()
    local serviceActor = tes3ui.getServiceActor() -- service or talking actor
    -- TODO pointing 3d object in menu?

    local structuredContent = jsonrpc.object({
        playerTarget = serializer.tes3reference(playerTarget),
        -- helpLayerMenu = serializer.tes3uiElement(helpLayerMenu),
        -- inventryTile = serializer.tes3inventoryTile(inventryTile), -- TODO
        -- serviceActor = serializer.tes3mobileActor(serviceActor), -- TODO fetch from base type to inherited types.
     })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
