local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local iter = require("morrowind-mcp.tes3.iterator")

--- Shared inventory enumeration helpers.
--- Callers provide serializers so this module stays independent of Memory document lifecycle.
local this = {}

--- Return the mutable inventory carried by a reference-backed actor or container instance.
---@param reference tes3reference?
---@return tes3inventory|tes3itemStack[]?
function this.GetReferenceInventory(reference)
    if not reference or not reference.object then
        return nil
    end
    return reference.object.inventory
end

--- Serialize one inventory collection into a compact gold-plus-stacks payload.
---@param inventory tes3inventory|tes3itemStack[]?
---@param serializeItem fun(item: tes3item): MCP.AnyMap?
---@param serializeItemData fun(itemData: tes3itemData?, item: tes3item): MCP.AnyMap?
---@param includeStack (fun(item: tes3item, itemData: tes3itemData?): boolean)?
---@return MCP.AnyMap
function this.ReadInventory(inventory, serializeItem, serializeItemData, includeStack)
    local items = jsonrpc.array()
    local gold = 0
    if not inventory then
        return jsonrpc.object({
            gold = gold,
            item_count = table.size(items),
            items = items,
        })
    end

    for item, count, itemData in iter.ForEachInventory(inventory) do
        local isGold = false
        if item.objectType == tes3.objectType.miscItem then
            ---@cast item tes3misc
            isGold = item.isGold == true
        end
        if isGold then
            gold = gold + count
        elseif not includeStack or includeStack(item, itemData) then
            table.insert(items, jsonrpc.object({
                item = serializeItem(item),
                itemData = serializeItemData(itemData, item),
                count = count,
            }))
        end
    end
    return jsonrpc.object({
        gold = gold,
        item_count = table.size(items),
        items = items,
    })
end

--- Serialize one UI inventory tile with the same stack shape used by inventory collections.
---@param tile tes3inventoryTile?
---@param serializeItem fun(item: tes3item): MCP.AnyMap?
---@param serializeItemData fun(itemData: tes3itemData?, item: tes3item): MCP.AnyMap?
---@return MCP.AnyMap?
function this.SerializeTile(tile, serializeItem, serializeItemData)
    if not tile or not tile.item then
        return nil
    end
    return jsonrpc.object({
        item = serializeItem(tile.item),
        itemData = serializeItemData(tile.itemData, tile.item),
        count = tile.count,
    })
end

return this
