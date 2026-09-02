local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local iter = require("morrowind-mcp.tes3.iterator")
local spellbook = require("morrowind-mcp.resources.memory.spellbook")

local castableEnchantmentType = {
    [tes3.enchantmentType.castOnce] = "castOnce",
    [tes3.enchantmentType.onUse] = "onUse",
}

---@class MCP.Tools.SpellFetch: MCP.ITool
---@field logger mwseLogger
---@class MCP.Tools.SpellFetchEntry: MCP.MemorySpell
---@field category "spell"|"power"
---@field used boolean?
---@field available boolean?
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.SpellFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.SpellFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "spell_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "spell-fetch",
        description = "Fetch the player's spells, powers, and castable magic items.",
        inputSchema = jsonrpc.InputSchema(),
        outputSchema = jsonrpc.OutputSchema({
            spells = jsonrpc.JsonArraySchema(),
            powers = jsonrpc.JsonArraySchema(),
            magic_items = jsonrpc.JsonArraySchema(),
        }, jsonrpc.array({
            "spells",
            "powers",
            "magic_items",
        })),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Available only in an active loaded game, when the player spellbook and inventory are available."
end

--- Requires a loaded game because the player spellbook and inventory are live game state.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    return true
end

--- Serializes one castable enchanted inventory stack using the same item serializers as inventory-fetch.
---@param item tes3item
---@param count integer
---@param itemData tes3itemData?
---@return MCP.AnyMap?
local function SerializeMagicItem(item, count, itemData)
    -- tes3item is a broad metadata type; only runtime item subclasses expose enchantment.
    local magicItem = item --[[@as any]]
    local enchantment = magicItem.enchantment
    local castType = enchantment and castableEnchantmentType[enchantment.castType]
    if not castType then
        return nil
    end
    return jsonrpc.object({
        id = item.id,
        name = item.name,
        category = "magic_item",
        item = obj.tes3anyObject(item),
        count = count,
        itemData = obj.tes3itemData(itemData),
        enchantment = obj.tes3anyObject(enchantment),
        enchantmentCastType = castType,
    })
end

--- Fetches the player's live spellbook and castable enchanted inventory stacks.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local player = tes3.mobilePlayer
    if not player then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("No player found. Please enter the game."), nil, true)
    end

    local spells = jsonrpc.array()
    local powers = jsonrpc.array()
    local magicItems = jsonrpc.array()
    for _, spell in ipairs(tes3.getSpells({ target = tes3.player, spellType = tes3.spellType.spell }) or {}) do
        local serializedSpell = spellbook.SerializeSpell(spell)
        if serializedSpell then
            ---@cast serializedSpell MCP.Tools.SpellFetchEntry
            serializedSpell.category = "spell"
            table.insert(spells, serializedSpell)
        end
    end
    for _, power in ipairs(tes3.getSpells({ target = tes3.player, spellType = tes3.spellType.power }) or {}) do
        local serializedPower = spellbook.SerializeSpell(power)
        if serializedPower then
            ---@cast serializedPower MCP.Tools.SpellFetchEntry
            serializedPower.category = "power"
            serializedPower.used = player:hasUsedPower(power) == true
            serializedPower.available = not serializedPower.used
            table.insert(powers, serializedPower)
        end
    end
    iter.ForEachItem(player.inventory, SerializeMagicItem, magicItems)

    return jsonrpc.CallToolResult(nil, jsonrpc.object({
        spells = spells,
        powers = powers,
        magic_items = magicItems,
    }))
end

return this
