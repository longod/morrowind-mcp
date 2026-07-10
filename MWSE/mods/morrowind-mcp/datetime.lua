local this = {}

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
---@field year integer
---@field month integer 1 to 12
---@field day integer
---@field hour number minutes and seconds are contained in the decimal part
---@field day_count integer
---@field epoch_time number
---@field time_zone string

---@return MCP.DateTime
function this.Now()
    -- Build a local wall-clock timestamp and keep epoch_time aligned to the same instant.
    local epochTime = os.time()
    local dateTime = os.date("*t", epochTime)

    -- Prefer a human-readable zone name; fall back to numeric offset, then a stable literal.
    local timeZone = os.date("%Z", epochTime)
    if timeZone == nil or timeZone == "" then
        timeZone = os.date("%z", epochTime)
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
        time_zone = "Tamriel/Morrowind",
    }
    return t
end

return this
