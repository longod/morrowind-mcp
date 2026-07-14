
-- who? only player? service actor? target? cursor? menu? inventory tile?

local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")


---@class MCP.InventryFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.InventryFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.InventryFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "inventory_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "inventory-fetch",
        description =
        "Fetch current inventory.",
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

function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    return true
end

function this:Execute(params, context)
    local player = tes3.mobilePlayer
    if not player then
        local errorContent = jsonrpc.TextContent("No player found. Please enter the game.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    self.logger:debug("Fetching inventory for player: %d", table.size(player.inventory))
    local items = jsonrpc.array(table.size(player.inventory))
    for item, count, itemData in iter.ForEachInventory(player.inventory) do
        self.logger:trace("Fetching item=%s count=%d itemData=%s", item.name, count, itemData and "itemData" or "nil")
        local o = jsonrpc.object({
            item = obj.tes3anyObject(item),
            count = count,
            itemData = obj.tes3itemData(itemData),
        })
        if o then
            table.insert(items, o)
        end
    end

    local structuredContent = jsonrpc.object({ inventory = items })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
