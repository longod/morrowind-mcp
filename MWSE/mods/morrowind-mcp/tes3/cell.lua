--- Shared stable identity helpers for TES3 cells.
local this = {}

---@alias MCP.CellIdentityKey string Shared internal key for one TES3 cell.

--- Return an internal key that distinguishes every valid loaded cell.
--- Interior IDs are unique, while exterior region IDs require grid coordinates.
---@param cell tes3cell?
---@return MCP.CellIdentityKey?
function this.GetIdentityKey(cell)
    if not cell or not cell.id then
        return nil
    end
    if cell.isInterior then
        return string.format("interior:%s", cell.id)
    end
    if cell.gridX == nil or cell.gridY == nil then
        return nil
    end
    return string.format("exterior:%s:%d,%d", cell.id, cell.gridX, cell.gridY)
end

--- Resolve an optional logical cell ID, falling back to the supplied current player cell.
---@param cellId string?
---@param fallbackCell tes3cell?
---@return tes3cell?
function this.ResolveOptionalId(cellId, fallbackCell)
    if cellId == nil or cellId:match("^%s*$") then
        return fallbackCell
    end
    return tes3.getCell({ id = cellId })
end

return this
