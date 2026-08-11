local this = {}

-- MWSE uses game units for almost all engine lengths, including positions and distances.
-- The engine conversion factor is 22.1 game units per foot; this is preferred over
-- the inaccurate values described in the Construction Set help.
local gameUnitsPerFoot = 22.1
-- Use the international foot definition when exposing the equivalent SI distance.
local metersPerFoot = 0.3048

--- Convert a Morrowind world distance to meters.
---@param units number Distance in Morrowind game units.
---@return number meters Distance in meters.
function this.ToMeters(units)
    return units * metersPerFoot / gameUnitsPerFoot
end

return this
