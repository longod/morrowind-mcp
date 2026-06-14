local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local jsonrpc = require("morrowind-mcp.server.jsonrpc")

    unitwind:start("morrowind-mcp.jsonrpc")

    unitwind:test("request returns parse_error for invalid JSON", function()
        local result, err = jsonrpc.request("not json")
        unitwind:expect(result).toBe(nil)
        unitwind:expect(err).toBe(jsonrpc.error_code.parse_error)
    end)

    unitwind:test("request returns invalid_request for wrong jsonrpc version", function()
        local payload = json.encode({ jsonrpc = "1.0", method = "foo" })
        local result, err = jsonrpc.request(payload)
        unitwind:expect(result).toBe(nil)
        unitwind:expect(err).toBe(jsonrpc.error_code.invalid_request)
    end)

    unitwind:test("request parses valid request", function()
        local payload = json.encode({
            jsonrpc = "2.0",
            id = 1,
            method = "foo",
            params = { x = 42 },
        })
        local request, err = jsonrpc.request(payload)
        unitwind:expect(err).toBe(nil)
        if request then
            unitwind:expect(request.jsonrpc).toBe("2.0")
            unitwind:expect(request.id).toBe(1)
            unitwind:expect(request.method).toBe("foo")
            unitwind:expect(request.params.x).toBe(42)
        end
    end)

    unitwind:test("request parses notification without id", function()
        local payload = json.encode({
            jsonrpc = "2.0",
            method = "notify",
            params = { key = "value" },
        })
        local request, err = jsonrpc.request(payload)
        unitwind:expect(err).toBe(nil)
        if request then
            unitwind:expect(request.jsonrpc).toBe("2.0")
            unitwind:expect(request.id).toBe(nil)
            unitwind:expect(request.method).toBe("notify")
            unitwind:expect(request.params.key).toBe("value")
        end
    end)

    unitwind:test("result encodes JSON-RPC result", function()
        local resultJson = jsonrpc.result(1, { hello = "world" })
        unitwind:expect(resultJson).toBe(json.encode({
            jsonrpc = "2.0",
            id = 1,
            result = { hello = "world" },
        }, { indent = false }))
    end)

    unitwind:test("error encodes JSON-RPC error with data", function()
        local errorJson = jsonrpc.error(1, jsonrpc.error_code.method_not_found, { reason = "missing" })
        local actual = json.decode(errorJson)
        local expected = json.decode(json.encode({
        jsonrpc = "2.0",
        id = 1,
        error = {
            code = -32601,
            message = "Method not found",
            data = { reason = "missing" },
        },
        }))
        unitwind:expect(actual.jsonrpc).toBe("2.0")
        unitwind:expect(actual.id).toBe(1)
        unitwind:expect(actual.error.code).toBe(-32601)
        unitwind:expect(actual.error.message).toBe("Method not found")
        unitwind:expect(actual.error.data.reason).toBe("missing")
    end)

    unitwind:test("notification encodes JSON-RPC notification", function()
        local notificationJson = jsonrpc.notification("update", { x = 1 })
        unitwind:expect(notificationJson).toBe(json.encode({
            jsonrpc = "2.0",
            method = "update",
            params = { x = 1 },
        }, { indent = false }))
    end)

    unitwind:finish()
end

return this
