local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local http = require("morrowind-mcp.server.http")

    unitwind:start("morrowind-mcp.http")

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

    unitwind:finish()
end

return this
