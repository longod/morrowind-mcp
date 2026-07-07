local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

---@return number[]
local function GetMonthGmstIds()
    return {
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
end

---@class MCP.JournalFetch: MCP.ITool
---@field logger mwseLogger
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
    return instance
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
    local monthGmstIds = GetMonthGmstIds()
    local monthIndexByName = {}
    for index, gmstId in ipairs(monthGmstIds) do
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

--- Parse the journal date label into numeric fields suitable for chronological sorting.
---@param dateLabel string?
---@param monthIndexByName table<string, number>
---@return MCP.AnyMap?
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
        day_count  = dayCount,
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

--- Parse Journal.htm into lightweight structured entries without game-data cross references.
---@param content string?
---@param monthIndexByName table<string, number>
---@return table
function this.ParseJournalEntries(content, monthIndexByName)
    local entries = jsonrpc.array()
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

    local path = tes3.installDirectory .. "\\Journal.htm"
    if lfs.attributes(path) then
        local file = io.open(path, "r")
        if file then
            local content = file:read("*a")
            file:close()

            local monthIndexByName, monthError = this.BuildMonthIndexByName()
            if not monthIndexByName then
                local errorContent = jsonrpc.TextContent(monthError or "failed to build month lookup.")
                return jsonrpc.CallToolResult(errorContent, nil, true)
            end

            local wc = tes3.worldController
            local currentTime = {
                year = wc.year.value,
                month = wc.month.value + 1, -- convert from 0-based to 1-based
                day = wc.day.value,
                hour = wc.hour.value, -- minutes and seconds are contained in the decimal part
                day_count = wc.daysPassed.value,
            }

            local entries = this.ParseJournalEntries(content, monthIndexByName)
            local structuredContent = jsonrpc.object({
                entries = entries,
                current_time = currentTime
             })
            return jsonrpc.CallToolResult(nil, structuredContent)
        else
            local errorContent = jsonrpc.TextContent("failed to open Journal.htm.")
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end
    else
        local errorContent = jsonrpc.TextContent("Journal.htm not found.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

end

return this
