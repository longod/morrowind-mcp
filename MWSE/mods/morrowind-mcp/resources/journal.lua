local this = {}
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "journal" })
local pathutil = require("morrowind-mcp.core.pathutil")
local mcp = require("morrowind-mcp.core.mcp")
local settings = require("morrowind-mcp.settings")
local dialogue = require("morrowind-mcp.util.dialogue")
local datetime = require("morrowind-mcp.util.datetime")

-- Reconstruct journal dates against the canonical game start used by Morrowind's in-game calendar.
local tamrielMonthLengths = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local tamrielYearDays = 365
local gameStartYear = 427
local gameStartMonth = 8
local gameStartDay = 16


---@class MCP.JournalEntry
---@field date_label string?
---@field sequence integer
---@field text string
---@field topics string[]
---@field in_game_time MCP.DateTimeInGame

---@class MCP.JournalParsedDate
---@field type "in-game time" -- annotation for agent
---@field day_of_month integer
---@field month_number integer 1 to 12
---@field day_count integer
---@field time_zone string


---@return number[]
local month_gmst = {
    tes3.gmst.sMonthMorningstar,
    tes3.gmst.sMonthSunsdawn,
    tes3.gmst.sMonthFirstseed,
    tes3.gmst.sMonthRainshand,
    tes3.gmst.sMonthSecondseed,
    tes3.gmst.sMonthMidyear,
    tes3.gmst.sMonthSunsheight,
    tes3.gmst.sMonthLastseed,
    tes3.gmst.sMonthHeartfire,
    tes3.gmst.sMonthFrostfall,
    tes3.gmst.sMonthSunsdusk,
    tes3.gmst.sMonthEveningstar,
}
local journal_path = tes3.installDirectory .. "\\Journal.htm"

---@param value string?
---@return string?
function this.NormalizeMonthKey(value)
    if not value then
        return nil
    end
    -- Keep only alphabetic characters so month names can be compared consistently.
    local normalized = value:lower():gsub("[^%a]", "")
    return normalized
end

--- Build a lookup from normalized in-game month names to a 1-based month index.
---@return table<string, number>?
---@return string?
function this.BuildMonthIndexByName()
    local monthIndexByName = {}
    for index, gmstId in ipairs(month_gmst) do
        local gameSetting = tes3.findGMST(gmstId)
        if not gameSetting or type(gameSetting.value) ~= "string" or gameSetting.value == "" then
            return nil, "failed to resolve month GMST: " .. tostring(gmstId)
        end

        local monthNameKey = this.NormalizeMonthKey(gameSetting.value)
        if monthNameKey then
            monthIndexByName[monthNameKey] = index
        end
    end
    return monthIndexByName, nil
end

---@return boolean
local function HasCalendarFix()
    -- MWSE exposes the MCP patch feature constants in this environment, so a direct lookup keeps
    -- the runtime check aligned with the engine's canonical feature id.
    return tes3.hasCodePatchFeature(tes3.codePatchFeature.calendarFix) == true
end

---@return integer
local function GetGameStartDayOfYearOffset()
    local dayOffset = gameStartDay - 1
    for monthIndex = 1, gameStartMonth - 1 do
        dayOffset = dayOffset + tamrielMonthLengths[monthIndex]
    end
    return dayOffset
end

--- Parse the journal date label into numeric fields suitable for chronological sorting.
---@param dateLabel string?
---@param monthIndexByName table<string, number>
---@return MCP.JournalParsedDate?
function this.ParseDateLabel(dateLabel, monthIndexByName)
    if not dateLabel then
        return nil
    end

    -- Split labels like "1st Morning Star (Day 1)" into day, month name, and day counter.
    local dayOfMonthText, monthName, dayInfo = dateLabel:match("^(%d+)%s+(.+)%s+%((.-)%)$")
    if not dayOfMonthText or not monthName or not dayInfo then
        return nil
    end

    local dayOfMonth = tonumber(dayOfMonthText)
    -- Read the in-game day number from the trailing parenthesized text.
    local dayCount = tonumber(dayInfo:match("[Dd]ay%s+(%d+)"))
    local monthNumber = monthIndexByName[this.NormalizeMonthKey(monthName)]
    if not dayOfMonth or not dayCount or not monthNumber then
        return nil
    end
    ---@type MCP.JournalParsedDate
    local date = {
        type = "in-game time",
        day_of_month = dayOfMonth,
        month_number = monthNumber,
        day_count    = dayCount,
        time_zone = datetime.tamrielTimeZone,
    }
    return jsonrpc.object(date)
