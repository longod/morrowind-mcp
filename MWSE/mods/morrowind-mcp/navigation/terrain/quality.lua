local this = {}

---@class MCP.TerrainHeightMetrics
---@field total integer Number of requested validation positions.
---@field compared integer Positions where both reference and grid heights existed.
---@field missing integer Positions excluded because either height was unavailable.
---@field mae number Mean absolute height error.
---@field rmse number Root-mean-square height error.
---@field max_error number Largest absolute height error.
---@field percentile_95 number Nearest-rank 95th-percentile absolute error.

--- Select a nearest-rank percentile from a mutable error list.
--- Sorting is acceptable because quality measurements are explicit debug work, not route-time processing.
---@param values number[]
---@param percentile number
---@return number
local function Percentile(values, percentile)
    if table.size(values) == 0 then
        return 0
    end
    table.sort(values)
    local index = math.max(1, math.ceil(table.size(values) * percentile))
    return values[index]
end

--- Compare bilinearly reconstructed grid heights with a finer reference sampler over matching world bounds.
--- Missing values are counted separately and excluded from numeric error aggregates.
---@param referenceSampler MCP.TerrainHeightSampler
---@param grid MCP.TerrainGrid
---@param validationInterval number
---@return MCP.TerrainHeightMetrics
function this.EvaluateHeight(referenceSampler, grid, validationInterval)
    local errors = {}
    local squaredError = 0
    local absoluteError = 0
    local maxError = 0
    local missing = 0
    local total = 0
    local maxX = grid.originX + (grid.width - 1) * grid.interval
    local maxY = grid.originY + (grid.height - 1) * grid.interval
    for y = grid.originY, maxY, validationInterval do
        for x = grid.originX, maxX, validationInterval do
            local referenceHeight = referenceSampler:Sample(x, y) ---@diagnostic disable-line: undefined-field
            local gridHeight = grid:InterpolateHeight(x, y) ---@diagnostic disable-line: undefined-field
            total = total + 1
            if referenceHeight and gridHeight then
                local errorValue = math.abs(referenceHeight - gridHeight)
                table.insert(errors, errorValue)
                absoluteError = absoluteError + errorValue
                squaredError = squaredError + errorValue * errorValue
                maxError = math.max(maxError, errorValue)
            else
                missing = missing + 1
            end
        end
    end
    local compared = table.size(errors)
    return {
        total = total,
        compared = compared,
        missing = missing,
        mae = compared > 0 and absoluteError / compared or 0,
        rmse = compared > 0 and math.sqrt(squaredError / compared) or 0,
        max_error = maxError,
        percentile_95 = Percentile(errors, 0.95),
    }
end

return this
