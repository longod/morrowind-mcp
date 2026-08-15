local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.Tools.InventoryAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.InventoryAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.InventoryAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "inventory_action" })
    instance.definition = jsonrpc.Tool({
        name = "inventory-action",
        description =
            "Manipulate items in the inventory or container. transfer, equip, unequip, drop and etc." ..
            "This is more useful for manipulating items than for direct manipulation.",
        inputSchema = jsonrpc.InputSchema(
            {
                -- item tile select
                -- calc prices
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "equip",
                        "unequip",
                        "drop",
                        "transfer",
                        "transfer_all",
                        "offer",
                    },
                    "Action",
                    "Method to manipulate the item in the inventory or container.",
                    nil
                )
            },
            jsonrpc.array({ "action" })
        ),
        -- outputSchema = jsonrpc.OutputSchema(
        -- ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "The inventory menu must be displayed. To barter, pickpocket, or transfer items from a container, the barter menu or the menu for the target container must be displayed."
end

--- Keeps the incomplete workflow out of tools/list until its UI sequence is implemented.
---@return boolean
function this:IsPublished()
    return false
end

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

function this:Execute(arguments, context)

    -- local id = "iron_spear"
    -- local item = tes3.getObject(id)

    -- local dropped = tes3.dropItem({
    --     reference = tes3.player,
    --     item = item,
    --     count = 1,
    --     matchNoItemData = false,
    -- }) -- play sound

    -- tes3.equip({
    --     reference = tes3.player,
    --     item = item,
    --     selectBestCondition = false,
    --     selectWorstCondition = false,
    -- })

    -- tes3.addItem
    -- tes3.addItemData
    -- tes3.calculatePrice


    -- tes3.checkMerchantTradesItem
    -- tes3.getEquippedItem
    -- tes3.getItemCount
    -- tes3.getItemIsStolen
    -- tes3.getValue
    -- tes3.hasOwnershipAccess
    -- tes3.payMerchant
    -- tes3.playItemPickupSound
    -- tes3.removeItem
    -- tes3.removeItemData
    -- tes3.setItemIsStolen
    -- tes3.transferInventory
    -- tes3.transferItem


end

return this