end

--- Convert a parsed journal date into an in-game datetime shape.
--- Without the calendar code patch, vanilla Morrowind does not expose a reliable full calendar,
--- so only the parsed month/day plus day_count are preserved.
---@param parsedDate MCP.JournalParsedDate?
---@param hasCalendarFixOverride boolean?
---@return MCP.DateTimeInGame?
function this.ToInGameTime(parsedDate, hasCalendarFixOverride)
    if not parsedDate then
        return nil
    end

    local dayCount = parsedDate.day_count
    local day = parsedDate.day_of_month
    local month = parsedDate.month_number
    if not dayCount then
        return nil
    end

    ---@type MCP.DateTimeInGame
    local dateTime = {
        type = "in-game time",
        day = day,
        month = month,
        day_count = math.floor(dayCount),
        time_zone = parsedDate.time_zone or datetime.tamrielTimeZone,
    }

    -- Tests can override the patch state, but production code should follow the active MCP setting.
    local hasCalendarFix = hasCalendarFixOverride
    if hasCalendarFix == nil then
        hasCalendarFix = HasCalendarFix()
    end

    if not hasCalendarFix then
        return dateTime
    end

    local elapsedDays = dateTime.day_count - 1
    if elapsedDays < 0 then
        return nil
    end

    local absoluteDay = GetGameStartDayOfYearOffset() + elapsedDays
    dateTime.year = gameStartYear + math.floor(absoluteDay / tamrielYearDays)

    -- Prefer the journal label's month/day when present; only synthesize missing fields from day_count.
    if dateTime.month and dateTime.day then
        return dateTime
    end

    local dayOfYear = (absoluteDay % tamrielYearDays) + 1
    local computedMonth = 1
    while dayOfYear > tamrielMonthLengths[computedMonth] do
        dayOfYear = dayOfYear - tamrielMonthLengths[computedMonth]
        computedMonth = computedMonth + 1
    end

    if not dateTime.month then
        dateTime.month = computedMonth
    end
    if not dateTime.day then
        dateTime.day = dayOfYear
    end

    return dateTime
end

--- Parse Journal.htm into lightweight structured entries without game-data cross references.
---@param content string
---@param monthIndexByName table<string, number>
---@return MCP.JournalEntry[]
function this.ParseJournalEntries(content, monthIndexByName)
    local entries = jsonrpc.array(256)
    if not content or content == "" then
        return entries
    end

    local sequence = 0
    -- Journal.htm separates entries with <P>, so iterate one paragraph at a time.
    for paragraph in content:gmatch("(.-)<P>") do
        local trimmedParagraph = string.trim(paragraph)
        if trimmedParagraph and trimmedParagraph ~= "" then
            -- Capture the date label that precedes the body text.
            local dateLabel = trimmedParagraph:match("<FONT.-%>(.-)</FONT><BR>")
            -- Take the text after the date block as the entry body.
            local body = trimmedParagraph:match("</FONT><BR>(.*)") or trimmedParagraph
            local normalizedText, topics = dialogue.NormalizeDialogueText(body)

            if normalizedText ~= "" then
                sequence = sequence + 1
                ---@type MCP.JournalEntry
                local entry = jsonrpc.object({
                    date_label = dateLabel,
                    sequence = sequence,
                    text = normalizedText,
                    topics = topics,
                })
                local parsedDate = this.ParseDateLabel(dateLabel, monthIndexByName)
                if parsedDate then
                    entry.in_game_time = this.ToInGameTime(parsedDate)
                end
                table.insert(entries, entry)
            end
        end
    end

    return entries
