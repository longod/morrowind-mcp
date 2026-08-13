local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")

---@class MCP.Tools.InventoryFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.InventoryFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.InventoryFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "inventory_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "inventory-fetch",
        description =
        "Fetch current player's inventory. or instead read the resource: morrowind://memory/player/inventory.json",
        inputSchema = jsonrpc.InputSchema(
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                inventory = jsonrpc.JsonArraySchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and loaded."
end

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    ok, reason = availability.IsCharGenFinished()
    if not ok then
        return false, reason
    end
    return true
end

function this:Execute(arguments, context)
    local player = tes3.mobilePlayer
    if not player then
        local errorContent = jsonrpc.TextContent("No player found. Please enter the game.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    self.logger:debug("Fetching inventory for player: %d", table.size(player.inventory))
    local items = jsonrpc.array(table.size(player.inventory))
    iter.ForEachItem(player.inventory, function(item, count, itemData)
            self.logger:trace("Fetching item=%s count=%d itemData=%s", item.name, count, itemData and "itemData" or "nil")
            local o = jsonrpc.object({
                item = obj.tes3anyObject(item),
                count = count,
                itemData = obj.tes3itemData(itemData),
            })
            return o
        end,
        items)

    local structuredContent = jsonrpc.object({ inventory = items })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
