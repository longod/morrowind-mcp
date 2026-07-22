local this = {}

this.tamrielTimeZone = "Tamriel/Morrowind"

---@param value string?
---@return string?
local function NormalizeIsoOffset(value)
    if type(value) ~= "string" then
        return nil
    end

    local sign, hour, minute = string.match(value, "^([%+%-])(%d%d)(%d%d)$")
    if sign and hour and minute then
        return string.format("%s%s:%s", sign, hour, minute)
    end

    sign, hour, minute = string.match(value, "^([%+%-])(%d%d):(%d%d)$")
    if sign and hour and minute then
        return string.format("%s%s:%s", sign, hour, minute)
    end

    return nil
end


---@class MCP.DateTime
---@field type "real time" -- annotation for agent
---@field year integer
---@field month integer 1 to 12
---@field day integer
---@field hour number
---@field minute integer
---@field second integer
---@field epoch_time number
---@field time_zone string


---@class MCP.DateTimeInGame
---@field type "in-game time" -- annotation for agent
---@field year integer?
---@field month integer? 1 to 12
---@field day integer?
---@field hour number? minutes and seconds are contained in the decimal part
---@field day_count integer
---@field epoch_time number?
---@field time_zone string


---@return MCP.DateTime
function this.Now()
    -- Build a local wall-clock timestamp and keep epoch_time aligned to the same instant.
    local epochTime = os.time()
    local dateTime = os.date("*t", epochTime)

    -- Prefer numeric UTC offset for machine-safe formatting; fall back to zone name, then a stable literal.
    local timeZone = os.date("%z", epochTime)
    if timeZone == nil or timeZone == "" then
        timeZone = os.date("%Z", epochTime)
    end
    if timeZone == nil or timeZone == "" then
        timeZone = "local"
    end

    ---@type MCP.DateTime
    local t = {
        type = "real time",
        year = dateTime.year,
        month = dateTime.month,
        day = dateTime.day,
        hour = dateTime.hour,
        minute = dateTime.min,
        second = dateTime.sec,
        epoch_time = epochTime,
        time_zone = timeZone,
    }
    return t
end

---@return MCP.DateTime
function this.UTCNow()
    -- Use UTC table expansion to avoid local timezone drift in field values.
    local epochTime = os.time()
    local dateTime = os.date("!*t", epochTime)

    ---@type MCP.DateTime
    local t = {
        type = "real time",
        year = dateTime.year,
        month = dateTime.month,
        day = dateTime.day,
        hour = dateTime.hour,
        minute = dateTime.min,
        second = dateTime.sec,
        epoch_time = epochTime,
        time_zone = "UTC",
    }
    return t
end

--- Format MCP.DateTime into ISO 8601 basic date-time text.
--- UTC returns a trailing "Z". Numeric offsets return "+HH:MM" or "-HH:MM".
--- Named zones (for example, "JST") are not standardized offsets and are omitted.
---@param dateTime MCP.DateTime?
---@return string?
function this.ToISO8601(dateTime)
    if not dateTime then
        return nil
    end

    local year = dateTime.year
    local month = dateTime.month
    local day = dateTime.day
    local hour = dateTime.hour
    local minute = dateTime.minute
    local second = dateTime.second
    if not year or not month or not day or not hour or not minute or not second then
        return nil
    end

    local isoText = string.format(
        "%04d-%02d-%02dT%02d:%02d:%02d",
        year,
        month,
        day,
        math.floor(hour),
        math.floor(minute),
        math.floor(second)
    )

    if dateTime.time_zone == "UTC" then
        return isoText .. "Z"
    end

    local offset = NormalizeIsoOffset(dateTime.time_zone)
    if offset then
        return isoText .. offset
    end

    return isoText
end

--- Format in-game time as short human-readable Tamriel text for compact observations.
--- This intentionally drops seconds and simulation epoch details when exact chronology is unnecessary.
---@param inGameTime MCP.DateTimeInGame?
---@return string?
function this.ToInGameShortText(inGameTime)
    if not inGameTime or not inGameTime.year or not inGameTime.month or not inGameTime.day or not inGameTime.hour then
        return nil
    end

    local hour = math.floor(inGameTime.hour)
    local minute = math.floor((inGameTime.hour - hour) * 60)
    return string.format("3E %d-%02d-%02d %02d:%02d", inGameTime.year, inGameTime.month, inGameTime.day, hour, minute)
end

---@return MCP.DateTimeInGame?
function this.InGameNow()
    if tes3.onMainMenu() then
        return nil
    end

    local wc = tes3.worldController
    if wc == nil then
        return nil
    end

    -- Convert MWSE worldController values to MCP-facing schema fields.
    ---@type MCP.DateTimeInGame
    local t = {
        type = "in-game time",
        year = wc.year.value,
        month = wc.month.value + 1, -- convert from 0-based to 1-based
        day = wc.day.value,
        hour = wc.hour.value,       -- minutes and seconds are contained in the decimal part
        day_count = wc.daysPassed.value,
        epoch_time = tes3.getSimulationTimestamp(),
        time_zone = this.tamrielTimeZone,
    }
    return t
end

return this
