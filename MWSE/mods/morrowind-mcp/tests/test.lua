
local function RunTest()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    unitwind:start("morrowind-mcp")

    do
        local strutil = require("morrowind-mcp.strutil")

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
            unitwind:expect(parts[1]).toBe("a")
            unitwind:expect(parts[2]).toBe("b")
            unitwind:expect(parts[3]).toBe("c")

            unitwind:expect(strutil.split("abc", "")[1]).toBe("abc")
            unitwind:expect(strutil.split("abc", nil)[1]).toBe("abc")

            local p2 = strutil.split("abc", ",")
            unitwind:expect(#p2).toBe(1)
            unitwind:expect(p2[1]).toBe("abc")
        end)
    end

    do
        local http = require("morrowind-mcp.server.http")

        unitwind:test("ParseRequestMethod parses request line", function()
            local method, endpoint, protocol = http.ParseRequestMethod("GET / HTTP/1.1")
            unitwind:expect(method).toBe("GET")
            unitwind:expect(endpoint).toBe("/")
            unitwind:expect(protocol).toBe("HTTP/1.1")

            local bad = http.ParseRequestMethod("INVALID")
            unitwind:expect(bad).toBe(nil)
        end)

        unitwind:test("ParseHeader parses header lines", function()
            local name, value = http.ParseHeader("Host: example.com")
            unitwind:expect(name).toBe("host")
            unitwind:expect(value).toBe("example.com")

            local n2, v2 = http.ParseHeader("NoColonHeader")
            unitwind:expect(n2).toBe(nil)
            unitwind:expect(v2).toBe(nil)
        end)
    end

    unitwind:finish()
end

RunTest()
