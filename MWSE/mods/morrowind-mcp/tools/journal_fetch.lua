local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local datetime = require("morrowind-mcp.datetime")

-- improving resource management then maybe no nessessary to fetch some data.
-- possibly too many tools cause dump AI decision.
-- but manual fetch is useful for debugging and testing.

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

---@class MCP.JournalFetch: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager TODO use MCP.IResourceManager
---@field journalCallback fun(e : journalEventData)
---@field loadedCallback fun(e : loadedEventData)
local this = {}
setmetatable(this, { __index = base })


---@param params table?
---@return MCP.JournalFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.JournalFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "journal_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "journal-fetch",
        description =
        "Fetch active journal entries.",
        inputSchema = jsonrpc.InputSchema(
        -- active,
        -- finished, unfinished
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                entries = jsonrpc.JsonArraySchema(),
                current_time = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })

    instance.journalCallback = function(e)
        instance:OnJournalUpdated(e)
    end
    event.register(tes3.event.journal, instance.journalCallback)
    instance.loadedCallback = function(e)
        instance:OnLoaded(e)
    end
    event.register(tes3.event.loaded, instance.loadedCallback)
    return instance
end

function this:Release()
    if self.journalCallback then
        event.unregister(tes3.event.journal, self.journalCallback)
        self.journalCallback = nil
    end
    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end
end

---@param value string?
---@return string?
function this.NormalizeMonthKey(value)
    if not value then
        return nil
    end
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

---@class MCP.JournalParsedDate
---@field day_of_month integer
---@field month_number integer 1 to 12
---@field day_count integer

--- Parse the journal date label into numeric fields suitable for chronological sorting.
---@param dateLabel string?
---@param monthIndexByName table<string, number>
---@return MCP.JournalParsedDate?
function this.ParseDateLabel(dateLabel, monthIndexByName)
    if not dateLabel then
        return nil
    end

    local dayOfMonthText, monthName, dayInfo = dateLabel:match("^(%d+)%s+(.+)%s+%((.-)%)$")
    if not dayOfMonthText or not monthName or not dayInfo then
        return nil
    end

    local dayOfMonth = tonumber(dayOfMonthText)
    local dayCount = tonumber(dayInfo:match("[Dd]ay%s+(%d+)"))
    local monthNumber = monthIndexByName[this.NormalizeMonthKey(monthName)]
    if not dayOfMonth or not dayCount or not monthNumber then
        return nil
    end

    return jsonrpc.object({
        day_of_month = dayOfMonth,
        month_number = monthNumber,
        day_count    = dayCount,
    })
end

--- Convert a journal paragraph into plain text and collect its explicit keyword markup.
---@param value string?
---@return string
---@return table
function this.NormalizeJournalText(value)
    if not value then
        return "", jsonrpc.array()
    end

    local keywords = jsonrpc.array()
    local keywordSeen = {}
    local normalized = value
    normalized = normalized:gsub("@([^#]+)#", function(keyword)
        local keywordKey = keyword ~= "" and keyword:lower() or ""
        if keywordKey ~= "" and not keywordSeen[keywordKey] then
            keywordSeen[keywordKey] = true
            table.insert(keywords, keyword)
        end
        return keyword
    end)
    normalized = normalized:gsub("<[^>]+>", " ")
    normalized = normalized:gsub("\r\n", " ")
    normalized = normalized:gsub("\n", " ")
    normalized = normalized:gsub("\r", " ")
    normalized = normalized:gsub("%s+", " ")
    normalized = string.trim(normalized)

    return normalized, keywords
end

