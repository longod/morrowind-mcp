local storageModule = require("morrowind-mcp.navigation.terrain.storage")

local this = {}

local sampledFlag = 1
local walkableFlag = 2
local waterFlag = 4

---@class MCP.TerrainGridDirection
---@field dx integer Horizontal column offset.
---@field dy integer Vertical row offset.
---@field mask integer Bit used to block this outgoing direction.
---@field oppositeMask integer Corresponding bit on the destination sample.
---@field distance number Distance multiplier relative to the sampling interval.

---@type MCP.TerrainGridDirection[]
local directions = {
    { dx = 1, dy = 0, mask = 1, oppositeMask = 2, distance = 1 },
    { dx = -1, dy = 0, mask = 2, oppositeMask = 1, distance = 1 },
    { dx = 0, dy = 1, mask = 4, oppositeMask = 8, distance = 1 },
    { dx = 0, dy = -1, mask = 8, oppositeMask = 4, distance = 1 },
    { dx = 1, dy = 1, mask = 16, oppositeMask = 128, distance = math.sqrt(2) },
    { dx = -1, dy = 1, mask = 32, oppositeMask = 64, distance = math.sqrt(2) },
    { dx = 1, dy = -1, mask = 64, oppositeMask = 32, distance = math.sqrt(2) },
    { dx = -1, dy = -1, mask = 128, oppositeMask = 16, distance = math.sqrt(2) },
}

---@class MCP.TerrainGridParams
---@field cellId MCP.CellIdentityKey Stable identity of the exterior cell.
---@field gridX integer Exterior cell X coordinate.
---@field gridY integer Exterior cell Y coordinate.
---@field originX number Minimum world X represented by column zero.
---@field originY number Minimum world Y represented by row zero.
---@field interval number Distance in world units between samples.
---@field width integer Number of sample columns.
---@field height integer Number of sample rows.
---@field maxSlopeDegrees number? Optional walking slope limit.
---@field maxClimb number? Optional vertical step limit.
---@field waterLevel number? Cell water surface, when present.
---@field storage MCP.TerrainGridStorage? Optional injected storage backend.

---@class MCP.TerrainGridOpenEntry
---@field index integer Flat sample index.
---@field score number Estimated total A* cost.

---@class MCP.TerrainGridPath
---@field indices integer[] Ordered flat sample indices from start to destination.
---@field positions MCP.PathfindingPosition[] Copied world-space positions matching `indices`.
---@field cost number Accumulated horizontal and elevation cost.

---@class MCP.TerrainGrid
---@field cellId MCP.CellIdentityKey
---@field gridX integer
---@field gridY integer
---@field originX number
---@field originY number
---@field interval number
---@field width integer
---@field height integer
---@field maxSlopeDegrees number
---@field maxSlopeRadians number
---@field maxClimb number
---@field waterLevel number?
---@field storage MCP.TerrainGridStorage
---@field Index fun(self: MCP.TerrainGrid, column: integer, row: integer): integer?
---@field GridCoordinates fun(self: MCP.TerrainGrid, index: integer): integer, integer
---@field WorldPosition fun(self: MCP.TerrainGrid, index: integer): MCP.PathfindingPosition
---@field SetSample fun(self: MCP.TerrainGrid, column: integer, row: integer, height: number, normalZ: number)
---@field SetUnavailable fun(self: MCP.TerrainGrid, column: integer, row: integer)
---@field IsWalkable fun(self: MCP.TerrainGrid, index: integer?): boolean
---@field GetNeighborIndex fun(self: MCP.TerrainGrid, fromIndex: integer, direction: MCP.TerrainGridDirection): integer?
---@field CanTraverse fun(self: MCP.TerrainGrid, fromIndex: integer, direction: MCP.TerrainGridDirection): boolean
---@field SetEdgeBlocked fun(self: MCP.TerrainGrid, fromIndex: integer, toIndex: integer, blocked: boolean): boolean
---@field FindNearestWalkable fun(self: MCP.TerrainGrid, position: MCP.PathfindingPosition|tes3vector3): integer?
---@field Heuristic fun(self: MCP.TerrainGrid, first: integer, second: integer): number
---@field FindPath fun(self: MCP.TerrainGrid, start: MCP.PathfindingPosition|tes3vector3, destination: MCP.PathfindingPosition|tes3vector3): MCP.TerrainGridPath?
---@field InterpolateHeight fun(self: MCP.TerrainGrid, x: number, y: number): number?
---@field Release fun(self: MCP.TerrainGrid)

