local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local jsonrpc = require("morrowind-mcp.server.jsonrpc")

    local function ResetPrimitivePrefix()
        jsonrpc.SetPrimitivePrefix("", "", "")
    end

    unitwind:start("morrowind-mcp.server.jsonrpc")

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

    unitwind:test("request parses JSON-RPC response", function()
        local payload = json.encode({
            jsonrpc = "2.0",
            id = "server-1",
            result = {},
        })
        local response, err = jsonrpc.request(payload)
        unitwind:expect(err).toBe(nil)
        if response then
            unitwind:expect(response.jsonrpc).toBe("2.0")
            unitwind:expect(response.id).toBe("server-1")
            unitwind:expect(response.result == nil).toBe(false)
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

    unitwind:test("RequestMessage encodes JSON-RPC request", function()
        local requestJson = jsonrpc.RequestMessage("server-1", "ping")
        unitwind:expect(requestJson).toBe(json.encode({
            jsonrpc = "2.0",
            id = "server-1",
            method = "ping",
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
        local notificationJson = jsonrpc.notification("ping", { x = 1 })
        unitwind:expect(notificationJson).toBe(json.encode({
            jsonrpc = "2.0",
            method = "ping",
            params = { x = 1 },
        }, { indent = false }))
    end)

    unitwind:test("Content generators build text, image and audio blocks", function()
        local textContent = jsonrpc.TextContent("hello")
        unitwind:expect(textContent.type).toBe("text")
        unitwind:expect(textContent.text).toBe("hello")

        local imageContent = jsonrpc.ImageContent("imgdata", "image/png")
        unitwind:expect(imageContent.type).toBe("image")
        unitwind:expect(imageContent.data).toBe("imgdata")
        unitwind:expect(imageContent.mimeType).toBe("image/png")

        local audioContent = jsonrpc.AudioContent("audiodata", "audio/mpeg")
        unitwind:expect(audioContent.type).toBe("audio")
        unitwind:expect(audioContent.data).toBe("audiodata")
        unitwind:expect(audioContent.mimeType).toBe("audio/mpeg")
    end)

    unitwind:test("Content generators build resource blocks", function()
        local textResource = jsonrpc.TextResourceContents("mcp://text", "body", "text/plain")
        unitwind:expect(textResource.uri).toBe("mcp://text")
        unitwind:expect(textResource.text).toBe("body")
        unitwind:expect(textResource.mimeType).toBe("text/plain")

        local blobResource = jsonrpc.BlobResourceContents("mcp://blob", "YmFzZTY0", "application/json")
        unitwind:expect(blobResource.uri).toBe("mcp://blob")
        unitwind:expect(blobResource.blob).toBe("YmFzZTY0")
        unitwind:expect(blobResource.mimeType).toBe("application/json")

        local embedded = jsonrpc.EmbeddedResource(textResource)
        unitwind:expect(embedded.type).toBe("resource")
        unitwind:expect(embedded.resource.uri).toBe("mcp://text")

        local resourceLink = jsonrpc.ResourceLink("name", "mcp://link", "title", "desc", "text/plain", nil, 123)
        unitwind:expect(resourceLink.type).toBe("resource_link")
        unitwind:expect(resourceLink.name).toBe("name")
        unitwind:expect(resourceLink.uri).toBe("mcp://link")
        unitwind:expect(resourceLink.size).toBe(123)
    end)

    unitwind:test("Tool generators build schema, execution and annotations", function()
        local schema = jsonrpc.InputSchema(
            { name = { type = "string" } },
            { "name" },
            "https://json-schema.org/draft/2020-12/schema"
        )
        unitwind:expect(schema.type).toBe("object")
        unitwind:expect(schema.required[1]).toBe("name")
        unitwind:expect(schema.properties.name.type).toBe("string")

        local execution = jsonrpc.ToolExecution("optional")
        unitwind:expect(execution.taskSupport).toBe("optional")

        local annotations = jsonrpc.ToolAnnotations("Title", true, false, true, false)
        unitwind:expect(annotations.title).toBe("Title")
        unitwind:expect(annotations.readOnlyHint).toBe(true)
        unitwind:expect(annotations.destructiveHint).toBe(false)
        unitwind:expect(annotations.idempotentHint).toBe(true)
        unitwind:expect(annotations.openWorldHint).toBe(false)
    end)

    unitwind:test("ToolObjectSchema keeps required and reports missing keys", function()
        local schema, validRequired = jsonrpc.InputSchema(
            {
                name = { type = "string" },
                age = { type = "number" },
            },
            { "name", "missing", "age" },
            "https://json-schema.org/draft/2020-12/schema"
        )

        unitwind:expect(validRequired).toBe(false)
        unitwind:expect(type(schema.required)).toBe("table")
        unitwind:expect(table.size(schema.required)).toBe(3)
        unitwind:expect(schema.required[1]).toBe("name")
        unitwind:expect(schema.required[2]).toBe("missing")
        unitwind:expect(schema.required[3]).toBe("age")
    end)

    unitwind:test("ToolObjectSchema reports false when required is valid", function()
        local schema, validRequired = jsonrpc.InputSchema(
            {
                value = { type = "string" },
            },
            { "value" },
            "https://json-schema.org/draft/2020-12/schema"
        )

        unitwind:expect(validRequired).toBe(true)
        unitwind:expect(schema.required[1]).toBe("value")
    end)

    unitwind:test("Tool generator builds MCP.Tool from single ToolInput argument", function()
        ResetPrimitivePrefix()
        local inputSchema = jsonrpc.InputSchema(
            { value = { type = "string" } },
            { "value" },
            "https://json-schema.org/draft/2020-12/schema"
        )

        local tool = jsonrpc.Tool({
            name = "test_tool",
            title = "Test Tool",
            description = "Returns state of on main menu",
            inputSchema = inputSchema,
            execution = jsonrpc.ToolExecution("optional"),
            outputSchema = jsonrpc.OutputSchema(nil, nil, "https://json-schema.org/draft/2020-12/schema"),
            annotations = jsonrpc.ToolAnnotations("Test Tool", true, false, true, false),
        })

        unitwind:expect(tool.name).toBe("test_tool")
        unitwind:expect(tool.title).toBe("Test Tool")
        unitwind:expect(tool.inputSchema.type).toBe("object")
        unitwind:expect(tool.execution.taskSupport).toBe("optional")
        unitwind:expect(tool.annotations.readOnlyHint).toBe(true)
    end)

    unitwind:test("Tool generator applies configured primitive prefixes", function()
        jsonrpc.SetPrimitivePrefix("mw_", "[MW] ", "[MW] ")

        local tool = jsonrpc.Tool({
            name = "test_tool",
            title = "Test Tool",
            description = "Returns state of on main menu",
            inputSchema = jsonrpc.InputSchema(),
        })

        unitwind:expect(tool.name).toBe("mw_test_tool")
        unitwind:expect(tool.title).toBe("[MW] Test Tool")
        unitwind:expect(tool.description).toBe("[MW] Returns state of on main menu")

        ResetPrimitivePrefix()
    end)

    unitwind:test("Tool generator keeps nil title and description with prefixes", function()
        jsonrpc.SetPrimitivePrefix("mw_", "[MW] ", "[MW] ")

        local tool = jsonrpc.Tool({
            name = "test_tool",
            title = nil,
            description = nil,
            inputSchema = jsonrpc.InputSchema(),
        })

        unitwind:expect(tool.name).toBe("mw_test_tool")
        unitwind:expect(tool.title).toBe(nil)
        unitwind:expect(tool.description).toBe(nil)

        ResetPrimitivePrefix()
    end)

    unitwind:test("Tool generator keeps additionalProperties unset for empty inputSchema.properties", function()
        ResetPrimitivePrefix()
        local inputSchema = jsonrpc.InputSchema({}, nil, "https://json-schema.org/draft/2020-12/schema")
        local outputSchema = jsonrpc.OutputSchema({}, nil, "https://json-schema.org/draft/2020-12/schema")

        local tool = jsonrpc.Tool({
            name = "no_params_tool",
            description = "Tool with no parameters",
            inputSchema = inputSchema,
            outputSchema = outputSchema,
        })

        unitwind:expect(tool.inputSchema.additionalProperties).toBe(nil)
    end)

    unitwind:test("Tool generator keeps MCP.Tool inputSchema required", function()
        ResetPrimitivePrefix()
        local tool = jsonrpc.Tool({
            name = "implicit_input_schema_tool",
            description = "Tool with generated input schema",
            inputSchema = jsonrpc.InputSchema(),
        })

        unitwind:expect(tool.inputSchema.type).toBe("object")
        unitwind:expect(tool.inputSchema.additionalProperties).toBe(false)
    end)

    unitwind:test("ListPromptsResult prepares MCP array field", function()
        local result = jsonrpc.ListPromptsResult(2)
        unitwind:expect(type(result)).toBe("table")
        unitwind:expect(type(result.prompts)).toBe("table")
        unitwind:expect(getmetatable(result.prompts).__jsontype).toBe("array")
        unitwind:expect(result.nextCursor).toBe(nil)
    end)

    unitwind:test("CompleteResult accepts array and metadata", function()
        local result = jsonrpc.CompleteResult({ "one", "two" }, 2, true)
        unitwind:expect(getmetatable(result.completion.values).__jsontype).toBe("array")
        unitwind:expect(result.completion.values[1]).toBe("one")
        unitwind:expect(result.completion.values[2]).toBe("two")
        unitwind:expect(result.completion.total).toBe(2)
        unitwind:expect(result.completion.hasMore).toBe(true)
    end)

    unitwind:test("CreateTaskResult copies task object", function()
        local result = jsonrpc.CreateTaskResult({
            taskId = "task-1",
            status = "working",
            createdAt = "2026-06-22T00:00:00Z",
            lastUpdatedAt = "2026-06-22T00:00:00Z",
        })
        unitwind:expect(result.task.taskId).toBe("task-1")
        unitwind:expect(result.task.status).toBe("working")
    end)

    unitwind:test("ListTasksResult accepts nextCursor", function()
        local result = jsonrpc.ListTasksResult({ { taskId = "task-1" } }, "cursor-1")
        unitwind:expect(getmetatable(result.tasks).__jsontype).toBe("array")
        unitwind:expect(result.tasks[1].taskId).toBe("task-1")
        unitwind:expect(result.nextCursor).toBe("cursor-1")
    end)

    unitwind:test("GetPromptResult accepts description", function()
        local result = jsonrpc.GetPromptResult({ { role = "user", content = { type = "text", text = "hi" } } },
            "prompt-desc")
        unitwind:expect(getmetatable(result.messages).__jsontype).toBe("array")
        unitwind:expect(result.messages[1].role).toBe("user")
        unitwind:expect(result.description).toBe("prompt-desc")
    end)

    unitwind:test("ListResourceTemplatesResult accepts nextCursor", function()
        local result = jsonrpc.ListResourceTemplatesResult({ { name = "template-1", uriTemplate = "mcp://foo" } },
            "cursor-2")
        unitwind:expect(getmetatable(result.resourceTemplates).__jsontype).toBe("array")
        unitwind:expect(result.resourceTemplates[1].name).toBe("template-1")
        unitwind:expect(result.nextCursor).toBe("cursor-2")
    end)

    unitwind:test("CallToolResult prepares default MCP shape", function()
        local result = jsonrpc.CallToolResult()
        unitwind:expect(type(result)).toBe("table")
        unitwind:expect(type(result.content)).toBe("table")
        unitwind:expect(getmetatable(result.content).__jsontype).toBe("array")
        unitwind:expect(result.structuredContent).toBe(nil)
        unitwind:expect(result.isError).toBe(nil)
    end)

    unitwind:test("CallToolResult wraps single content block", function()
        local result = jsonrpc.CallToolResult({
            type = "text",
            text = "hello",
        })
        unitwind:expect(getmetatable(result.content).__jsontype).toBe("array")
        unitwind:expect(result.content[1].type).toBe("text")
        unitwind:expect(result.content[1].text).toBe("hello")
    end)

    unitwind:test("CallToolResult copies content array", function()
        local result = jsonrpc.CallToolResult({ {
            type = "text",
            text = "hello",
        } })
        unitwind:expect(getmetatable(result.content).__jsontype).toBe("array")
        unitwind:expect(result.content[1].type).toBe("text")
        unitwind:expect(result.content[1].text).toBe("hello")
    end)

    unitwind:test("CallToolResult sets structuredContent and isError", function()
        local result = jsonrpc.CallToolResult(nil, { ok = true }, false)
        unitwind:expect(result.structuredContent.ok).toBe(true)
        unitwind:expect(result.isError).toBe(false)
    end)

    unitwind:test("ListPromptsResult copies prompt array", function()
        local result = jsonrpc.ListPromptsResult({ { name = "foo" } })
        unitwind:expect(getmetatable(result.prompts).__jsontype).toBe("array")
        unitwind:expect(result.prompts[1].name).toBe("foo")
    end)

    unitwind:test("ListResourcesResult copies resource array", function()
        local result = jsonrpc.ListResourcesResult({ { name = "resource-1" } }, "cursor-3")
        unitwind:expect(getmetatable(result.resources).__jsontype).toBe("array")
        unitwind:expect(result.resources[1].name).toBe("resource-1")
        unitwind:expect(result.nextCursor).toBe("cursor-3")
    end)

    unitwind:test("ListToolsResult copies tool array", function()
        local result = jsonrpc.ListToolsResult({ { name = "tool-1" } }, "cursor-4")
        unitwind:expect(getmetatable(result.tools).__jsontype).toBe("array")
        unitwind:expect(result.tools[1].name).toBe("tool-1")
        unitwind:expect(result.nextCursor).toBe("cursor-4")
    end)

    unitwind:test("ListRootsResult copies root array", function()
        local result = jsonrpc.ListRootsResult({ { uri = "mcp://root" } })
        unitwind:expect(getmetatable(result.roots).__jsontype).toBe("array")
        unitwind:expect(result.roots[1].uri).toBe("mcp://root")
    end)

    unitwind:test("ReadResourceResult copies contents array", function()
        local result = jsonrpc.ReadResourceResult({ { uri = "mcp://resource", text = "hello" } })
        unitwind:expect(getmetatable(result.contents).__jsontype).toBe("array")
        unitwind:expect(result.contents[1].uri).toBe("mcp://resource")
        unitwind:expect(result.contents[1].text).toBe("hello")
    end)

    unitwind:test("object returns nil for array tagged table", function()
        local arr = jsonrpc.array({ 1, 2, 3 })
        local result = jsonrpc.object(arr)
        unitwind:expect(result).toBe(nil)
    end)

    unitwind:test("array with table copies content", function()
        local result = jsonrpc.array({ "a", "b" })
        if result then
            unitwind:expect(getmetatable(result).__jsontype).toBe("array")
            unitwind:expect(result[1]).toBe("a")
            unitwind:expect(result[2]).toBe("b")
        end
    end)

    unitwind:test("array returns nil for object tagged table", function()
        local obj = jsonrpc.object({ name = "foo" })
        local result = jsonrpc.array(obj)
        unitwind:expect(result).toBe(nil)
    end)

    -- ========================================================================
    -- Schema Generators
    -- ========================================================================

    unitwind:test("StringSchema creates valid schema", function()
        local schema = jsonrpc.StringSchema("Name", "Enter a name", 1, 50, "email", "default@example.com")
        unitwind:expect(schema.type).toBe("string")
        unitwind:expect(schema.title).toBe("Name")
        unitwind:expect(schema.description).toBe("Enter a name")
        unitwind:expect(schema.minLength).toBe(1)
        unitwind:expect(schema.maxLength).toBe(50)
        unitwind:expect(schema.format).toBe("email")
        unitwind:expect(schema.default).toBe("default@example.com")
    end)

    unitwind:test("StringSchema allows nil optional fields", function()
        local schema = jsonrpc.StringSchema(nil, nil, nil, nil, nil, nil)
        unitwind:expect(schema.type).toBe("string")
        unitwind:expect(schema.title).toBe(nil)
        unitwind:expect(schema.description).toBe(nil)
    end)

    unitwind:test("NumberSchema creates valid schema", function()
        local schema = jsonrpc.NumberSchema("Age", "Enter your age", 0, 150, 25)
        unitwind:expect(schema.type).toBe("number")
        unitwind:expect(schema.title).toBe("Age")
        unitwind:expect(schema.description).toBe("Enter your age")
        unitwind:expect(schema.minimum).toBe(0)
        unitwind:expect(schema.maximum).toBe(150)
        unitwind:expect(schema.default).toBe(25)
    end)

    unitwind:test("BooleanSchema creates valid schema", function()
        local schema = jsonrpc.BooleanSchema("Enabled", "Enable this option", true)
        unitwind:expect(schema.type).toBe("boolean")
        unitwind:expect(schema.title).toBe("Enabled")
        unitwind:expect(schema.description).toBe("Enable this option")
        unitwind:expect(schema.default).toBe(true)
    end)

    unitwind:test("JsonObjectSchema keeps object type and reports valid input", function()
        ---@type table
        local objectDefinition = {
            title = "Object Title",
        }
        local schema, validObjectType = jsonrpc.JsonObjectSchema(objectDefinition)
        ---@type table
        local rawSchema = schema

        unitwind:expect(validObjectType).toBe(true)
        unitwind:expect(rawSchema.type).toBe("object")
        unitwind:expect(rawSchema.title).toBe("Object Title")
    end)

    unitwind:test("JsonObjectSchema reports false when input type mismatches", function()
        ---@type table
        local objectDefinition = {
            type = "string",
            title = "Object Title",
        }
        local schema, validObjectType = jsonrpc.JsonObjectSchema(objectDefinition)
        ---@type table
        local rawSchema = schema

        unitwind:expect(validObjectType).toBe(false)
        unitwind:expect(rawSchema.type).toBe("object")
        unitwind:expect(rawSchema.title).toBe("Object Title")
    end)

    unitwind:test("JsonArraySchema keeps array type and reports valid input", function()
        ---@type table
        local arrayDefinition = {
            type = "array",
            title = "Array Title",
        }
        local schema, validArrayType = jsonrpc.JsonArraySchema(arrayDefinition)
        ---@type table
        local rawSchema = schema

        unitwind:expect(validArrayType).toBe(true)
        unitwind:expect(rawSchema.type).toBe("array")
        unitwind:expect(rawSchema.title).toBe("Array Title")
    end)

    unitwind:test("JsonArraySchema reports false when input type mismatches", function()
        ---@type table
        local arrayDefinition = {
            type = "object",
            title = "Array Title",
        }
        local schema, validArrayType = jsonrpc.JsonArraySchema(arrayDefinition)
        ---@type table
        local rawSchema = schema

        unitwind:expect(validArrayType).toBe(false)
        unitwind:expect(rawSchema.type).toBe("array")
        unitwind:expect(rawSchema.title).toBe("Array Title")
    end)

    unitwind:test("ConstTitle creates valid const-title pair", function()
        local constTitle = jsonrpc.ConstTitle("red", "Red Color")
        unitwind:expect(constTitle.const).toBe("red")
        unitwind:expect(constTitle.title).toBe("Red Color")
    end)

    unitwind:test("UntitledSingleSelectEnumSchema creates valid schema", function()
        local enum = { "option1", "option2", "option3" }
        local schema = jsonrpc.UntitledSingleSelectEnumSchema(enum, "Select", "Choose one option", "option1")
        unitwind:expect(schema.type).toBe("string")
        unitwind:expect(schema.title).toBe("Select")
        unitwind:expect(schema.description).toBe("Choose one option")
        unitwind:expect(getmetatable(schema.enum).__jsontype).toBe("array")
        unitwind:expect(schema.enum[1]).toBe("option1")
        unitwind:expect(schema.default).toBe("option1")
    end)

    unitwind:test("TitledSingleSelectEnumSchema creates valid schema", function()
        local oneOf = {
            jsonrpc.ConstTitle("red", "Red"),
            jsonrpc.ConstTitle("blue", "Blue"),
        }
        local schema = jsonrpc.TitledSingleSelectEnumSchema(oneOf, "Color", "Pick a color")
        unitwind:expect(schema.type).toBe("string")
        unitwind:expect(schema.title).toBe("Color")
        unitwind:expect(getmetatable(schema.oneOf).__jsontype).toBe("array")
        unitwind:expect(schema.oneOf[1].const).toBe("red")
    end)

    --[[
    unitwind:test("LegacyTitledEnumSchema creates valid schema", function()
        local enum = { "a", "b", "c" }
        local enumNames = { "Option A", "Option B", "Option C" }
        local schema = jsonrpc.LegacyTitledEnumSchema(enum, enumNames, "Legacy", "Old format enum")
        unitwind:expect(schema.type).toBe("string")
        unitwind:expect(schema.title).toBe("Legacy")
        unitwind:expect(getmetatable(schema.enum).__jsontype).toBe("array")
        unitwind:expect(getmetatable(schema.enumNames).__jsontype).toBe("array")
        unitwind:expect(schema.enumNames[1]).toBe("Option A")
    end)

    unitwind:test("LegacyTitledEnumSchema allows nil enumNames", function()
        local enum = { "a", "b" }
        local schema = jsonrpc.LegacyTitledEnumSchema(enum, nil, "NoNames")
        unitwind:expect(schema.enumNames).toBe(nil)
    end)
    --]]

    unitwind:test("UntitledMultiSelectEnumSchemaItems creates valid items", function()
        local enum = { "item1", "item2", "item3" }
        local items = jsonrpc.UntitledMultiSelectEnumSchemaItems(enum)
        unitwind:expect(items.type).toBe("string")
        unitwind:expect(getmetatable(items.enum).__jsontype).toBe("array")
        unitwind:expect(items.enum[1]).toBe("item1")
    end)

    unitwind:test("UntitledMultiSelectEnumSchema creates valid array schema", function()
        local enum = { "a", "b", "c" }
        local items = jsonrpc.UntitledMultiSelectEnumSchemaItems(enum)
        local schema = jsonrpc.UntitledMultiSelectEnumSchema(items, "Colors", "Select colors", 1, 3, { "a", "b" })
        unitwind:expect(schema.type).toBe("array")
        unitwind:expect(schema.title).toBe("Colors")
        unitwind:expect(schema.minItems).toBe(1)
        unitwind:expect(schema.maxItems).toBe(3)
        unitwind:expect(schema.items.type).toBe("string")
        unitwind:expect(getmetatable(schema.default).__jsontype).toBe("array")
        unitwind:expect(schema.default[1]).toBe("a")
    end)

    unitwind:test("UntitledMultiSelectEnumSchema allows nil default", function()
        local items = jsonrpc.UntitledMultiSelectEnumSchemaItems({ "a", "b" })
        local schema = jsonrpc.UntitledMultiSelectEnumSchema(items, "List", nil, nil, nil, nil)
        unitwind:expect(schema.default).toBe(nil)
    end)

    unitwind:test("TitledMultiSelectEnumSchemaItems creates valid items", function()
        local anyOf = {
            jsonrpc.ConstTitle("red", "Red"),
            jsonrpc.ConstTitle("green", "Green"),
        }
        local items = jsonrpc.TitledMultiSelectEnumSchemaItems(anyOf)
        unitwind:expect(getmetatable(items.anyOf).__jsontype).toBe("array")
        unitwind:expect(items.anyOf[1].const).toBe("red")
    end)

    unitwind:test("TitledMultiSelectEnumSchema creates valid array schema", function()
        local anyOf = {
            jsonrpc.ConstTitle("x", "X Axis"),
            jsonrpc.ConstTitle("y", "Y Axis"),
        }
        local items = jsonrpc.TitledMultiSelectEnumSchemaItems(anyOf)
        local schema = jsonrpc.TitledMultiSelectEnumSchema(items, "Axes", "Select axes", 1, 2, { "x" })
        unitwind:expect(schema.type).toBe("array")
        unitwind:expect(schema.title).toBe("Axes")
        unitwind:expect(schema.items.anyOf[1].title).toBe("X Axis")
        unitwind:expect(getmetatable(schema.default).__jsontype).toBe("array")
    end)

    unitwind:finish()
end

return this
