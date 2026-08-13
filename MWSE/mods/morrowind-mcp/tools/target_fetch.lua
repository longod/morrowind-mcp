local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local summary = require("morrowind-mcp.tes3.object_summary")
local availability = require("morrowind-mcp.util.tes3_availability")
local obj = require("morrowind-mcp.tes3.object")
local ui = require("morrowind-mcp.tes3.ui")
local dist = require("morrowind-mcp.util.distance")


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
        inputSchema = jsonrpc.InputSchema({
            detail_level = jsonrpc.UntitledSingleSelectEnumSchema(
                { "minimal", "standard", "full" },
                "Detail Level",
                "Serialization detail for game objects. The default is standard.",
                "standard"
            ),
        }),
        outputSchema = jsonrpc.OutputSchema(
            {
                -- TODO paused in menu target move to anywhere. menu, tile and service actor.
                playerTarget = jsonrpc.JsonObjectSchema(), -- cant set description?
                -- helpLayerMenu = jsonrpc.JsonObjectSchema(),
                -- inventoryTile = jsonrpc.JsonObjectSchema(),
                lookingAt = jsonrpc.JsonObjectSchema(),
                -- serviceActor = jsonrpc.JsonObjectSchema(),
                serialization = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and the player must be loaded. "
end


function this:CanExecute(arguments, context)

    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end

    -- it seemes better to disallow in menu mode.
    ok, reason = availability.NotInMenuMode()
    if not ok then
        return ok, reason
    end

    return true
end

function this:Execute(arguments, context)
    local serializer = summary.new({
        detailLevel = arguments["detail_level"] or summary.level.standard,
        origin = tes3.player and tes3.player.position or nil,
    })
    local playerTarget = tes3.getPlayerTarget()   -- not include non-activatable objects.
    -- local helpLayerMenu = tes3ui.getCursor()      -- on item picking and dragging.
    -- local inventoryTile = tes3ui.getCursorTile()  -- on item picking and dragging.
    -- local serviceActor = tes3ui.getServiceActor() -- service or talking actor
    -- TODO pointing 3d object in menu?

    local looking = nil
    if not playerTarget then
        local hit = tes3.rayTest({
            position = tes3.getPlayerEyePosition(),
            direction = tes3.getPlayerEyeVector(),
            maxDistance = dist.ToUnits(500),
            ignore = { tes3.player }
        })
        if hit then
            looking = hit.reference
            -- hit.distance
        end
    end

    -- self.logger:debug("playerTarget: %s, helpLayerMenu: %s, inventoryTile: %s, serviceActor: %s",
    --     playerTarget and playerTarget.id or "nil",
    --     helpLayerMenu and helpLayerMenu.name or "nil",
    --     inventoryTile and tostring(inventoryTile.type) or "nil",
    --     serviceActor and tostring(serviceActor.actorType) or "nil"
    -- )

    local target = serializer:Reference(playerTarget)

    local structuredContent = jsonrpc.object({
        serialization = serializer:GetMetadata(),
        playerTarget = target,
        lookingAt = looking and serializer:Reference(looking) or target,
        -- helpLayerMenu = ui.tes3uiElement(helpLayerMenu),
        -- inventoryTile = obj.tes3inventoryTile(inventoryTile),
        -- serviceActor = serializer:tes3anyObject(serviceActor),
    })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