--- Create one cell-local 2.5D grid whose neighbor edges are derived rather than stored as tables.
---@param params MCP.TerrainGridParams
---@return MCP.TerrainGrid
function this.new(params)
    local instance = {
        cellId = params.cellId,
        gridX = params.gridX,
        gridY = params.gridY,
        originX = params.originX,
        originY = params.originY,
        interval = params.interval,
        width = params.width,
        height = params.height,
        maxSlopeDegrees = params.maxSlopeDegrees or 46,
        maxSlopeRadians = math.rad(params.maxSlopeDegrees or 46),
        maxClimb = params.maxClimb or 34,
        waterLevel = params.waterLevel,
        storage = params.storage or storageModule.new(params.width * params.height),
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Convert zero-based grid coordinates to the storage's 1-based row-major index.
--- Coordinates outside this grid return nil instead of wrapping into an adjacent cell.
---@param column integer
---@param row integer
---@return integer?
function this:Index(column, row)
    if column < 0 or row < 0 or column >= self.width or row >= self.height then
        return nil
    end
    return row * self.width + column + 1
end

--- Convert a valid 1-based storage index back to zero-based grid coordinates.
---@param index integer
---@return integer column
---@return integer row
function this:GridCoordinates(index)
    local offset = index - 1
    return offset % self.width, math.floor(offset / self.width)
end

--- Materialize a copied world-space point for a sample without exposing storage internals.
---@param index integer
---@return MCP.PathfindingPosition
function this:WorldPosition(index)
    local column, row = self:GridCoordinates(index)
    return {
        x = self.originX + column * self.interval,
        y = self.originY + row * self.interval,
        z = self.storage:GetHeight(index),
    }
end

--- Classify one terrain sample from elevation and an upward-facing normal component.
--- Water and over-slope samples remain sampled but are not walkable in the walking-only model.
---@param column integer
---@param row integer
---@param height number
---@param normalZ number
function this:SetSample(column, row, height, normalZ)
    local index = self:Index(column, row)
    if not index then
        return
    end
    local flags = sampledFlag
    local isWater = self.waterLevel ~= nil and height < self.waterLevel
    if isWater then
        flags = bit.bor(flags, waterFlag)
    elseif normalZ >= math.cos(self.maxSlopeRadians) then
        flags = bit.bor(flags, walkableFlag)
    end
    self.storage:SetSample(index, height, flags)
end

--- Mark a coordinate as unsampled so route queries cannot traverse interpolation gaps.
---@param column integer
---@param row integer
function this:SetUnavailable(column, row)
    local index = self:Index(column, row)
    if index then
        self.storage:SetSample(index, 0, 0)
    end
end

--- Return whether a sample exists and is classified for walking.
---@param index integer?
---@return boolean
function this:IsWalkable(index)
    return index ~= nil and bit.band(self.storage:GetFlags(index), walkableFlag) ~= 0
end

--- Resolve one of the eight fixed neighbor directions within this grid.
---@param fromIndex integer
---@param direction MCP.TerrainGridDirection
---@return integer?
function this:GetNeighborIndex(fromIndex, direction)
    local column, row = self:GridCoordinates(fromIndex)
    return self:Index(column + direction.dx, row + direction.dy)
end

--- Check classification, learned blockage, climb/slope limits, and diagonal corner clearance for one edge.
---@param fromIndex integer
---@param direction MCP.TerrainGridDirection
---@return boolean
function this:CanTraverse(fromIndex, direction)
    local toIndex = self:GetNeighborIndex(fromIndex, direction)
    if not self:IsWalkable(fromIndex) or not self:IsWalkable(toIndex) then
        return false
    end
    if self.storage:IsDirectionBlocked(fromIndex, direction.mask) then
        return false
    end

    local heightDifference = math.abs(self.storage:GetHeight(toIndex) - self.storage:GetHeight(fromIndex))
    local horizontalDistance = self.interval * direction.distance
    -- A route edge must satisfy both independent walking limits; a steep long slope cannot bypass the step limit.
    if heightDifference > self.maxClimb or math.atan2(heightDifference, horizontalDistance) > self.maxSlopeRadians then
        return false
    end

    -- Diagonal motion requires both orthogonal side samples so the route cannot cut through a blocked corner.
    if direction.dx ~= 0 and direction.dy ~= 0 then
        local column, row = self:GridCoordinates(fromIndex)
        if not self:IsWalkable(self:Index(column + direction.dx, row))
            or not self:IsWalkable(self:Index(column, row + direction.dy)) then
            return false
        end
    end
    return true
end

--- Persist a symmetric blocked state for one adjacent pair discovered by obstacle validation.
---@param fromIndex integer
---@param toIndex integer
---@param blocked boolean
---@return boolean
function this:SetEdgeBlocked(fromIndex, toIndex, blocked)
    local fromColumn, fromRow = self:GridCoordinates(fromIndex)
    local toColumn, toRow = self:GridCoordinates(toIndex)
    for _, direction in ipairs(directions) do
        if toColumn - fromColumn == direction.dx and toRow - fromRow == direction.dy then
            self.storage:SetDirectionBlocked(fromIndex, direction.mask, blocked)
            self.storage:SetDirectionBlocked(toIndex, direction.oppositeMask, blocked)
            return true
        end
    end
    return false
end

--- Find the nearest walkable sample with one bounded scan of the flat storage.
--- The scan avoids repeatedly visiting out-of-bounds square rings when no sample is walkable.
---@param position MCP.PathfindingPosition|tes3vector3
---@return integer?
function this:FindNearestWalkable(position)
    local bestIndex = nil
    local bestDistance = nil
    for index = 1, self.width * self.height do
        if self:IsWalkable(index) then
            local world = self:WorldPosition(index)
            local dx = world.x - position.x
            local dy = world.y - position.y
            local dz = world.z - position.z
            local distance = dx * dx + dy * dy + dz * dz
            if not bestDistance or distance < bestDistance then
                bestIndex = index
                bestDistance = distance
            end
        end
    end
    return bestIndex
end

--- Insert an A* frontier entry into a binary min-heap ordered by total score.
---@param heap MCP.TerrainGridOpenEntry[]
---@param entry MCP.TerrainGridOpenEntry
local function PushHeap(heap, entry)
    table.insert(heap, entry)
    local index = table.size(heap)
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].score <= entry.score then
            break
        end
        heap[index] = heap[parent]
        index = parent
    end
    heap[index] = entry
