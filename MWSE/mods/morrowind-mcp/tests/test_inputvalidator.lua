local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local inputvalidator = require("morrowind-mcp.core.inputvalidator")
    local itool = require("morrowind-mcp.core.itool")
    local http = require("morrowind-mcp.server.http")
    local httpServer = require("morrowind-mcp.server.http_server")
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")
    local menuAction = require("morrowind-mcp.tools.menu_action")
    local screenshotSave = require("morrowind-mcp.tools.screenshot_save")

    unitwind:start("morrowind-mcp.core.inputvalidator")

    local function HasErrorPath(result, path)
        for _, validationError in ipairs(result.errors) do
            if validationError.path == path then
                return true
            end
        end
        return false
    end

    unitwind:test("validates required primitive arguments", function()
        local schema = jsonrpc.InputSchema({
            name = jsonrpc.StringSchema("Name", nil, 1, 8),
            count = jsonrpc.NumberSchema("Count", nil, 0, 10),
            enabled = jsonrpc.BooleanSchema("Enabled"),
        }, { "name", "count", "enabled" })

        local result = inputvalidator.ValidateArguments({
            name = "alpha",
            count = 3,
            enabled = false,
        }, schema)

        unitwind:expect(result.valid).toBe(true)
        unitwind:expect(table.size(result.errors)).toBe(0)
    end)

    unitwind:test("reports missing inputSchema", function()
        local result = inputvalidator.ValidateArguments({}, nil) ---@diagnostic disable-line: param-type-mismatch

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(result.errors[1].path).toBe("$")
        unitwind:expect(result.errors[1].message).toBe("inputSchema is required.")
    end)

    unitwind:test("reports missing required arguments", function()
        local schema = jsonrpc.InputSchema({
            name = jsonrpc.StringSchema("Name"),
        }, { "name" })

        local result = inputvalidator.ValidateArguments({}, schema)

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(result.errors[1].path).toBe("name")
        unitwind:expect(result.errors[1].message).toBe("Required argument is missing.")
    end)

    unitwind:test("reports primitive constraint violations", function()
        local schema = jsonrpc.InputSchema({
            name = jsonrpc.StringSchema("Name", nil, 2, 4),
            count = jsonrpc.NumberSchema("Count", nil, 1, 3),
            enabled = jsonrpc.BooleanSchema("Enabled"),
        })

        local result = inputvalidator.ValidateArguments({
            name = "x",
            count = 4,
            enabled = "yes",
        }, schema)

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(table.size(result.errors)).toBe(3)
        unitwind:expect(HasErrorPath(result, "count")).toBe(true)
        unitwind:expect(HasErrorPath(result, "enabled")).toBe(true)
        unitwind:expect(HasErrorPath(result, "name")).toBe(true)
    end)

    unitwind:test("applies default hard limit to strings without maxLength", function()
        local schema = jsonrpc.InputSchema({
            value = jsonrpc.StringSchema("Value"),
        })

        local validResult = inputvalidator.ValidateArguments({
            value = string.rep("a", inputvalidator.defaultMaxStringLength),
        }, schema)
        local invalidResult = inputvalidator.ValidateArguments({
            value = string.rep("a", inputvalidator.defaultMaxStringLength + 1),
        }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].message).toBe(
            string.format("Expected string length to be at most %d.", inputvalidator.defaultMaxStringLength))
    end)

    unitwind:test("validates single select enum values", function()
        local schema = jsonrpc.InputSchema({
            action = jsonrpc.UntitledSingleSelectEnumSchema({ "mouseClick", "textInput" }, "Action"),
        }, { "action" })

        local validResult = inputvalidator.ValidateArguments({ action = "textInput" }, schema)
        local invalidResult = inputvalidator.ValidateArguments({ action = "invalid" }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].path).toBe("action")
    end)

    unitwind:test("validates titled enum values", function()
        local schema = jsonrpc.InputSchema({
            color = jsonrpc.TitledSingleSelectEnumSchema({
                jsonrpc.ConstTitle("red", "Red"),
                jsonrpc.ConstTitle("blue", "Blue"),
            }, "Color"),
        })

        local validResult = inputvalidator.ValidateArguments({ color = "red" }, schema)
        local invalidResult = inputvalidator.ValidateArguments({ color = "green" }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].path).toBe("color")
    end)

    unitwind:test("validates multi select enum arrays", function()
        local schema = jsonrpc.InputSchema({
            colors = jsonrpc.TitledMultiSelectEnumSchema(
                jsonrpc.TitledMultiSelectEnumSchemaItems({
                    jsonrpc.ConstTitle("red", "Red"),
                    jsonrpc.ConstTitle("blue", "Blue"),
                }),
                "Colors",
                nil,
                1,
                2
            ),
        })

        local validResult = inputvalidator.ValidateArguments({ colors = { "red", "blue" } }, schema)
        local invalidResult = inputvalidator.ValidateArguments({ colors = { "red", "green", "blue" } }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].path).toBe("colors")
        unitwind:expect(invalidResult.errors[2].path).toBe("colors[2]")
    end)

    unitwind:test("honors additionalProperties false for no-argument schemas", function()
        local schema = jsonrpc.InputSchema()

        local validResult = inputvalidator.ValidateArguments(nil, schema)
        local invalidResult = inputvalidator.ValidateArguments({ unexpected = true }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].path).toBe("unexpected")
    end)

    unitwind:test("allows extra arguments when additionalProperties is unset", function()
        local schema = jsonrpc.InputSchema({})

        local result = inputvalidator.ValidateArguments({ extra = true }, schema)

        unitwind:expect(result.valid).toBe(true)
    end)

    unitwind:test("distinguishes object and array table shapes", function()
        local schema = jsonrpc.InputSchema({
            bag = jsonrpc.JsonObjectSchema(),
            items = jsonrpc.JsonArraySchema(),
        })

        local validResult = inputvalidator.ValidateArguments({
            bag = { key = "value" },
            items = { "one", "two" },
        }, schema)
        local invalidResult = inputvalidator.ValidateArguments({
            bag = { "array" },
            items = { key = "value" },
        }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(table.size(invalidResult.errors)).toBe(2)
    end)

    unitwind:test("NormalizeArguments applies schema defaults before validation", function()
        local schema = jsonrpc.InputSchema({
            mode = jsonrpc.StringSchema("Mode", nil, nil, nil, nil, "tap"),
            seconds = jsonrpc.NumberSchema("Seconds", nil, 0, 10, 1.0),
            capture_with_ui = jsonrpc.BooleanSchema("Capture with UI", nil, false),
        }, { "mode", "seconds", "capture_with_ui" })

        local normalizedArguments = inputvalidator.NormalizeArguments({}, schema)
        ---@cast normalizedArguments MCP.AnyMap
        local result = inputvalidator.ValidateArguments(normalizedArguments, schema)

        unitwind:expect(normalizedArguments.mode).toBe("tap")
        unitwind:expect(normalizedArguments.seconds).toBe(1.0)
        unitwind:expect(normalizedArguments.capture_with_ui).toBe(false)
        unitwind:expect(result.valid).toBe(true)
    end)

    unitwind:test("NormalizeArguments preserves explicit values and copies table defaults", function()
        local defaultItems = setmetatable({ "red" }, { __jsontype = "array" })
        local schema = jsonrpc.InputSchema({
            mode = jsonrpc.StringSchema("Mode", nil, nil, nil, nil, "tap"),
            items = {
                type = "array",
                default = defaultItems,
            },
        })

        local originalFirstItem = defaultItems[1]
        local normalizedArguments = inputvalidator.NormalizeArguments({ mode = "push" }, schema)
        ---@cast normalizedArguments MCP.AnyMap
        normalizedArguments.items[1] = "blue"

        unitwind:expect(normalizedArguments.mode).toBe("push")
        unitwind:expect(normalizedArguments.items).NOT.toBe(defaultItems)
        unitwind:expect(normalizedArguments.items[1]).toBe("blue")
        unitwind:expect(originalFirstItem).toBe("red")
        unitwind:expect(getmetatable(normalizedArguments.items).__jsontype).toBe("array")
    end)

    unitwind:test("ValidateUiText rejects reserved UI text characters", function()
        unitwind:expect(inputvalidator.ValidateUiText("plain text", "text").valid).toBe(true)

        for _, character in ipairs({ "|", "@", "#", "^" }) do
            local result = inputvalidator.ValidateUiText("before" .. character .. "after", "text")
            unitwind:expect(result.valid).toBe(false)
            unitwind:expect(result.errors[1].path).toBe("text")
        end
    end)

    unitwind:test("ValidateUiText accepts caller-provided reserved characters", function()
        local validResult = inputvalidator.ValidateUiText("pipe | allowed", "text", { reservedCharacters = { "$" } })
        local invalidResult = inputvalidator.ValidateUiText("gold $ blocked", "text", { reservedCharacters = { "$" } })

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].message).toBe("Reserved UI text character is not allowed: $.")
    end)

    unitwind:test("ValidateUiText supports single-line and multi-line modes", function()
        local defaultResult = inputvalidator.ValidateUiText("line one\nline two", "text")
        local singleLineResult = inputvalidator.ValidateSingleLineUiText("line one\r\nline two", "text")
        local multiLineResult = inputvalidator.ValidateMultiLineUiText("line one\nline two", "text")
        local optionResult = inputvalidator.ValidateUiText("line one\nline two", "text", { allowNewlines = true })

        unitwind:expect(defaultResult.valid).toBe(false)
        unitwind:expect(defaultResult.errors[1].message).toBe("Expected single-line UI text.")
        unitwind:expect(singleLineResult.valid).toBe(false)
        unitwind:expect(multiLineResult.valid).toBe(true)
        unitwind:expect(optionResult.valid).toBe(true)
    end)

    unitwind:test("ValidateUiText keeps legacy reserved-character argument support", function()
        local validResult = inputvalidator.ValidateUiText("pipe | allowed", "text", { "$" })
        local invalidResult = inputvalidator.ValidateUiText("gold $ blocked", "text", { "$" })

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
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
            errors = { {
                path = "bad\npath",
                message = "bad\rmessage\t\1",
            } },
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

    unitwind:test("ITool default Validate uses tool inputSchema", function()
        local tool = itool.new()
        tool.definition = {
            name = "fake",
            inputSchema = jsonrpc.InputSchema({
                name = jsonrpc.StringSchema("Name"),
            }, { "name" }),
        }

        local validResult = tool:Validate({ name = "fake", arguments = { name = "alpha" } })
        local invalidResult = tool:Validate({ name = "fake", arguments = {} })

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(invalidResult.errors[1].path).toBe("name")
    end)

    unitwind:test("tool subclasses can extend Validate", function()
        local customTool = itool.new()
        customTool.definition = {
            name = "fake",
            inputSchema = jsonrpc.InputSchema({
                name = jsonrpc.StringSchema("Name"),
            }, { "name" }),
        }

        function customTool:Validate(params)
            local result = itool.Validate(self, params)
            if result.valid and params.arguments.name == "blocked" then
                result.valid = false
                table.insert(result.errors, {
                    path = "name",
                    message = "Name is blocked.",
                })
            end
            return result
        end

        local result = customTool:Validate({ name = "fake", arguments = { name = "blocked" } })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(result.errors[1].message).toBe("Name is blocked.")
    end)

    unitwind:test("MenuAction Validate rejects unsafe UI text", function()
        local tool = menuAction.new()

        local result = tool:Validate({
            name = "mw-menu-action",
            arguments = {
                menu_name = "nameInput",
                action = "textInput",
                text = "bad|text",
            },
        })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "text")).toBe(true)
    end)

    unitwind:test("ScreenshotSave Validate rejects unsafe file names", function()
        local tool = screenshotSave.new()

        local result = tool:Validate({
            name = "mw-screenshot-save",
            arguments = {
                file_name = "CON",
            },
        })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "file_name")).toBe(true)
    end)

    unitwind:test("OnToolsCall rejects invalid arguments before Execute", function()
        local executed = false
        local fakeTool = {
            definition = {
                inputSchema = jsonrpc.InputSchema({
                    name = jsonrpc.StringSchema("Name"),
                }, { "name" }),
            },
            CanExecute = function()
                return true
            end,
            Validate = function()
                return {
                    valid = false,
                    errors = { {
                        path = "name",
                        message = "Required argument is missing.",
                    } },
                }
            end,
            Execute = function()
                executed = true
                return jsonrpc.CallToolResult(jsonrpc.TextContent("executed"))
            end,
        }
        local fakeServer = {
            tools = { fake = fakeTool },
            logger = {
                warn = function()
                end,
            },
        }

        local result = httpServer.OnToolsCall(fakeServer, { name = "fake", arguments = {} }, nil)
        local callResult = result.result
        ---@cast callResult MCP.CallToolResult

        unitwind:expect(result.http_response).toBe(http.response_code.ok)
        unitwind:expect(callResult.isError).toBe(true)
        unitwind:expect(callResult.content[1].text).toBe("name: Required argument is missing.")
        unitwind:expect(executed).toBe(false)
    end)

    unitwind:test("OnToolsCall executes after valid arguments", function()
        local executed = false
        local fakeTool = {
            definition = {
                inputSchema = jsonrpc.InputSchema(),
            },
            CanExecute = function()
                return true
            end,
            Validate = function()
                return { valid = true, errors = {} }
            end,
            Execute = function()
                executed = true
                return jsonrpc.CallToolResult(jsonrpc.TextContent("executed"))
            end,
        }
        local fakeServer = {
            tools = { fake = fakeTool },
            logger = {
                warn = function()
                end,
            },
            GetProgressToken = function()
                return nil
            end,
            NotifyProgress = function()
                return true
            end,
        }

        local result = httpServer.OnToolsCall(fakeServer, { name = "fake", arguments = {} }, nil)
        local callResult = result.result
        ---@cast callResult MCP.CallToolResult

        unitwind:expect(result.http_response).toBe(http.response_code.ok)
        unitwind:expect(callResult.content[1].text).toBe("executed")
        unitwind:expect(executed).toBe(true)
    end)

    unitwind:test("OnToolsCall normalizes defaults before Validate and Execute", function()
        local validatedSeconds = nil
        local executedSeconds = nil
        local fakeTool = {
            definition = {
                inputSchema = jsonrpc.InputSchema({
                    seconds = jsonrpc.NumberSchema("Seconds", nil, 0, 10, 1.0),
                }, { "seconds" }),
            },
            CanExecute = function()
                return true
            end,
            Validate = function(_, params)
                validatedSeconds = params.arguments.seconds
                return { valid = true, errors = {} }
            end,
            Execute = function(_, arguments)
                executedSeconds = arguments.seconds
                return jsonrpc.CallToolResult(jsonrpc.TextContent("executed"))
            end,
        }
        local fakeServer = {
            tools = { fake = fakeTool },
            logger = {
                warn = function()
                end,
            },
            GetProgressToken = function()
                return nil
            end,
            NotifyProgress = function()
                return true
            end,
        }

        local result = httpServer.OnToolsCall(fakeServer, { name = "fake", arguments = {} }, nil)

        unitwind:expect(result.http_response).toBe(http.response_code.ok)
        unitwind:expect(validatedSeconds).toBe(1.0)
        unitwind:expect(executedSeconds).toBe(1.0)
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
