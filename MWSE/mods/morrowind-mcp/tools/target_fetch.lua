local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local ui = require("morrowind-mcp.tes3.ui")


---@class MCP.Tools.TargetFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.TargetFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.TargetFetch
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
                helpLayerMenu = jsonrpc.JsonObjectSchema(),
                inventryTile = jsonrpc.JsonObjectSchema(),
                serviceActor = jsonrpc.JsonObjectSchema(),
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
    local helpLayerMenu = tes3ui.getCursor() -- on item picking and dragging.
    local inventryTile = tes3ui.getCursorTile() -- on item picking and dragging.
    local serviceActor = tes3ui.getServiceActor() -- service or talking actor
    -- TODO pointing 3d object in menu?

    self.logger:debug("playerTarget: %s, helpLayerMenu: %s, inventryTile: %s, serviceActor: %s",
        playerTarget and playerTarget.id or "nil",
        helpLayerMenu and helpLayerMenu.name or "nil",
        inventryTile and tostring(inventryTile.type) or "nil",
        serviceActor and tostring(serviceActor.actorType) or "nil"
    )

    -- local itemData = nil ---@type tes3itemData
    -- if playerTarget and not playerTarget:isValid()
    --     -- fetch item data from playertarget reference
    --     if playerTarget.object then -- tes3reference
    --         itemData = tes3.getAttachment(playerTarget, "itemData") --[[@as tes3itemData?]]
    --     end
    -- else
    --     -- fetch seeing objects
    --     if tes3.menuMode() then
    --         -- on cursor in 3d scene. if not pointing no ui.
    --     else
    --         -- raycast
    --         local maxDistance = tes3.getPlayerActivationDistance()
    --         if tes3.is3rdPerson() then
    --             maxDistance = maxDistance + tes3.getCameraPosition():distance(tes3.getPlayerEyePosition())
    --         end
    --         local hit = tes3.rayTest({
    --             position = tes3.getPlayerEyePosition(),
    --             direction = tes3.getPlayerEyeVector(),
    --             ignore = { tes3.player }, -- for no offseted TPV
    --             maxDistance = maxDistance,
    --         })
    --         if hit and hit.reference then
    --             -- logger:debug("Hit: %s", hit.reference.id)
    --             -- reference = hit.reference
    --             -- context.object = reference.object
    --             -- context.itemData = tes3.getAttachment(reference, "itemData") --[[@as tes3itemData?]]
    --         end

    --     end
    -- end

    -- help layer fetching on my way. findhelp*

    -- cache hover items
    -- event.register(tes3.event.itemTileUpdated, OnItemTileUpdated)

    -- discard cache
    -- event.register(tes3.event.menuExit, OnMenuExit)
    -- event.register(tes3.event.load, OnLoad)

    -- check modal menus?


    local structuredContent = jsonrpc.object({
        playerTarget = obj.tes3reference(playerTarget),
        helpLayerMenu = ui.tes3uiElement(helpLayerMenu),
        inventryTile = obj.tes3inventoryTile(inventryTile),
        serviceActor = obj.tes3anyObject(serviceActor),
     })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
