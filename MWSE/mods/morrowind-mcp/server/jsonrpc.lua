local this = {}

--- -32000 to -32099	Server error -- Reserved for implementation-defined server-errors.
---@enum MCP.JSONRPCErrorCode
this.error_code = {
    --- standard error code
    parse_error = { code = -32700, message = "Parse error" }, ---@type MCP.Error Invalid JSON was received by the server. An error occurred on the server while parsing the JSON text.
    invalid_request = { code = -32600, message = "Invalid Request" }, ---@type MCP.Error The JSON sent is not a valid Request object.
    method_not_found = { code = -32601, message = "Method not found" }, ---@type MCP.Error The method does not exist / is not available.
    invalid_params = { code = -32602, message = "Invalid params" }, ---@type MCP.Error Invalid method parameter(s).
    internal_error = { code = -32603, message = "Internal error" }, ---@type MCP.Error Internal JSON-RPC error.
    --- mcp
    header_mismatch = { code = -32001, message = "Header mismatch" }, ---@type MCP.Error https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http#server-validation
}

local name_prefix = ""
local title_prefix = ""
local description_prefix = ""

---@param name string?
---@param title string?
---@param description string?
function this.SetPrimitivePrefix(name, title, description)
    name_prefix = name or ""
    title_prefix = title or ""
    description_prefix = description or ""
end

---@param arg table|number?
---@return table?
function this.object(arg)
    local content = nil
    local reserved = 0
    if type(arg) == "number" then
        reserved = arg
    elseif type(arg) == "table" then
        local mt = getmetatable(arg)
        if mt and mt.__jsontype == "array" then
            return nil -- array tagged table is not valid for object
        else
            content = arg
            reserved = table.size(content)
        end
    end
    local t = table.new(0, reserved)
    setmetatable(t, { __jsontype = "object" })
    if content then
        for k, v in pairs(content) do
            t[k] = v
        end
    end
    return t
end

---@param arg table|number?
---@return table?
function this.array(arg)
    local content = nil
    local reserved = 0
    if type(arg) == "number" then
        reserved = arg
    elseif type(arg) == "table" then
        local mt = getmetatable(arg)
        if mt and mt.__jsontype == "object" then
            return nil -- object tagged table is not valid for array
        else
            content = arg
            reserved = table.size(content)
        end
    end
    local t = table.new(reserved, 0)
    setmetatable(t, { __jsontype = "array" })
    if content then
        for _, v in ipairs(content) do
            table.insert(t, v)
        end
    end
    return t
end

local dummy_object = this.object()

---@param str string
---@return MCP.JSONRPCRequest|MCP.JSONRPCNotification? json
---@return MCP.Error?
function this.request(str)
    if not str then -- allow nil
        return nil, nil
    end
    local success, result = pcall(json.decode, str)
    if not success or result == nil then
        return nil, this.error_code.parse_error
    end

    if result.jsonrpc ~= "2.0" then
        return nil, this.error_code.invalid_request
    end
    -- possible notification
    -- local t = type(result.id)
    -- if t ~= "string" and t ~= "number" then
    --     return nil, this.error_code.invalid_request
    -- end
    if type(result.method) ~= "string" then
        return nil, this.error_code.invalid_request
    end
    if result.params and type(result.params) ~= "table" then
        return nil, this.error_code.invalid_request
    end
    -- typeがあったらキャストする？
    return result
end

---@param id string|number?
---@param params table?
---@return string
function this.result(id, params)
    ---@type MCP.JSONRPCResultResponse
    local body = {
        jsonrpc = "2.0",
        id = id,
        result = params or dummy_object,
    }
    -- TODO typeの追加... deepcopyがいる？
    local encoded = json.encode(body, { indent = false })
    return encoded
end

---@param id string|number?
---@param err MCP.Error
---@param data any?
---@return string
function this.error(id, err, data)
    ---@type MCP.JSONRPCErrorResponse
    local body = {
        jsonrpc = "2.0",
        id = id,
        error = err,
    }
    if id then
        body.id = id
    end
    if data then
        body.error = table.deepcopy(body.error) -- const original table
        body.error.data = data
        -- TODO typeの追加
    end
    return json.encode(body, { indent = false })
end

--- maybe server should not use notification.
---@param method MCP.Method
---@param params table?
---@return string
function this.notification(method, params)
    ---@type MCP.JSONRPCNotification
    local body = {
        jsonrpc = "2.0",
        method = method,
    }
    if params then
        body.params = params
    end
    return json.encode(body, { indent = false })
end

