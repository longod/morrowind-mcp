--- Shared stable identity helpers for TES3 cells.
local this = {}
local nearbyBoundaryFraction = 0.25

--- Exterior cells use a fixed world-space grid size in Morrowind game units.
this.exteriorCellSize = 8192

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

--- Select the player's exterior cell and loaded neighbours near its grid boundaries.
--- Interior cells always return only the current cell. Active cells limit exterior results to loaded cells.
---@param currentCell tes3cell?
---@param playerPosition tes3vector3?
---@param activeCells tes3cell[]?
---@return tes3cell[]
function this.GetNearbyActiveCells(currentCell, playerPosition, activeCells)
    if not currentCell then
        return {}
    end
    if currentCell.isInterior or not playerPosition or currentCell.gridX == nil or currentCell.gridY == nil then
        return { currentCell }
    end

    local cellSize = this.exteriorCellSize
    local boundaryDistance = cellSize * nearbyBoundaryFraction
    local localX = playerPosition.x - currentCell.gridX * cellSize
    local localY = playerPosition.y - currentCell.gridY * cellSize
    local xOffsets = { 0 }
    local yOffsets = { 0 }
    if localX <= boundaryDistance then
        table.insert(xOffsets, -1)
    elseif localX >= cellSize - boundaryDistance then
        table.insert(xOffsets, 1)
    end
    if localY <= boundaryDistance then
        table.insert(yOffsets, -1)
    elseif localY >= cellSize - boundaryDistance then
        table.insert(yOffsets, 1)
    end

    local activeByGrid = {}
    for _, cell in ipairs(activeCells or {}) do
        if not cell.isInterior and cell.gridX ~= nil and cell.gridY ~= nil then
            -- Omit region identity so adjacent cells across region boundaries remain selectable.
            activeByGrid[string.format("%d,%d", cell.gridX, cell.gridY)] = cell
        end
    end

    local nearbyCells = {}
    for _, yOffset in ipairs(yOffsets) do
        for _, xOffset in ipairs(xOffsets) do
            local gridX = currentCell.gridX + xOffset
            local gridY = currentCell.gridY + yOffset
            local cell = activeByGrid[string.format("%d,%d", gridX, gridY)]
            -- Always retain the player's current cell even if an incomplete active-cell list omitted it.
            if cell or (xOffset == 0 and yOffset == 0) then
                table.insert(nearbyCells, cell or currentCell)
            end
        end
    end
    return nearbyCells
end

return this
