local this = {}

---@return MCP.UnitWindResult
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
            { "POST /hello HTTP/1.1" },
            { "Host: example.com" },
            { "Content-Length: 5" },
            { "" },
            { "world" },
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
            unitwind:expect(request.headers["host"]).toBe("example.com")
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

    unitwind:test("SendResponse terminates empty response headers", function()
        local sentData = ""
        local client = {
            send = function(self, data, i, j)
                sentData = data
                return #data, nil, #data
            end,
        }

        local result = http.SendResponse(client, http.response_code.accepted)
        unitwind:expect(result.error).toBe(nil)
        unitwind:expect(result.response).toBe("HTTP/1.1 202 Accepted\r\n\r\n")
        unitwind:expect(sentData).toBe(result.response)
    end)

    unitwind:test("AcceptsContentType handles exact and wildcard media ranges", function()
        unitwind:expect(http.AcceptsContentType("application/json, text/event-stream", http.content_type.event_stream))
            .toBe(true)
        unitwind:expect(http.AcceptsContentType("text/*;q=0.9", http.content_type.event_stream)).toBe(true)
        unitwind:expect(http.AcceptsContentType("*/*", http.content_type.json)).toBe(true)
        unitwind:expect(http.AcceptsContentType("application/json", http.content_type.event_stream)).toBe(false)
        unitwind:expect(http.AcceptsContentType(nil, http.content_type.event_stream)).toBe(false)
    end)

    unitwind:test("FormatServerSentEvent writes SSE data frame", function()
        local event = http.FormatServerSentEvent('{"jsonrpc":"2.0","method":"notifications/message"}', "message", "1",
            1000)
        unitwind:expect(event).toBe(
        "id: 1\nevent: message\nretry: 1000\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\"}\n\n")
    end)

    unitwind:test("SendSSEHeaders writes event-stream response headers without body", function()
        local sentData = ""
        local client = {
            send = function(self, data, i, j)
                sentData = data
                return #data, nil, #data
            end,
        }

        local result = http.SendSSEHeaders(client, { [http.mcp_header.mcp_session_id] = "session-1" })
        unitwind:expect(result.error).toBe(nil)
        unitwind:expect(result.response).toBe(sentData)
        unitwind:expect(result.response:match("HTTP/1%.1 200 OK")).toBe("HTTP/1.1 200 OK")
        unitwind:expect(result.response:match("content%-type: text/event%-stream")).toBe(
        "content-type: text/event-stream")
        unitwind:expect(result.response:match("cache%-control: no%-cache")).toBe("cache-control: no-cache")
        unitwind:expect(result.response:match("mcp%-session%-id: session%-1")).toBe("mcp-session-id: session-1")
    end)

    unitwind:test("SendServerSentEvent writes one SSE message", function()
        local sentData = ""
        local client = {
            send = function(self, data, i, j)
                sentData = data
                return #data, nil, #data
            end,
        }

        local result = http.SendServerSentEvent(client, "hello", "message", "42", 500)
        unitwind:expect(result.error).toBe(nil)
        unitwind:expect(result.index).toBe(#sentData)
        unitwind:expect(result.lastIndex).toBe(#sentData)
        unitwind:expect(result.response).toBe("id: 42\nevent: message\nretry: 500\ndata: hello\n\n")
    end)

    unitwind:test("PrepareResponseHeaders copies headers and sets close when needed", function()
        local copied = http.PrepareResponseHeaders({ [http.header.content_type] = http.content_type.json }, false)
        if copied then
            unitwind:expect(copied[http.header.content_type]).toBe(http.content_type.json)
            unitwind:expect(copied[http.header.connection]).toBe(http.connection_type.close)
        end

        local keepHeaders = { [http.header.connection] = http.connection_type.keep }
        local same = http.PrepareResponseHeaders(keepHeaders, true)
        unitwind:expect(same).toBe(keepHeaders)
    end)

    unitwind:test("IsFailureHttpStatus detects 4xx and 5xx", function()
        unitwind:expect(http.IsFailureHttpStatus(http.response_code.ok)).toBe(false)
        unitwind:expect(http.IsFailureHttpStatus(http.response_code.bad_request)).toBe(true)
        unitwind:expect(http.IsFailureHttpStatus(http.response_code.internal_server_error)).toBe(true)
        unitwind:expect(http.IsFailureHttpStatus(nil)).toBe(false)
    end)

    unitwind:test("IsClosedBeforeRequest matches closed with empty partial", function()
        unitwind:expect(http.IsClosedBeforeRequest(nil, "closed", nil)).toBe(true)
        unitwind:expect(http.IsClosedBeforeRequest(nil, "closed", "")).toBe(true)
        unitwind:expect(http.IsClosedBeforeRequest(nil, "timeout", nil)).toBe(false)
        unitwind:expect(http.IsClosedBeforeRequest(
        { method = "GET", endpoint = "/", protocol = "HTTP/1.1", headers = {} }, "closed", nil)).toBe(false)
        unitwind:expect(http.IsClosedBeforeRequest(nil, "closed", "partial")).toBe(false)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
