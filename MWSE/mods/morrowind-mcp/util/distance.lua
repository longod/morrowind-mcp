local this = {}

-- MWSE uses game units for almost all engine lengths, including positions and distances.
-- The engine conversion factor is 22.1 game units per foot; this is preferred over
-- the inaccurate values described in the Construction Set help.
local gameUnitsPerFoot = 22.1
-- Use the international foot definition when exposing the equivalent SI distance.
local metersPerFoot = 0.3048

local metersPerGameUnit = metersPerFoot / gameUnitsPerFoot
local gameUnitsPerMeter = gameUnitsPerFoot / metersPerFoot

--- Convert a Morrowind world distance to meters.
---@param units number Distance in Morrowind game units.
---@return number meters Distance in meters.
function this.ToMeters(units)
    return units * metersPerGameUnit
end

--- Convert a metric world distance to Morrowind game units.
---@param meters number Distance in meters.
---@return number units Distance in Morrowind game units.
function this.ToUnits(meters)
    return meters * gameUnitsPerMeter
end

return this
