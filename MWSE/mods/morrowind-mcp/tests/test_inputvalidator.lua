local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local inputvalidator = require("morrowind-mcp.core.input_validator")

    unitwind:start("morrowind-mcp.core.input_validator")

    unitwind:test("ValidateUiText rejects reserved UI text characters", function()
        unitwind:expect(inputvalidator.ValidateUiText("plain text", "text").valid).toBe(true)

        for _, character in ipairs({ "|", "@", "#", "^" }) do
            local result = inputvalidator.ValidateUiText("before" .. character .. "after", "text")
            unitwind:expect(result.valid).toBe(false)
            unitwind:expect(result.errors[1].path).toBe("text")
        end
    end)

    unitwind:test("ValidateUiText supports caller-defined and multiline policies", function()
        local validResult = inputvalidator.ValidateUiText("pipe | allowed", "text", { reservedCharacters = { "$" } })
        local invalidResult = inputvalidator.ValidateUiText("gold $ blocked", "text", { reservedCharacters = { "$" } })
        local singleLineResult = inputvalidator.ValidateSingleLineUiText("line one\r\nline two", "text")
        local multiLineResult = inputvalidator.ValidateMultiLineUiText("line one\nline two", "text")

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(singleLineResult.valid).toBe(false)
        unitwind:expect(multiLineResult.valid).toBe(true)
    end)

    unitwind:test("ValidateFileName rejects unsafe Windows file names", function()
        unitwind:expect(inputvalidator.ValidateFileName("screenshot_01", "file_name").valid).toBe(true)
        unitwind:expect(inputvalidator.ValidateFileName("bad/name", "file_name").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateFileName("bad\1name", "file_name").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateFileName("CON", "file_name").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateFileName("LPT1.txt", "file_name").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateFileName("trailing.", "file_name").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateFileName("trailing ", "file_name").valid).toBe(false)
    end)

    unitwind:test("FormatErrors escapes control characters", function()
        local message = inputvalidator.FormatErrors({
            valid = false,
            errors = { { path = "bad\npath", message = "bad\rmessage\t\1" } },
        })

        unitwind:expect(message).toBe("bad\\npath: bad\\rmessage\\t\\x01")
    end)

    unitwind:test("ValidateResourcePath accepts only safe relative resource paths", function()
        unitwind:expect(inputvalidator.ValidateResourcePath("folder/file.txt", "uri").valid).toBe(true)
        unitwind:expect(inputvalidator.ValidateResourcePath("../file.txt", "uri").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateResourcePath("/file.txt", "uri").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateResourcePath("folder//file.txt", "uri").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateResourcePath("folder\\file.txt", "uri").valid).toBe(false)
        unitwind:expect(inputvalidator.ValidateResourcePath("C:/file.txt", "uri").valid).toBe(false)
    end)

    unitwind:test("ValidateResourceUri checks scheme encoding and decoded path safety", function()
        unitwind:expect(inputvalidator.ValidateResourceUri("morrowind://folder/file.txt", "morrowind://", "uri").valid)
            .toBe(true)
        unitwind:expect(inputvalidator.ValidateResourceUri("http://folder/file.txt", "morrowind://", "uri").valid)
            .toBe(false)
        unitwind:expect(inputvalidator.ValidateResourceUri("morrowind://folder/file%2", "morrowind://", "uri").valid)
            .toBe(false)
        unitwind:expect(inputvalidator.ValidateResourceUri("morrowind://..%2Ffile.txt", "morrowind://", "uri").valid)
            .toBe(false)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