-- ============================================================================
-- MCP Content Generators
-- ============================================================================

---@param text string
---@param annotations MCP.Annotations?
---@return MCP.TextContent
function this.TextContent(text, annotations)
    return {
        type = "text",
        text = text,
        annotations = annotations,
    }
end

---@param data string
---@param mimeType MCP.MimeType
---@param annotations MCP.Annotations?
---@return MCP.ImageContent
function this.ImageContent(data, mimeType, annotations)
    return {
        type = "image",
        data = data,
        mimeType = mimeType,
        annotations = annotations,
    }
end

---@param data string
---@param mimeType MCP.MimeType
---@param annotations MCP.Annotations?
---@return MCP.AudioContent
function this.AudioContent(data, mimeType, annotations)
    return {
        type = "audio",
        data = data,
        mimeType = mimeType,
        annotations = annotations,
    }
end

---@param uri string
---@param text string
---@param mimeType MCP.MimeType?
---@return MCP.TextResourceContents
function this.TextResourceContents(uri, text, mimeType)
    return {
        uri = uri,
        mimeType = mimeType,
        text = text,
    }
end

---@param uri string
---@param blob string
---@param mimeType MCP.MimeType?
---@return MCP.BlobResourceContents
function this.BlobResourceContents(uri, blob, mimeType)
    return {
        uri = uri,
        mimeType = mimeType,
        blob = blob,
    }
end

---@param resource MCP.TextResourceContents|MCP.BlobResourceContents
---@param annotations MCP.Annotations?
---@return MCP.EmbeddedResource
function this.EmbeddedResource(resource, annotations)
    return {
        type = "resource",
        resource = resource,
        annotations = annotations,
    }
end

---@param name string
---@param uri string
---@param title string?
---@param description string?
---@param mimeType MCP.MimeType?
---@param annotations MCP.Annotations?
---@param size number?
---@param icons MCP.Icon[]?
---@return MCP.ResourceLink
function this.ResourceLink(name, uri, title, description, mimeType, annotations, size, icons)
    return {
        type = "resource_link",
        icons = icons,
        name = name,
        title = title,
        uri = uri,
        description = description,
        mimeType = mimeType,
        annotations = annotations,
        size = size,
    }
end

-- ============================================================================
-- MCP Tool Generators
-- ============================================================================

---@param properties table<string, MCP.JsonSchemaProperty>?
---@param required string[]?
---@return boolean validRequired
local function ValidateProperties(properties, required)
    if required then
        if properties then
            for _, key in ipairs(required) do
                if not properties[key] then
                    return false
                end
            end
        else
            return false
        end
    end
    return true
end

---@param properties table<string, MCP.JsonSchemaProperty>?
---@param required string[]?
---@param schema string?
---@return MCP.InputSchema
---@return boolean validRequired
function this.InputSchema(properties, required, schema)
    local validRequired = ValidateProperties(properties, required)

    local inputSchema = {
        ["$schema"] = schema,
        type = "object",
        properties = properties,
        required = required,
    }
    if not inputSchema.properties then
        inputSchema.additionalProperties = false
    end
    return inputSchema, validRequired
end

---@param properties table<string, MCP.JsonSchemaProperty>?
---@param required string[]?
---@param schema string?
---@return MCP.OutputSchema
---@return boolean validRequired
function this.OutputSchema(properties, required, schema)
    local validRequired = ValidateProperties(properties, required)

    local outputSchema = {
        ["$schema"] = schema,
        type = "object",
        properties = properties,
        required = required,
    }
    return outputSchema, validRequired
end

---@param taskSupport MCP.ToolTaskSupport?
---@return MCP.ToolExecution
function this.ToolExecution(taskSupport)
    return {
        taskSupport = taskSupport,
    }
end

---@param title string?
---@param readOnlyHint boolean? default false
---@param destructiveHint boolean? default true
---@param idempotentHint boolean? default false
---@param openWorldHint boolean? default false
---@return MCP.ToolAnnotations
function this.ToolAnnotations(title, readOnlyHint, destructiveHint, idempotentHint, openWorldHint)
    return {
        title = title, -- TODO need prefix?
        readOnlyHint = readOnlyHint,
        destructiveHint = destructiveHint,
        idempotentHint = idempotentHint,
        openWorldHint = openWorldHint or false, -- specification is true, but morrowind is closed world, so default is false
    }
end

