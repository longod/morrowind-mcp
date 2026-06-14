local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local strutil = require("morrowind-mcp.strutil")

    unitwind:start("morrowind-mcp.strutil")

    unitwind:test("ltrim removes leading spaces", function()
        unitwind:expect(strutil.ltrim("   abc")).toBe("abc")
        unitwind:expect(strutil.ltrim("abc")).toBe("abc")
        unitwind:expect(strutil.ltrim("   ")).toBe("")
    end)

    unitwind:test("startswith works", function()
        unitwind:expect(strutil.startswith("hello", "he")).toBe(true)
        unitwind:expect(strutil.startswith("hello", "hello")).toBe(true)
        unitwind:expect(strutil.startswith("hello", "world")).toBe(false)
        unitwind:expect(strutil.startswith("", "")).toBe(true)
    end)

    unitwind:test("endswith works", function()
        unitwind:expect(strutil.endswith("hello", "lo")).toBe(true)
        unitwind:expect(strutil.endswith("hello", "")).toBe(true)
        unitwind:expect(strutil.endswith("hello", "hell")).toBe(false)
    end)

    unitwind:test("split works", function()
        local parts = strutil.split("a,b,c", ",")
        unitwind:expect(type(parts)).toBe("table")
        unitwind:expect(#parts).toBe(3)
        unitwind:expect(parts).NOT.toBe(nil)
        if parts then
            unitwind:expect(parts[1]).toBe("a")
            unitwind:expect(parts[2]).toBe("b")
            unitwind:expect(parts[3]).toBe("c")
        end

        unitwind:expect(strutil.split("abc", "")[1]).toBe("abc")
        unitwind:expect(strutil.split("abc", nil)[1]).toBe("abc") ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(strutil.split(nil, " ")).toBe(nil)

        local p2 = strutil.split("abc", ",")
        unitwind:expect(#p2).toBe(1)
        if p2 then
            unitwind:expect(p2[1]).toBe("abc")
        end
    end)

    unitwind:finish()
end

return this
