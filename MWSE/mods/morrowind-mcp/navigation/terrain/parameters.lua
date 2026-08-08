--- Internal terrain-navigation tuning parameters.
--- These values are implementation details and must not be persisted in the user-facing mod configuration.
---@class MCP.TerrainParameters
---@field interval number Distance in world units between adjacent terrain samples.
---@field maxSlopeDegrees number Steepest terrain normal accepted for walking.
---@field maxClimb number Maximum vertical step that bypasses the slope check.
---@field budgetMode MCP.TerrainGridBudgetMode Per-frame builder stopping policy.
---@field maxSamplesPerFrame integer Sample limit used by samples and hybrid modes.
---@field maxMillisecondsPerFrame number Time limit used by time and hybrid modes.
---@field timeCheckInterval integer Samples processed between elapsed-time checks.

---@type MCP.TerrainParameters
local parameters = {
    interval = 128,
    maxSlopeDegrees = 46,
    maxClimb = 34,
    budgetMode = "hybrid",
    maxSamplesPerFrame = 64,
    maxMillisecondsPerFrame = 2,
    timeCheckInterval = 16,
}

return parameters
