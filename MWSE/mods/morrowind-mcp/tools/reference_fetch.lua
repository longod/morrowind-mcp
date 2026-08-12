local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.core.tool_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local summary = require("morrowind-mcp.tes3.object_summary")
local iter = require("morrowind-mcp.tes3.iterator")
local cellutil = require("morrowind-mcp.tes3.cell")


---@class MCP.Tools.ReferenceFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.ReferenceFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.ReferenceFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "reference_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "reference-fetch",
        description =
        "Fetch references near the player by default, or from all active cells when requested. In minimal and standard results, " ..
        "distance is reported from the player as both Morrowind game units and meters; " ..
        "reference positions remain Morrowind game-space coordinates in game units.",
        inputSchema = jsonrpc.InputSchema({
            category = jsonrpc.UntitledMultiSelectEnumSchema(
                jsonrpc.UntitledMultiSelectEnumSchemaItems({
                    "activators",
                    "actors",
                    "statics",
                }),
                "Category",
                "Filter references by category. If not specified, all categories will be returned. activators is can be activated and interacted by the player. actors is characters and NPCs. statics is not moved by self objects such as items.",
                0, 3,
                nil
            ),
            id = jsonrpc.StringSchema(
                "Reference ID",
                "Filter references by ID. If not specified, all references will be returned.",
                1, 255
            ),
            detail_level = jsonrpc.UntitledSingleSelectEnumSchema(
                { "minimal", "standard", "full" },
                "Detail Level",
                "Serialization detail. The default is minimal for lists and full when filtering by reference ID.",
                nil
            ),
            scope = jsonrpc.UntitledSingleSelectEnumSchema(
                { "nearby", "active" },
                "Cell Scope",
                "Reference cell scope. nearby includes the player's current cell and loaded neighbours near exterior cell boundaries. active includes all active cells.",
                "nearby"
            ),
        }),
        outputSchema = jsonrpc.OutputSchema(
            {
                activators = jsonrpc.JsonArraySchema(),
                actors = jsonrpc.JsonArraySchema(),
                statics = jsonrpc.JsonArraySchema(),
                serialization = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "A game must be active and at least one cell must be loaded."
end

function this:CanExecute(arguments, context)
    if tes3.onMainMenu() then
        return false, availability.Unavailable(availability.reason.gameNotActive, "Start or continue a game.")
    end
    if not tes3.getActiveCells() then
        return false, availability.Unavailable(availability.reason.noActiveCells, "Wait until the player has entered a cell.")
    end
    return true
end

-- TODO prefix, exact, perfect matching?
---@param ref string
---@param id string
---@return boolean
local function CompareId(ref, id)
    return ref == id
end

---@param ref tes3reference
---@return boolean
local function IsNotLeveledCreature(ref)
    local baseObject = ref.baseObject
    return not baseObject or baseObject.objectType ~= tes3.objectType.leveledCreature
end

function this:Execute(arguments, context)
    local id = arguments["id"]
    local detailLevel = arguments["detail_level"] or (id and summary.level.full or summary.level.minimal)
    local serializer = summary.new({
        detailLevel = detailLevel,
        origin = tes3.player and tes3.player.position or nil,
    })
    local cats = arguments["category"] or {} -- possible nil
    local category = nil
    if #cats > 0 then
        category = {}
        for _, value in ipairs(cats) do
            category[value] = true
        end
    end

    -- Active cells are the authoritative loaded-cell set. Nearby scope narrows that set by player position.
    local activeCells = tes3.getActiveCells()
    if not activeCells then
        local errorContent = jsonrpc.TextContent("no active cells found. Please enter a cell first.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    local cells = activeCells
    local scope = arguments["scope"] or "nearby"
    if scope ~= "active" then
        cells = cellutil.GetNearbyActiveCells(tes3.getPlayerCell(), tes3.player and tes3.player.position or nil, activeCells)
    end
    self.logger:debug("reference-fetch scope=%s cells=%d", scope, #cells)
    local activatorSize = 0
    local actorSize = 0
    local staticSize = 0
    for _, cell in ipairs(cells) do
        activatorSize = activatorSize + cell.activators.size
        actorSize = actorSize + cell.actors.size
        staticSize = staticSize + cell.statics.size
    end
    local activators = jsonrpc.array(activatorSize)
    local actors = jsonrpc.array(actorSize)
    local statics = jsonrpc.array(staticSize)
    if id then
        if category == nil or category["activators"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(
                    cell.activators,
                    function(i)
                        if CompareId(i.id, id) then
                            return serializer:Reference(i)
                        end
                        return nil
                    end,
                    activators,
                    IsNotLeveledCreature)
            end
        end
        if category == nil or category["actors"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(
                    cell.actors,
                    function(i)
                        if CompareId(i.id, id) then
                            return serializer:Reference(i)
                        end
                        return nil
                    end,
                    actors)
            end
        end
        if category == nil or category["statics"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(
                    cell.statics,
                    function(i)
                        if CompareId(i.id, id) then
                            return serializer:Reference(i)
                        end
                        return nil
                    end,
                    statics)
            end
        end
    else
        if category == nil or category["activators"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(
                    cell.activators,
                    function(i) return serializer:Reference(i) end,
                    activators,
                    IsNotLeveledCreature)
            end
        end
        if category == nil or category["actors"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(cell.actors, function(i) return serializer:Reference(i) end, actors)
            end
        end
        if category == nil or category["statics"] then
            for _, cell in ipairs(cells) do
                iter.ForEachReferenceObject(cell.statics, function(i) return serializer:Reference(i) end, statics)
            end
        end
    end
    local structuredContent = jsonrpc.object({
        serialization = serializer:GetMetadata(),
        activators = activators,
        actors = actors,
        statics = statics,
    })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
