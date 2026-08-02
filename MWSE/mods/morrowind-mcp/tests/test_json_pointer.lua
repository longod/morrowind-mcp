local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local jsonpointer = require("morrowind-mcp.core.json_pointer")

    unitwind:start("morrowind-mcp.core.json_pointer")

    unitwind:test("EscapeToken escapes tilde before slash", function()
        unitwind:expect(jsonpointer.EscapeToken("a~b/c")).toBe("a~0b~1c")
    end)

    unitwind:test("EscapeToken leaves plain tokens intact", function()
        unitwind:expect(jsonpointer.EscapeToken("MenuBook_button_prev")).toBe("MenuBook_button_prev")
    end)

    unitwind:test("DecodeToken restores tilde and slash from encoded form", function()
        local decoded, errorMessage = jsonpointer.DecodeToken("a~0b~1c")
        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(decoded).toBe("a~b/c")
    end)

    unitwind:test("DecodeToken rejects unknown escape sequences", function()
        local decoded, errorMessage = jsonpointer.DecodeToken("bad~2escape")
        unitwind:expect(decoded).toBe(nil)
        unitwind:expect(errorMessage ~= nil).toBe(true)
    end)

    unitwind:test("Escape and decode round-trip preserves RFC 6901 reserved characters", function()
        local original = "Child/with~characters"
        local decoded, errorMessage = jsonpointer.DecodeToken(jsonpointer.EscapeToken(original))
        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(decoded).toBe(original)
    end)

    unitwind:test("Parse requires a leading slash", function()
        local tokens, errorMessage = jsonpointer.Parse("children/0")
        unitwind:expect(tokens).toBe(nil)
        unitwind:expect(errorMessage ~= nil).toBe(true)
    end)

    unitwind:test("Parse splits multiple tokens and decodes escapes", function()
        local tokens, errorMessage = jsonpointer.Parse("/children/0/a~1b")
        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(tokens == nil).toBe(false)
        if tokens then
            unitwind:expect(table.size(tokens)).toBe(3)
            unitwind:expect(tokens[1]).toBe("children")
            unitwind:expect(tokens[2]).toBe("0")
            unitwind:expect(tokens[3]).toBe("a/b")
        end
    end)

    unitwind:test("Parse yields a single empty token for '/'", function()
        local tokens, errorMessage = jsonpointer.Parse("/")
        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(tokens == nil).toBe(false)
        if tokens then
            unitwind:expect(table.size(tokens)).toBe(1)
            unitwind:expect(tokens[1]).toBe("")
        end
    end)

    unitwind:test("Parse surfaces malformed escapes with a pointer-specific message", function()
        local tokens, errorMessage = jsonpointer.Parse("/children/~2")
        unitwind:expect(tokens).toBe(nil)
        unitwind:expect(errorMessage ~= nil).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
