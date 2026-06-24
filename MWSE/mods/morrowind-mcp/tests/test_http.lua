local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local http = require("morrowind-mcp.server.http")

    unitwind:start("morrowind-mcp.server.http")

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

    unitwind:test("ReceiveRequest reads request line, headers and body", function()
        local responses = {
            {"POST /hello HTTP/1.1"},
            {"Host: example.com"},
            {"Content-Length: 5"},
            {""},
            {"world"},
        }

        local client = {
            receive = function(self, pattern, ...)
                local response = table.remove(responses, 1)
                if not response then
                    return nil, "closed", nil
                end
                return response[1], response[2], response[3]
            end,
        }

        local request, err, partial = http.ReceiveRequest(client)

        unitwind:expect(err).toBe(nil)
        unitwind:expect(partial).toBe(nil)
        if request then
            unitwind:expect(request.method).toBe("POST")
            unitwind:expect(request.endpoint).toBe("/hello")
            unitwind:expect(request.protocol).toBe("HTTP/1.1")
            unitwind:expect(request.headers.host).toBe("example.com")
            unitwind:expect(request.headers["content-length"]).toBe("5")
            unitwind:expect(request.body).toBe("world")
        end
    end)

    unitwind:test("SendResponse writes HTTP status, json content type and body", function()
        local sentData = ""
        local client = {
            send = function(self, data, i, j)
                sentData = data
                return #data, nil, #data
            end,
        }

        local result = http.SendResponse(client, http.response_code.ok, nil, '{"ok":true}')
        unitwind:expect(result.index).toBe(#sentData)
        unitwind:expect(result.error).toBe(nil)
        unitwind:expect(result.lastIndex).toBe(#sentData)
        unitwind:expect(result.response).toBe(sentData)
        unitwind:expect(result.response:match("HTTP/1%.1 200 OK")).toBe("HTTP/1.1 200 OK")
        unitwind:expect(result.response:match("content%-type: application/json")).toBe("content-type: application/json")
        unitwind:expect(result.response:match('{"ok":true}')).toBe('{"ok":true}')
    end)

    unitwind:finish()
end

return this