end

-- load <Morrowind>/Journal.htm
-- perphaps, we can not access to journal entries in a save data.
-- "JOUR"  recourds in ess stores just html same as journal.htm.
-- https://en.uesp.net/morrow/tech/mw_esm.txt
-- https://en.uesp.net/wiki/Morrowind_Mod:Text_Defines
-- hyperlink (@*#)

---@return MCP.JournalEntry[]?
function this.ReadJournal()
    if tes3.onMainMenu() then
        logger:error("Cannot read journal while on main menu.")
        return nil
    end

    local path = journal_path
    if lfs.attributes(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            if not content or content == "" then
                logger:warn("Journal.htm is empty yet.")
                return nil
            end

            local monthIndexByName, monthError = this.BuildMonthIndexByName()
            if monthIndexByName then
                local entries = this.ParseJournalEntries(content, monthIndexByName)
                if entries then
                    logger:debug("Journal entries count: %d", #entries)
                else
                    logger:warn("Journal has no entries yet.")
                end
                return entries
            else
                logger:error("Failed to build month lookup: %s", monthError)
            end
        else
            logger:error("Failed to open Journal.htm.")
        end
    else
        logger:error("Journal.htm not found.")
    end
    return nil
end

---@param desc MCP.Resource
---@return MCP.ResourceContent[]
function this.GetContents(desc)
    local entries = this.ReadJournal()
    local content = jsonrpc.TextResourceContents(desc.uri, json.encode(entries, { indent = false }), desc.mimeType)
    return { content }
end

local relativePath = "game/journal.json"
local uri = pathutil.ToUri(relativePath, settings.uriScheme) -- TODO wrapper?, injected scheme

---@type MCP.ResourceEntry
local entry = {
    descriptor = {
        name = relativePath,
        title = "Journal",
        uri = uri,
        description = "Current player's journal entries.",
        mimeType = mcp.mimeType.application_json,
        annotations = jsonrpc.Annotations(nil, nil, nil),
        -- size = nil,
    },
    handler = this.GetContents,
}

-- contain ResourceEntry?
this.link = jsonrpc.ResourceLink(entry.descriptor.name, entry.descriptor.uri, entry.descriptor.title, entry.descriptor.description, entry.descriptor.mimeType)

---@param e journalEventData
---@param resource MCP.ResourceManager
local function OnJournalUpdated(e, resource)
    -- can execute?

    logger:debug("Journal updated")
    -- I considered journal.htm is not written yet. because event data has claim to be updated, be able to block.
    -- but journal.htm is already written. So I can read journal.htm now.

    resource:PublishResource(entry)
end

---@param e loadedEventData
---@param resource MCP.ResourceManager
local function OnLoaded(e, resource)
    -- can execute?

    -- new game is not write journal.htm yet.
    if e.newGame then
        resource:UnpublishResource(entry.descriptor.uri)
        return
    end

    logger:debug("Game loaded")
    resource:PublishResource(entry)
end

local journalCallback = nil ---@type fun(e : journalEventData)?
local loadedCallback = nil ---@type fun(e : loadedEventData)?

---@param resource MCP.ResourceManager
function this.RegisterEvent(resource)
    journalCallback = function(e)
        OnJournalUpdated(e, resource)
    end
    event.register(tes3.event.journal, journalCallback)
    loadedCallback = function(e)
        OnLoaded(e, resource)
    end
    event.register(tes3.event.loaded, loadedCallback)
    logger:debug("Journal event handlers registered")
end

function this.UnregisterEvent()
    if journalCallback then
        event.unregister(tes3.event.journal, journalCallback)
        journalCallback = nil
    end
    if loadedCallback then
        event.unregister(tes3.event.loaded, loadedCallback)
        loadedCallback = nil
    end
    logger:debug("Journal event handlers unregistered")
end

return this
