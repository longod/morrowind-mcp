local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local datetime = require("morrowind-mcp.util.datetime")
    local journal = require("morrowind-mcp.resources.journal")

    unitwind:start("morrowind-mcp.tools.resources.journal")

    unitwind:test("BuildMonthIndexByName resolves month order from GMST", function()
        local values = {
            [tes3.gmst.sMonthMorningstar] = { value = "Alpha Dawn" },
            [tes3.gmst.sMonthSunsdawn] = { value = "Beta Rise" },
            [tes3.gmst.sMonthFirstseed] = { value = "Gamma Seed" },
            [tes3.gmst.sMonthRainshand] = { value = "Delta Rain" },
            [tes3.gmst.sMonthSecondseed] = { value = "Epsilon Seed" },
            [tes3.gmst.sMonthMidyear] = { value = "Zeta Year" },
            [tes3.gmst.sMonthSunsheight] = { value = "Eta Height" },
            [tes3.gmst.sMonthLastseed] = { value = "Theta Harvest" },
            [tes3.gmst.sMonthHeartfire] = { value = "Iota Fire" },
            [tes3.gmst.sMonthFrostfall] = { value = "Kappa Fall" },
            [tes3.gmst.sMonthSunsdusk] = { value = "Lambda Dusk" },
            [tes3.gmst.sMonthEveningstar] = { value = "Mu Star" },
        }

        unitwind:mock(tes3, "findGMST", function(id)
            return values[id]
        end)

        local monthIndexByName, err = journal.BuildMonthIndexByName()
        unitwind:unmock(tes3, "findGMST")

        unitwind:expect(err).toBe(nil)
        unitwind:expect(monthIndexByName).NOT.toBe(nil)
        if monthIndexByName then
            unitwind:expect(monthIndexByName.alphadawn).toBe(1)
            unitwind:expect(monthIndexByName.thetaharvest).toBe(8)
            unitwind:expect(monthIndexByName.mustar).toBe(12)
            unitwind:expect(monthIndexByName.lambdadusk).toBe(11)
        end
    end)

    unitwind:test("ParseDateLabel returns numeric parsed_date fields", function()
        local parsedDate = journal.ParseDateLabel("16 Theta Harvest (Day 1)", {
            thetaharvest = 8,
        })

        unitwind:expect(parsedDate).NOT.toBe(nil)
        if parsedDate then
            unitwind:expect(parsedDate.day_of_month).toBe(16)
            unitwind:expect(parsedDate.month_number).toBe(8)
            unitwind:expect(parsedDate.day_count).toBe(1)
        end
    end)

    unitwind:test("ParseJournalEntries excludes date labels from topics", function()
        local content =
        "<FONT COLOR=\"9F0000\">16 Theta Harvest (Day 1)</FONT><BR>I should @report# to @Caius Cosades#.<P>"
        local entries = journal.ParseJournalEntries(content, {
            thetaharvest = 8,
        })

        unitwind:expect(getmetatable(entries).__jsontype).toBe("array")
        unitwind:expect(table.size(entries)).toBe(1)
        unitwind:expect(entries[1].date_label).toBe("16 Theta Harvest (Day 1)")
        unitwind:expect(entries[1].sequence).toBe(1)
        unitwind:expect(entries[1].text).toBe("I should report to Caius Cosades.")
        unitwind:expect(entries[1].topics[1]).toBe("report")
        unitwind:expect(entries[1].topics[2]).toBe("Caius Cosades")
        unitwind:expect(entries[1].topics[3]).toBe(nil)
        unitwind:expect(entries[1].in_game_time.type).toBe("in-game time")
        unitwind:expect(entries[1].in_game_time.day_count).toBe(1)
        unitwind:expect(entries[1].in_game_time.time_zone).toBe(datetime.tamrielTimeZone)
    end)

    unitwind:test("ToInGameTime returns partial datetime on vanilla calendar", function()
        local dateTime = journal.ToInGameTime({
            type = "in-game time",
            day_of_month = 16,
            month_number = 8,
            day_count = 1,
            time_zone = datetime.tamrielTimeZone,
        }, false)

        unitwind:expect(dateTime).NOT.toBe(nil)
        if dateTime then
            unitwind:expect(dateTime.type).toBe("in-game time")
            unitwind:expect(dateTime.day_count).toBe(1)
            unitwind:expect(dateTime.time_zone).toBe(datetime.tamrielTimeZone)
            unitwind:expect(dateTime.year).toBe(nil)
            unitwind:expect(dateTime.month).toBe(8)
            unitwind:expect(dateTime.day).toBe(16)
        end
    end)

    unitwind:test("ToInGameTime reconstructs year with calendar fix", function()
        local dateTime = journal.ToInGameTime({
            type = "in-game time",
            day_of_month = 1,
            month_number = 3,
            day_count = 198,
            time_zone = datetime.tamrielTimeZone,
        }, true)

        unitwind:expect(dateTime).NOT.toBe(nil)
        if dateTime then
            unitwind:expect(dateTime.year).toBe(428)
            unitwind:expect(dateTime.month).toBe(3)
            unitwind:expect(dateTime.day).toBe(1)
            unitwind:expect(dateTime.day_count).toBe(198)
        end
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