end

--- Remove the lowest-score A* frontier entry while preserving the binary heap invariant.
---@param heap MCP.TerrainGridOpenEntry[]
---@return MCP.TerrainGridOpenEntry?
local function PopHeap(heap)
    if table.size(heap) == 0 then
        return nil
    end
    local result = heap[1]
    local last = table.remove(heap)
    if table.size(heap) > 0 then
        local index = 1
        while true do
            local left = index * 2
            if left > table.size(heap) then
                break
            end
            local right = left + 1
            local child = right <= table.size(heap) and heap[right].score < heap[left].score and right or left
            if last.score <= heap[child].score then
                break
            end
            heap[index] = heap[child]
            index = child
        end
        heap[index] = last
    end
    return result
end

--- Compute an octile lower bound for an eight-neighbor grid with cardinal and diagonal costs.
---@param first integer
---@param second integer
---@return number
function this:Heuristic(first, second)
    local firstColumn, firstRow = self:GridCoordinates(first)
    local secondColumn, secondRow = self:GridCoordinates(second)
    local dx = math.abs(firstColumn - secondColumn)
    local dy = math.abs(firstRow - secondRow)
    return (math.max(dx, dy) + (math.sqrt(2) - 1) * math.min(dx, dy)) * self.interval
end

--- Run A* between the nearest walkable samples and return copied indices, positions, and accumulated cost.
--- Elevation change is added to edge cost so equally short routes prefer gentler terrain.
---@param start MCP.PathfindingPosition|tes3vector3
---@param destination MCP.PathfindingPosition|tes3vector3
---@return MCP.TerrainGridPath?
function this:FindPath(start, destination)
    local startIndex = self:FindNearestWalkable(start)
    local destinationIndex = self:FindNearestWalkable(destination)
    if not startIndex or not destinationIndex then
        return nil
    end
    local sampleCount = self.width * self.height
    local open = table.new(sampleCount, 0)
    ---@cast open MCP.TerrainGridOpenEntry[]
    open[1] = { index = startIndex, score = self:Heuristic(startIndex, destinationIndex) }
    local costs = table.new(sampleCount, 0)
    ---@cast costs table<integer, number>
    costs[startIndex] = 0
    local previous = table.new(sampleCount, 0)
    ---@cast previous table<integer, integer>
    local closed = table.new(sampleCount, 0)
    ---@cast closed table<integer, boolean>
    while table.size(open) > 0 do
        local current = PopHeap(open)
        if current and not closed[current.index] then
            closed[current.index] = true
            if current.index == destinationIndex then
                local indices = table.new(sampleCount, 0)
                ---@cast indices integer[]
                local index = destinationIndex
                while index do
                    table.insert(indices, 1, index)
                    index = previous[index]
                end
                local positions = table.new(table.size(indices), 0)
                for pathIndex, sampleIndex in ipairs(indices) do
                    positions[pathIndex] = self:WorldPosition(sampleIndex)
                end
                return { indices = indices, positions = positions, cost = costs[destinationIndex] }
            end
            for _, direction in ipairs(directions) do
                if self:CanTraverse(current.index, direction) then
                    local neighbor = self:GetNeighborIndex(current.index, direction)
                    if neighbor and not closed[neighbor] then
                        local heightDifference = math.abs(self.storage:GetHeight(neighbor) - self.storage:GetHeight(current.index))
                        local nextCost = costs[current.index] + self.interval * direction.distance + heightDifference
                        if not costs[neighbor] or nextCost < costs[neighbor] then
                            costs[neighbor] = nextCost
                            previous[neighbor] = current.index
                            PushHeap(open, { index = neighbor, score = nextCost + self:Heuristic(neighbor, destinationIndex) })
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- Bilinearly interpolate elevation from four sampled grid corners for quality measurements.
--- Any missing corner makes the queried point unavailable rather than inventing a partial surface.
---@param x number
---@param y number
---@return number?
function this:InterpolateHeight(x, y)
    local localX = (x - self.originX) / self.interval
    local localY = (y - self.originY) / self.interval
    local column = math.floor(localX)
    local row = math.floor(localY)
    local nextColumn = math.min(column + 1, self.width - 1)
    local nextRow = math.min(row + 1, self.height - 1)
    local first = self:Index(column, row)
    local second = self:Index(nextColumn, row)
    local third = self:Index(column, nextRow)
    local fourth = self:Index(nextColumn, nextRow)
    if not first or bit.band(self.storage:GetFlags(first), sampledFlag) == 0
        or bit.band(self.storage:GetFlags(second), sampledFlag) == 0
        or bit.band(self.storage:GetFlags(third), sampledFlag) == 0
        or bit.band(self.storage:GetFlags(fourth), sampledFlag) == 0 then
        return nil
    end
    local tx = math.clamp(localX - column, 0, 1)
    local ty = math.clamp(localY - row, 0, 1)
    local south = math.lerp(self.storage:GetHeight(first), self.storage:GetHeight(second), tx)
    local north = math.lerp(self.storage:GetHeight(third), self.storage:GetHeight(fourth), tx)
    return math.lerp(south, north, ty)
end

--- Release cell-owned storage when the cell leaves the active set.
function this:Release()
    if self.storage then
        self.storage:Release()
        self.storage = nil
    end
end

this.flags = { sampled = sampledFlag, walkable = walkableFlag, water = waterFlag }
this.directions = directions
return this

