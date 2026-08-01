local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local inputvalidator = require("morrowind-mcp.core.inputvalidator")
    local toolvalidator = require("morrowind-mcp.core.toolvalidator")
    local itool = require("morrowind-mcp.core.itool")
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")

    unitwind:start("morrowind-mcp.core.toolvalidator")

    local function HasErrorPath(result, path)
        for _, validationError in ipairs(result.errors) do
            if validationError.path == path then
                return true
            end
        end
        return false
    end

    unitwind:test("validates required primitive arguments and constraints", function()
        local schema = jsonrpc.InputSchema({
            name = jsonrpc.StringSchema("Name", nil, 2, 4),
            count = jsonrpc.NumberSchema("Count", nil, 1, 3),
            enabled = jsonrpc.BooleanSchema("Enabled"),
        }, { "name", "count", "enabled" })

        local validResult = toolvalidator.ValidateArguments({ name = "beta", count = 3, enabled = false }, schema)
        local invalidResult = toolvalidator.ValidateArguments({ name = "x", count = 4, enabled = "yes" }, schema)
        local missingResult = toolvalidator.ValidateArguments({}, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(invalidResult, "name")).toBe(true)
        unitwind:expect(HasErrorPath(invalidResult, "count")).toBe(true)
        unitwind:expect(HasErrorPath(invalidResult, "enabled")).toBe(true)
        unitwind:expect(HasErrorPath(missingResult, "name")).toBe(true)
    end)

    unitwind:test("requires inputSchema and bounds unspecified strings", function()
        local missingSchemaResult = toolvalidator.ValidateArguments({}, nil) ---@diagnostic disable-line: param-type-mismatch
        local schema = jsonrpc.InputSchema({ value = jsonrpc.StringSchema("Value") })
        local validResult = toolvalidator.ValidateArguments({
            value = string.rep("a", inputvalidator.defaultMaxStringLength),
        }, schema)
        local invalidResult = toolvalidator.ValidateArguments({
            value = string.rep("a", inputvalidator.defaultMaxStringLength + 1),
        }, schema)

        unitwind:expect(missingSchemaResult.valid).toBe(false)
        unitwind:expect(missingSchemaResult.errors[1].message).toBe("inputSchema is required.")
        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
    end)

    unitwind:test("validates enum values and array constraints", function()
        local schema = jsonrpc.InputSchema({
            action = jsonrpc.UntitledSingleSelectEnumSchema({ "mouseClick", "textInput" }, "Action"),
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

        local validResult = toolvalidator.ValidateArguments({ action = "textInput", colors = { "red", "blue" } }, schema)
        local invalidResult = toolvalidator.ValidateArguments({ action = "invalid", colors = { "red", "green", "blue" } }, schema)

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(invalidResult, "action")).toBe(true)
        unitwind:expect(HasErrorPath(invalidResult, "colors")).toBe(true)
        unitwind:expect(HasErrorPath(invalidResult, "colors[2]")).toBe(true)
    end)

    unitwind:test("enforces object shape and additional property policy", function()
        local strictSchema = jsonrpc.InputSchema()
        local shapeSchema = jsonrpc.InputSchema({
            bag = jsonrpc.JsonObjectSchema(),
            items = jsonrpc.JsonArraySchema(),
        })

        local strictResult = toolvalidator.ValidateArguments({ unexpected = true }, strictSchema)
        local validShapeResult = toolvalidator.ValidateArguments({ bag = { key = "value" }, items = { "one" } }, shapeSchema)
        local invalidShapeResult = toolvalidator.ValidateArguments({ bag = { "array" }, items = { key = "value" } }, shapeSchema)

        unitwind:expect(strictResult.valid).toBe(false)
        unitwind:expect(validShapeResult.valid).toBe(true)
        unitwind:expect(invalidShapeResult.valid).toBe(false)
        unitwind:expect(table.size(invalidShapeResult.errors)).toBe(2)
    end)

    unitwind:test("NormalizeArguments applies defaults without mutating schema values", function()
        local defaultItems = setmetatable({ "red" }, { __jsontype = "array" })
        local schema = jsonrpc.InputSchema({
            mode = jsonrpc.StringSchema("Mode", nil, nil, nil, nil, "tap"),
            items = { type = "array", default = defaultItems },
        }, { "mode" })

        local normalizedArguments = toolvalidator.NormalizeArguments({}, schema)
        ---@cast normalizedArguments MCP.AnyMap
        normalizedArguments.items[1] = "blue"

        unitwind:expect(normalizedArguments.mode).toBe("tap")
        unitwind:expect(normalizedArguments.items).NOT.toBe(defaultItems)
        unitwind:expect(normalizedArguments.items[1]).toBe("blue")
        unitwind:expect(defaultItems[1]).toBe("red")
        unitwind:expect(getmetatable(normalizedArguments.items).__jsontype).toBe("array")
    end)

    unitwind:test("ITool delegates schema validation to ToolValidator", function()
        local tool = itool.new()
        tool.definition = {
            name = "fake",
            inputSchema = jsonrpc.InputSchema({ name = jsonrpc.StringSchema("Name") }, { "name" }),
        }

        local validResult = tool:Validate({ name = "fake", arguments = { name = "alpha" } })
        local invalidResult = tool:Validate({ name = "fake", arguments = {} })

        unitwind:expect(validResult.valid).toBe(true)
        unitwind:expect(invalidResult.valid).toBe(false)
        unitwind:expect(HasErrorPath(invalidResult, "name")).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
