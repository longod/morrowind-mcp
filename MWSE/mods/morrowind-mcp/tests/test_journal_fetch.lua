local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local journalFetch = require("morrowind-mcp.tools.journal_fetch")

    unitwind:start("morrowind-mcp.tools.journal_fetch")

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

        local monthIndexByName, err = journalFetch.BuildMonthIndexByName()
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
        local parsedDate = journalFetch.ParseDateLabel("16 Theta Harvest (Day 1)", {
            thetaharvest = 8,
        })

        unitwind:expect(parsedDate).NOT.toBe(nil)
        if parsedDate then
            unitwind:expect(parsedDate.day_of_month).toBe(16)
            unitwind:expect(parsedDate.month_number).toBe(8)
            unitwind:expect(parsedDate.day_count).toBe(1)
        end
    end)

    unitwind:test("NormalizeJournalText strips markup and deduplicates keywords", function()
        local text, keywords = journalFetch.NormalizeJournalText(
            "My @orders# are to go to @Balmora# and @report# to @Caius Cosades# in @Balmora# for further @orders#."
        )

        unitwind:expect(text).toBe(
            "My orders are to go to Balmora and report to Caius Cosades in Balmora for further orders."
        )
        unitwind:expect(getmetatable(keywords).__jsontype).toBe("array")
        unitwind:expect(keywords[1]).toBe("orders")
        unitwind:expect(keywords[2]).toBe("Balmora")
        unitwind:expect(keywords[3]).toBe("report")
        unitwind:expect(keywords[4]).toBe("Caius Cosades")
        unitwind:expect(keywords[5]).toBe(nil)
    end)

    unitwind:test("NormalizeJournalText deduplicates keywords case-insensitively", function()
        local _, keywords = journalFetch.NormalizeJournalText(
            "Speak to @Caius Cosades# after you @report# to @caius cosades# and @Report#."
        )

        unitwind:expect(getmetatable(keywords).__jsontype).toBe("array")
        unitwind:expect(keywords[1]).toBe("Caius Cosades")
        unitwind:expect(keywords[2]).toBe("report")
        unitwind:expect(keywords[3]).toBe(nil)
    end)

    unitwind:test("ParseJournalEntries excludes date labels from keywords", function()
        local content =
            "<FONT COLOR=\"9F0000\">16 Theta Harvest (Day 1)</FONT><BR>I should @report# to @Caius Cosades#.<P>"
        local entries = journalFetch.ParseJournalEntries(content, {
            thetaharvest = 8,
        })

        unitwind:expect(getmetatable(entries).__jsontype).toBe("array")
        unitwind:expect(table.size(entries)).toBe(1)
        unitwind:expect(entries[1].date_label).toBe("16 Theta Harvest (Day 1)")
        unitwind:expect(entries[1].sequence).toBe(1)
        unitwind:expect(entries[1].text).toBe("I should report to Caius Cosades.")
        unitwind:expect(entries[1].keywords[1]).toBe("report")
        unitwind:expect(entries[1].keywords[2]).toBe("Caius Cosades")
        unitwind:expect(entries[1].keywords[3]).toBe(nil)
        unitwind:expect(entries[1].parsed_date.month_number).toBe(8)
    end)

    unitwind:finish()
end

return this
