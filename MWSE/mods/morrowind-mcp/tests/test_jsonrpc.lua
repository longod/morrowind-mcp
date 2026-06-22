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

    unitwind:test("Tool generator keeps additionalProperties unset for empty inputSchema.properties", function()
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
        local result = jsonrpc.GetPromptResult({ { role = "user", content = { type = "text", text = "hi" } } }, "prompt-desc")
        unitwind:expect(getmetatable(result.messages).__jsontype).toBe("array")
        unitwind:expect(result.messages[1].role).toBe("user")
        unitwind:expect(result.description).toBe("prompt-desc")
    end)

    unitwind:test("ListResourceTemplatesResult accepts nextCursor", function()
        local result = jsonrpc.ListResourceTemplatesResult({ { name = "template-1", uriTemplate = "mcp://foo" } }, "cursor-2")
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

    unitwind:finish()
end

return this
