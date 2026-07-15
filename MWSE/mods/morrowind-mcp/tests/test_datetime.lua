local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.util.datetime")

    unitwind:test("Now returns local real-time fields", function()
        local now = datetime.Now()

        unitwind:expect(now).NOT.toBe(nil)
        if now then
            unitwind:expect(now.type).toBe("real time")
            unitwind:expect(now.year ~= nil).toBe(true)
            unitwind:expect(now.month >= 1 and now.month <= 12).toBe(true)
            unitwind:expect(now.day ~= nil).toBe(true)
            unitwind:expect(now.hour ~= nil).toBe(true)
            unitwind:expect(now.minute ~= nil).toBe(true)
            unitwind:expect(now.second ~= nil).toBe(true)
            unitwind:expect(now.epoch_time ~= nil).toBe(true)
            unitwind:expect(type(now.time_zone)).toBe("string")
            unitwind:expect(now.time_zone ~= "").toBe(true)
        end
    end)

    unitwind:test("Now uses numeric offset first", function()
        unitwind:mock(os, "time", function()
            return 1700000000
        end)

        unitwind:mock(os, "date", function(format, epoch)
            if format == "*t" then
                return {
                    year = 2026,
                    month = 7,
                    day = 10,
                    hour = 12,
                    min = 34,
                    sec = 56,
                }
            end
            if format == "%z" then
                return "+0900"
            end
            if format == "%Z" then
                return "JST"
            end
            return nil
        end)

        local now = datetime.Now()

        unitwind:unmock(os, "date")
        unitwind:unmock(os, "time")

        unitwind:expect(now.time_zone).toBe("+0900")
        unitwind:expect(now.minute).toBe(34)
        unitwind:expect(now.second).toBe(56)
        unitwind:expect(now.epoch_time).toBe(1700000000)
    end)

    unitwind:test("Now falls back to zone-name when offset is empty", function()
        unitwind:mock(os, "time", function()
            return 1700000001
        end)

        unitwind:mock(os, "date", function(format, epoch)
            if format == "*t" then
                return {
                    year = 2026,
                    month = 7,
                    day = 10,
                    hour = 12,
                    min = 34,
                    sec = 57,
                }
            end
            if format == "%z" then
                return ""
            end
            if format == "%Z" then
                return "JST"
            end
            return nil
        end)

        local now = datetime.Now()

        unitwind:unmock(os, "date")
        unitwind:unmock(os, "time")

        unitwind:expect(now.time_zone).toBe("JST")
    end)

    unitwind:test("Now falls back to local when both timezone formats are empty", function()
        unitwind:mock(os, "time", function()
            return 1700000002
        end)

        unitwind:mock(os, "date", function(format, epoch)
            if format == "*t" then
                return {
                    year = 2026,
                    month = 7,
                    day = 10,
                    hour = 12,
                    min = 34,
                    sec = 58,
                }
            end
            if format == "%Z" then
                return ""
            end
            if format == "%z" then
                return ""
            end
            return nil
        end)

        local now = datetime.Now()

        unitwind:unmock(os, "date")
        unitwind:unmock(os, "time")

        unitwind:expect(now.time_zone).toBe("local")
    end)

    unitwind:test("UTCNow returns UTC real-time fields", function()
        local utcNow = datetime.UTCNow()

        unitwind:expect(utcNow).NOT.toBe(nil)
        if utcNow then
            unitwind:expect(utcNow.type).toBe("real time")
            unitwind:expect(utcNow.month >= 1 and utcNow.month <= 12).toBe(true)
            unitwind:expect(utcNow.minute ~= nil).toBe(true)
            unitwind:expect(utcNow.second ~= nil).toBe(true)
            unitwind:expect(utcNow.time_zone).toBe("UTC")
        end
    end)

    unitwind:test("ToISO8601 formats UTC with Z suffix", function()
        local isoText = datetime.ToISO8601({
            type = "real time",
            year = 2026,
            month = 7,
            day = 11,
            hour = 9,
            minute = 8,
            second = 7,
            epoch_time = 0,
            time_zone = "UTC",
        })

        unitwind:expect(isoText).toBe("2026-07-11T09:08:07Z")
    end)

    unitwind:test("ToISO8601 formats numeric timezone offset", function()
        local isoText = datetime.ToISO8601({
            type = "real time",
            year = 2026,
            month = 7,
            day = 11,
            hour = 9,
            minute = 8,
            second = 7,
            epoch_time = 0,
            time_zone = "+0900",
        })

        unitwind:expect(isoText).toBe("2026-07-11T09:08:07+09:00")
    end)

    unitwind:test("ToISO8601 omits non-offset timezone names", function()
        local isoText = datetime.ToISO8601({
            type = "real time",
            year = 2026,
            month = 7,
            day = 11,
            hour = 9,
            minute = 8,
            second = 7,
            epoch_time = 0,
            time_zone = "JST",
        })

        unitwind:expect(isoText).toBe("2026-07-11T09:08:07")
    end)

    unitwind:test("ToISO8601 returns nil for invalid input", function()
        local isoText = datetime.ToISO8601({
            type = "real time",
            year = 2026,
            month = 7,
            day = 11,
            hour = 9,
            minute = nil, ---@diagnostic disable-line: assign-type-mismatch
            second = 7,
            epoch_time = 0,
            time_zone = "UTC",
        })

        unitwind:expect(isoText).toBe(nil)
    end)

    unitwind:test("InGameNow returns nil on main menu", function()
        unitwind:mock(tes3, "onMainMenu", function()
            return true
        end)

        local inGameNow = datetime.InGameNow()

        unitwind:unmock(tes3, "onMainMenu")

        unitwind:expect(inGameNow).toBe(nil)
    end)

    unitwind:test("InGameNow returns nil when worldController is missing", function()
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "worldController", nil)

        local inGameNow = datetime.InGameNow()

        unitwind:unmock(tes3, "worldController")
        unitwind:unmock(tes3, "onMainMenu")

        unitwind:expect(inGameNow).toBe(nil)
    end)

    unitwind:test("InGameNow maps worldController fields", function()
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "worldController", {
            year = { value = 427 },
            month = { value = 0 },
            day = { value = 16 },
            hour = { value = 13.25 },
            daysPassed = { value = 1001 },
        })
        unitwind:mock(tes3, "getSimulationTimestamp", function()
            return 98765
        end)

        local inGameNow = datetime.InGameNow()

        unitwind:unmock(tes3, "getSimulationTimestamp")
        unitwind:unmock(tes3, "worldController")
        unitwind:unmock(tes3, "onMainMenu")

        unitwind:expect(inGameNow).NOT.toBe(nil)
        if inGameNow then
            unitwind:expect(inGameNow.type).toBe("in-game time")
            unitwind:expect(inGameNow.year).toBe(427)
            unitwind:expect(inGameNow.month).toBe(1)
            unitwind:expect(inGameNow.day).toBe(16)
            unitwind:expect(inGameNow.hour).toBe(13.25)
            unitwind:expect(inGameNow.day_count).toBe(1001)
            unitwind:expect(inGameNow.epoch_time).toBe(98765)
            unitwind:expect(inGameNow.time_zone).toBe("Tamriel/Morrowind")
        end
    end)

    unitwind:finish()
end

return this
