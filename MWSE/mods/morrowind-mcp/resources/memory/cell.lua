local jsonrpc = require("morrowind-mcp.server.jsonrpc")

--- Shared compact serialization for a TES3 cell used by player location Memory.
local this = {}

--- Serialize stable gameplay-relevant cell facts without retaining MWSE userdata.
---@param cell tes3cell?
---@return MCP.AnyMap?
function this.Serialize(cell)
    if not cell or not cell.id then
        return nil
    end

    local isInterior = cell.isInterior == true
    local region = cell.region
    local serialized = jsonrpc.object({
        id = cell.id,
        display_name = cell.displayName,
        is_interior = isInterior,
        region = region and jsonrpc.object({ id = region.id, name = region.name }) or nil,
        resting_is_illegal = cell.restingIsIllegal == true,
    })
    if not isInterior then
        serialized.grid_x = cell.gridX
        serialized.grid_y = cell.gridY
    end
    return serialized
end

return this
