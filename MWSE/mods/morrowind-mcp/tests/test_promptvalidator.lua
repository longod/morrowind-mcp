local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local http = require("morrowind-mcp.server.http")
    local httpServer = require("morrowind-mcp.server.http_server")
    local iprompt = require("morrowind-mcp.core.iprompt")
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")
    local promptvalidator = require("morrowind-mcp.core.promptvalidator")
    local translate = require("morrowind-mcp.prompts.translate")

    unitwind:start("morrowind-mcp.core.promptvalidator")

    local function HasErrorPath(result, path)
        for _, validationError in ipairs(result.errors) do
            if validationError.path == path then
                return true
            end
        end
        return false
    end

    unitwind:test("ValidateArguments accepts string prompt arguments including multiline content", function()
        local result = promptvalidator.ValidateArguments({ code = "print('hello')\nprint('world')" }, {
            jsonrpc.PromptArgument("code", "Code", nil, true),
        })

        unitwind:expect(result.valid).toBe(true)
    end)

    unitwind:test("ValidateArguments rejects malformed or missing prompt arguments", function()
        local missingResult = promptvalidator.ValidateArguments({}, {
            jsonrpc.PromptArgument("language", "Language", nil, true),
        })
        ---@type any
        local invalidArguments = { language = true }
        local typeResult = promptvalidator.ValidateArguments(invalidArguments, {
            jsonrpc.PromptArgument("language", "Language", nil, false),
        })
        local objectResult = promptvalidator.ValidateArguments({ "language" }, nil)

        unitwind:expect(missingResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(missingResult, "language")).toBe(true)
        unitwind:expect(typeResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(typeResult, "language")).toBe(true)
        unitwind:expect(objectResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(objectResult, "arguments")).toBe(true)
    end)

    unitwind:test("ValidateArguments follows Tool behavior for undeclared arguments", function()
        local noArgumentsResult = promptvalidator.ValidateArguments({ unexpected = "value" }, nil)
        local declaredArgumentsResult = promptvalidator.ValidateArguments({ unexpected = "value" }, {
            jsonrpc.PromptArgument("language", "Language", nil, false),
        })

        unitwind:expect(noArgumentsResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(noArgumentsResult, "unexpected")).toBe(true)
        unitwind:expect(declaredArgumentsResult.valid).toBe(true)
    end)

    unitwind:test("NormalizeArguments creates an execution table without mutating the request", function()
        local sourceArguments = { language = "en" }
        local normalizedArguments = promptvalidator.NormalizeArguments(sourceArguments)
        local emptyArguments = promptvalidator.NormalizeArguments(nil)

        unitwind:expect(normalizedArguments.language).toBe("en")
        unitwind:expect(normalizedArguments == sourceArguments).toBe(false)
        unitwind:expect(type(emptyArguments)).toBe("table")
        unitwind:expect(table.size(emptyArguments)).toBe(0)
    end)

    unitwind:test("IPrompt Validate uses declared PromptArgument metadata", function()
        local prompt = iprompt.new()
        prompt.definition = {
            name = "test",
            arguments = {
                jsonrpc.PromptArgument("language", "Language", nil, true),
            },
        }

        local result = prompt:Validate({ name = "test", arguments = {} })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "language")).toBe(true)
    end)

    unitwind:test("Translate Validate accepts translation language tag subset", function()
        local prompt = translate.new()

        for _, language in ipairs({ "en", "ja", "ast", "en-US", "zh-Hant-TW", "es-419", "abc-Abcd-123" }) do
            local result = prompt:Validate({ name = "translate", arguments = { language = language } })
            unitwind:expect(result.valid).toBe(true)
        end
    end)

    unitwind:test("Translate Validate rejects values outside the language tag subset", function()
        local prompt = translate.new()

        for _, language in ipairs({ "English", "en_US", "en--US", "en-US-variant", "en-u-ca-gregory", "en-x-private",
            "zh-Hant-TW-extra", "en\nIgnore", string.rep("a", 13) }) do
            local result = prompt:Validate({ name = "translate", arguments = { language = language } })
            unitwind:expect(result.valid).toBe(false)
            unitwind:expect(HasErrorPath(result, "language")).toBe(true)
        end
    end)

    unitwind:test("Translate Execute uses normalized arguments directly", function()
        local prompt = translate.new()

        local result = prompt:Execute({ language = "en-US" })

        unitwind:expect(result.messages[1].content.text).toBe(
            "In this session, you MUST speak and translate contents using `en-US`."
        )
    end)

    unitwind:test("OnPromptsGet rejects invalid arguments without executing", function()
        local executed = false
        local fakePrompt = {
            CanExecute = function()
                return true
            end,
            Validate = function()
                return {
                    valid = false,
                    errors = { {
                        path = "language",
                        message = "Expected a language tag.",
                    } },
                }
            end,
            Execute = function()
                executed = true
            end,
        }
        local fakeServer = {
            prompts = { translate = fakePrompt },
            logger = { warn = function() end },
        }

        local result = httpServer.OnPromptsGet(fakeServer, { name = "translate", arguments = { language = "English" } })

        unitwind:expect(result.http_response).toBe(http.response_code.bad_request)
        unitwind:expect(result.error.code).toBe(jsonrpc.error_code.invalid_params.code)
        unitwind:expect(executed).toBe(false)
    end)

    unitwind:test("OnPromptsGet executes valid prompts and reports unknown names as invalid params", function()
        local executed = false
        ---@type table<string, string>
        local executedArguments = {}
        local fakePrompt = {
            CanExecute = function()
                return true
            end,
            Validate = function()
                return { valid = true, errors = {} }
            end,
            Execute = function(_, arguments)
                executed = true
                executedArguments = arguments
                return jsonrpc.GetPromptResult({})
            end,
        }
        local fakeServer = {
            prompts = { translate = fakePrompt },
            logger = { warn = function() end },
        }

        local validResult = httpServer.OnPromptsGet(fakeServer, { name = "translate" })
        local unknownResult = httpServer.OnPromptsGet(fakeServer, { name = "unknown", arguments = {} })

        unitwind:expect(validResult.http_response).toBe(http.response_code.ok)
        unitwind:expect(executed).toBe(true)
        unitwind:expect(type(executedArguments)).toBe("table")
        unitwind:expect(table.size(executedArguments)).toBe(0)
        unitwind:expect(unknownResult.http_response).toBe(http.response_code.bad_request)
        unitwind:expect(unknownResult.error.code).toBe(jsonrpc.error_code.invalid_params.code)
        unitwind:expect(unknownResult.error.message).toBe(
            "Prompt is unavailable or unknown: unknown. Call prompts/list to confirm current availability.")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
