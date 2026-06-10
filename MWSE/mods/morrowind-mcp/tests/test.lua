
local function RunTest()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    unitwind:start("morrowind-mcp")
    local http = require("morrowind-mcp.server.http")

    unitwind:test("Test http.ltrim", function()
        unitwind:expect(http.ltrim("  hello")).toBe("hello")
        unitwind:expect(http.ltrim("nochange")).toBe("nochange")
        unitwind:expect(http.ltrim("   ")).toBe("")
    end)

    unitwind:test("Test http.sendHttpResponse", function()
        local statusLine = "HTTP/1.1 200 OK"
        local headers = { ["Content-Type"] = "text/plain", ["X-Test"] = "1" }
        local body = "Hello"

        local sent
        local client = {}
        function client:send(data)
            sent = data
            return true
        end

        unitwind:spy(client, "send")
        local ok, err = http.sendHttpResponse(client, statusLine, headers, body)
        unitwind:expect(ok).toBe(true)
        unitwind:expect(client.send).toBeCalled()
        unitwind:expect(sent:sub(1, #statusLine)).toBe(statusLine)
        unitwind:expect(sent:find("\r\n\r\n" .. body, 1, true) ~= nil).toBe(true)
        unitwind:unspy(client, "send")
    end)

    unitwind:test("Test http.readHeaders", function()
        local client = {
            lines = {
                "Host: example.com",
                "Content-Length: 5",
                "",
            },
            idx = 1,
        }

        function client:receive(pattern)
            if pattern == "*l" then
                local line = self.lines[self.idx]
                self.idx = self.idx + 1
                return line
            end
            return nil, "unsupported pattern"
        end

        local headers = http.readHeaders(client)
        unitwind:expect(headers).NOT.toBe(nil)
        unitwind:expect(headers["host"]).toBe("example.com")
        unitwind:expect(headers["content-length"]).toBe("5")
    end)

    unitwind:test("Test http.parseRequestMethod", function()
        unitwind:expect(http.parseRequestMethod("GET / HTTP/1.1")).toBe("GET")
        unitwind:expect(http.parseRequestMethod("PATCH /items/1 HTTP/1.1")).toBe("PATCH")
        unitwind:expect(http.parseRequestMethod("INVALID_REQUEST_LINE")).toBe("INVALID_REQUEST_LINE")
    end)

    local function makeRequestClient(requestLine, body)
        local client = {
            lines = {
                requestLine,
                "Host: example.com",
                "Content-Length: 5",
                "",
            },
            idx = 1,
            body = body or "Hello",
        }

        function client:receive(patternOrLen)
            if patternOrLen == "*l" then
                local line = self.lines[self.idx]
                self.idx = self.idx + 1
                return line
            elseif type(patternOrLen) == "number" then
                return self.body
            end
            return nil, "unsupported pattern"
        end

        return client
    end

    unitwind:test("Test http.readHttpRequest", function()
        local methods = { "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD" }
        for _, method in ipairs(methods) do
            local path = method == "GET" and "/" or "/resource"
            local requestLine = string.format("%s %s HTTP/1.1", method, path)
            local client = makeRequestClient(requestLine, "Hello")
            local request = http.readHttpRequest(client)

            unitwind:expect(request).NOT.toBe(nil)
            unitwind:expect(request.method).toBe(method)
            unitwind:expect(request.requestLine).toBe(requestLine)
            unitwind:expect(request.headers["host"]).toBe("example.com")
            unitwind:expect(request.body).toBe("Hello")
        end
    end)

    unitwind:finish()
end

RunTest()
