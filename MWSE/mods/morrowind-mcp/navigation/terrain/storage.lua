--- Replaceable flat-array storage for one terrain grid.
--- Keeping allocation behind this module allows a later FFI backend without changing grid algorithms.
local this = {}

---@class MCP.TerrainGridStorage
---@field count integer
---@field heights number[]
---@field flags integer[]
---@field blockedDirections integer[]

--- Allocate zero-initialized flat arrays for one grid so storage can later be replaced independently of traversal logic.
---@param count integer
---@return MCP.TerrainGridStorage
function this.new(count)
    local instance = {
        count = count,
        heights = table.new(count, 0),
        flags = table.new(count, 0),
        blockedDirections = table.new(count, 0),
    }
    for index = 1, count do
        instance.heights[index] = 0
        instance.flags[index] = 0
        instance.blockedDirections[index] = 0
    end
    setmetatable(instance, { __index = this })
    return instance
end

--- Store one sampled elevation and its packed classification flags at a 1-based flat index.
---@param index integer
---@param height number
---@param flags integer
function this:SetSample(index, height, flags)
    self.heights[index] = height
    self.flags[index] = flags
end

--- Read the sampled elevation at a valid 1-based flat index.
---@param index integer
---@return number
function this:GetHeight(index)
    return self.heights[index]
end

--- Read the packed classification flags at a valid 1-based flat index.
---@param index integer
---@return integer
function this:GetFlags(index)
    return self.flags[index]
end

--- Test one directional edge bit learned from obstacle validation.
---@param index integer
---@param directionMask integer
---@return boolean
function this:IsDirectionBlocked(index, directionMask)
    return bit.band(self.blockedDirections[index], directionMask) ~= 0
end

--- Set or clear one directional edge bit without changing the sample classification.
---@param index integer
---@param directionMask integer
---@param blocked boolean
function this:SetDirectionBlocked(index, directionMask, blocked)
    if blocked then
        self.blockedDirections[index] = bit.bor(self.blockedDirections[index], directionMask)
    else
        self.blockedDirections[index] = bit.band(self.blockedDirections[index], bit.bnot(directionMask))
    end
end

--- Release large arrays promptly when an exterior cell deactivates.
function this:Release()
    self.heights = nil
    self.flags = nil
    self.blockedDirections = nil
    self.count = 0
end

return this
