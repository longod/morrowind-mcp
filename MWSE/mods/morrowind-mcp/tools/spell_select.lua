local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local availability = require("morrowind-mcp.util.tes3_availability")

--- “equip” might be a better name than "action". This is an alias, and it doesn't yet have the ability to cast spells. Since the conditions for opening and closing the inventory are reversed when casting spells, it might be better to use a different tool for that.
---@class MCP.Tools.SpellEquip: MCP.ITool
---@field logger mwseLogger
---@field GetPublishedTools fun(): table<string, MCP.ITool>
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.SpellEquip
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.SpellEquip
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "spell_equip" })
    instance.definition = jsonrpc.Tool({
        name = "spell-select",
        description = "Select a spell from the player's spells, powers or magic items in the magic menu.",
        inputSchema = jsonrpc.InputSchema({
            -- id, path
            name = jsonrpc.StringSchema(
                "Spell Name",
                "Name of the spell to select.",
                1,
                255
            ),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),
    })
    return instance
end


function this:GetCapabilityConditions()
    return "Required magic menu must be displayed."
end

--- Requires the live player inventory menu so a probe cannot target a container or barter tile.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    local ok, reason = availability.PausedInMenuMode()
    if not ok then
        return false, reason
    end

    -- magic menu displayed

    return true
end

---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
return jsonrpc.CallToolResult(
        jsonrpc.TextContent("Spell selection is not yet implemented."),
        nil,
        true
    )
end

return this