---@param tool MCP.Tool
---@return MCP.Tool
function this.Tool(tool)
    local normalizedTool = this.object(8)
    normalizedTool.icons = tool.icons
    normalizedTool.name = name_prefix .. tool.name
    normalizedTool.title = tool.title and (title_prefix .. tool.title) or nil
    normalizedTool.description = tool.description and (description_prefix .. tool.description) or nil
    normalizedTool.inputSchema = tool.inputSchema
    normalizedTool.execution = tool.execution
    normalizedTool.outputSchema = tool.outputSchema
    normalizedTool.annotations = tool.annotations
    return normalizedTool
end

-- ============================================================================
-- MCP Result Generators
-- ============================================================================

---@param values table|number?
---@param total number?
---@param hasMore boolean?
---@return MCP.CompleteResult
function this.CompleteResult(values, total, hasMore)
    return {
        completion = {
            values = this.array(values),
            total = total,
            hasMore = hasMore,
        },
    }
end

---@return MCP.ElicitResult
function this.ElicitResult()
    return {
        action = nil,
        content = nil,
    }
end

---@return MCP.InitializeResult
function this.InitializeResult()
    return {
        protocolVersion = nil,
        capabilities = this.object(),
        serverInfo = this.object(),
        instructions = nil,
    }
end

---@param task MCP.Task?
---@return MCP.CreateTaskResult
function this.CreateTaskResult(task)
    return {
        task = this.object(task),
    }
end

---@param prompts table|number?
---@param nextCursor string?
---@return MCP.ListPromptsResult
function this.ListPromptsResult(prompts, nextCursor)
    return {
        prompts = this.array(prompts),
        nextCursor = nextCursor,
    }
end

---@param resources table|number?
---@param nextCursor string?
---@return MCP.ListResourcesResult
function this.ListResourcesResult(resources, nextCursor)
    return {
        resources = this.array(resources),
        nextCursor = nextCursor,
    }
end

---@param tools table|number?
---@param nextCursor string?
---@return MCP.ListToolsResult
function this.ListToolsResult(tools, nextCursor)
    return {
        tools = this.array(tools),
        nextCursor = nextCursor,
    }
end

---@param roots table|number?
---@return MCP.ListRootsResult
function this.ListRootsResult(roots)
    return {
        roots = this.array(roots),
    }
end

---@param tasks table|number?
---@param nextCursor string?
---@return MCP.ListTasksResult
function this.ListTasksResult(tasks, nextCursor)
    return {
        tasks = this.array(tasks),
        nextCursor = nextCursor,
    }
end

---@param contents table|number?
---@return MCP.ReadResourceResult
function this.ReadResourceResult(contents)
    return {
        contents = this.array(contents),
    }
end

---@param content MCP.ContentBlock|MCP.ContentBlock[]?
---@param structuredContent MCP.AnyMap?
---@param isError boolean?
---@return MCP.CallToolResult
function this.CallToolResult(content, structuredContent, isError)
    local result_content = nil
    if type(content) == "table" then
        if content.type ~= nil then -- single content block
            result_content = this.array({ content })
        else                        -- array of content blocks
            result_content = this.array(content)
        end
    else
        result_content = this.array()
    end
    return {
        content = result_content,
        structuredContent = structuredContent,
        isError = isError,
    }
end

---@param messages table|number?
---@param description string?
---@return MCP.GetPromptResult
function this.GetPromptResult(messages, description)
    return {
        description = description,
        messages = this.array(messages),
    }
end

---@return MCP.GetTaskResult
function this.GetTaskResult()
    return {
        taskId = nil,
        status = nil,
        statusMessage = nil,
        createdAt = nil,
        lastUpdatedAt = nil,
        ttl = nil,
        pollInterval = nil,
    }
end

---@return MCP.GetTaskPayloadResult
function this.GetTaskPayloadResult()
    return {}
end

---@return MCP.CancelTaskResult
function this.CancelTaskResult()
    return {
        taskId = nil,
        status = nil,
        statusMessage = nil,
        createdAt = nil,
        lastUpdatedAt = nil,
        ttl = nil,
        pollInterval = nil,
    }
end

---@param resourceTemplates table|number?
---@param nextCursor string?
---@return MCP.ListResourceTemplatesResult
function this.ListResourceTemplatesResult(resourceTemplates, nextCursor)
    return {
        resourceTemplates = this.array(resourceTemplates),
        nextCursor = nextCursor,
    }
end

---@return MCP.CreateMessageResult
function this.CreateMessageResult()
    return {
        model = nil,
        stopReason = nil,
        role = nil,
        content = this.array(),
    }
end

-- ============================================================================
-- MCP Schema Generators
-- ============================================================================