---@class MCP.JournalEntry
---@field date_label string?
---@field sequence integer
---@field text string
---@field keywords string[]
---@field parsed_date MCP.JournalParsedDate

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
    for paragraph in content:gmatch("(.-)<P>") do
        local trimmedParagraph = string.trim(paragraph)
        if trimmedParagraph and trimmedParagraph ~= "" then
            local dateLabel = trimmedParagraph:match("<FONT.-%>(.-)</FONT><BR>")
            local body = trimmedParagraph:match("</FONT><BR>(.*)") or trimmedParagraph
            local normalizedText, keywords = this.NormalizeJournalText(body)

            if normalizedText ~= "" then
                sequence = sequence + 1
                local entry = jsonrpc.object({
                    date_label = dateLabel,
                    sequence = sequence,
                    text = normalizedText,
                    keywords = keywords,
                })
                local parsedDate = this.ParseDateLabel(dateLabel, monthIndexByName)
                if parsedDate then
                    entry.parsed_date = parsedDate
                end
                table.insert(entries, entry)
            end
        end
    end

    return entries
end

---@return MCP.JournalEntry[]?
function this:ReadJournal()
    if tes3.onMainMenu() then
        self.logger:error("Cannot read journal while on main menu.")
        return nil
    end

    -- TODO when on loading or on new game tutorial possible old or other journal.

    local path = journal_path
    if lfs.attributes(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()
            if not content or content == "" then
                self.logger:warn("Journal.htm is empty yet.")
                return nil
            end

            local monthIndexByName, monthError = this.BuildMonthIndexByName()
            if monthIndexByName then
                local entries = this.ParseJournalEntries(content, monthIndexByName)
                if  entries then
                    self.logger:debug("Journal entries count: %d", #entries)
                else
                    self.logger:warn("Journal has no entries yet.")
                end
                return entries
            else
                self.logger:error("Failed to build month lookup: %s", monthError)
            end
        else
            self.logger:error("Failed to open Journal.htm.")
        end
    else
        self.logger:error("Journal.htm not found.")
    end
    return nil
end

function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    -- exclude tutorial?
    return true
end

function this:Execute(params, context)
    -- load <Morrowind>/Journal.htm
    -- perphaps, we can not access to journal entries in a save data.
    -- "JOUR"  recourds in ess stores just html same as journal.htm.
    -- https://en.uesp.net/morrow/tech/mw_esm.txt

    -- https://pt.uesp.net/wiki/Morrowind_Mod:Text_Defines
    -- https://wiki.openmw.org/index.php?title=Research:Dialogue_and_Messages
    -- hyperlink (@*#): https://github.com/OpenMW/openmw/blob/master/apps/openmw/mwdialogue/keywordsearch.cpp#L140

    local entries = self:ReadJournal()
    if not entries then
        local errorContent = jsonrpc.TextContent("Failed to read journal entries.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local currentTime = datetime.InGameNow()
    local structuredContent = jsonrpc.object({
        entries = entries,
        current_time = currentTime,
    })
    return jsonrpc.CallToolResult(nil, structuredContent)

end

---@param e journalEventData
function this:OnJournalUpdated(e)
    -- can execute?

    self.logger:debug("Journal updated")
    local entries = self:ReadJournal()
    if entries then
        -- I considered journal.htm is not written yet. because event data has claim to be updated, be able to block.
        -- but journal.htm is already written. So I can read journal.htm now.
        self.logger:debug("Journal entries count: %d", #entries)
    end

    --[[
    --- resource descriptor
    ---@type MCP.Resource
    local r = {
        name = relativePath,
        uri = resourceUri,
        mimeType = mimeutil.ResolveMimeTypeFromResourcePath(relativePath),
    }

    self.resource:UpdateResource({
        resource = r,
        content = jsonrpc.object({
            entries = entries,
            current_time = datetime.InGameNow(), -- TODO update to response on fetching or reading
        }),
        -- any state, hints.
        -- per palyer? in-game? write to file?
    })
    --]]
end

---@param e loadedEventData
function this:OnLoaded(e)
    -- can execute?

    -- new game is not write journal.htm yet.
    if e.newGame then
        return
    end

    self.logger:debug("Game loaded")
    -- local entries = self:ReadJournal()
    -- if entries then
    --     -- same as on journal updated behavior.
    --     self.logger:debug("Journal entries count: %d", #entries)
    -- end
    -- self.resource: changed
end

return this