---@param title string?
---@param description string?
---@param minLength number?
---@param maxLength number?
---@param format "uri"|"email"|"date"|"date-time"?
---@param default string?
---@return MCP.StringSchema
function this.StringSchema(title, description, minLength, maxLength, format, default)
    return {
        type = "string",
        title = title,
        description = description,
        minLength = minLength,
        maxLength = maxLength,
        format = format,
        default = default,
    }
end

---@param title string?
---@param description string?
---@param minimum number?
---@param maximum number?
---@param default number?
---@return MCP.NumberSchema
function this.NumberSchema(title, description, minimum, maximum, default)
    return {
        type = "number",
        title = title,
        description = description,
        minimum = minimum,
        maximum = maximum,
        default = default,
    }
end

---@param title string?
---@param description string?
---@param default boolean?
---@return MCP.BooleanSchema
function this.BooleanSchema(title, description, default)
    return {
        type = "boolean",
        title = title,
        description = description,
        default = default,
    }
end

---@param object table<string, MCP.JsonSchemaProperty>|number?
---@return MCP.JsonObjectSchema
---@return boolean validObjectType
function this.JsonObjectSchema(object)
    local o = this.object(object)
    if not o then
        return { type = "object" }, false
    end

    local validObjectType = true
    if o.type and o.type ~= "object" then
        validObjectType = false
    end
    o.type = "object"
    return o, validObjectType
end

---@param array table<string, any>|number?
---@return MCP.JsonArraySchema
---@return boolean validArrayType
function this.JsonArraySchema(array)
    local a = this.object(array)
    if not a then
        return { type = "array" }, false
    end

    local validArrayType = true
    if a.type and a.type ~= "array" then
        validArrayType = false
    end
    a.type = "array"
    return a, validArrayType
end

---@param const string
---@param title string
---@return MCP.ConstTitle
function this.ConstTitle(const, title)
    return {
        const = const,
        title = title,
    }
end

---@param enum string[]
---@param title string?
---@param description string?
---@param default string?
---@return MCP.UntitledSingleSelectEnumSchema
function this.UntitledSingleSelectEnumSchema(enum, title, description, default)
    return {
        type = "string",
        title = title,
        description = description,
        enum = this.array(enum),
        default = default,
    }
end

---@param oneOf MCP.ConstTitle[]
---@param title string?
---@param description string?
---@param default string?
---@return MCP.TitledSingleSelectEnumSchema
function this.TitledSingleSelectEnumSchema(oneOf, title, description, default)
    return {
        type = "string",
        title = title,
        description = description,
        oneOf = this.array(oneOf),
        default = default,
    }
end

---@deprecated
---@param enum string[]
---@param enumNames string[]?
---@param title string?
---@param description string?
---@param default string?
---@return MCP.LegacyTitledEnumSchema
function this.LegacyTitledEnumSchema(enum, enumNames, title, description, default)
    return {
        type = "string",
        title = title,
        description = description,
        enum = this.array(enum),
        enumNames = enumNames and this.array(enumNames) or nil,
        default = default,
    }
end

---@param enum string[]
---@return MCP.UntitledMultiSelectEnumSchemaItems
function this.UntitledMultiSelectEnumSchemaItems(enum)
    return {
        type = "string",
        enum = this.array(enum),
    }
end

---@param items MCP.UntitledMultiSelectEnumSchemaItems
---@param title string?
---@param description string?
---@param minItems number?
---@param maxItems number?
---@param default string[]?
---@return MCP.UntitledMultiSelectEnumSchema
function this.UntitledMultiSelectEnumSchema(items, title, description, minItems, maxItems, default)
    return {
        type = "array",
        title = title,
        description = description,
        minItems = minItems,
        maxItems = maxItems,
        items = items,
        default = default and this.array(default) or nil,
    }
end

---@param anyOf MCP.ConstTitle[]
---@return MCP.TitledMultiSelectEnumSchemaItems
function this.TitledMultiSelectEnumSchemaItems(anyOf)
    return {
        anyOf = this.array(anyOf),
    }
end

---@param items MCP.TitledMultiSelectEnumSchemaItems
---@param title string?
---@param description string?
---@param minItems number?
---@param maxItems number?
---@param default string[]?
---@return MCP.TitledMultiSelectEnumSchema
function this.TitledMultiSelectEnumSchema(items, title, description, minItems, maxItems, default)
    return {
        type = "array",
        title = title,
        description = description,
        minItems = minItems,
        maxItems = maxItems,
        items = items,
        default = default and this.array(default) or nil,
    }
end

return this
