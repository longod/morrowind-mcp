local this = {}

-- This module only validates facts that are local to a schema or an input string. Runtime checks stay in tools.
-- Defensive defaults apply only when a schema or caller does not provide a tighter limit.
this.defaultMaxStringLength = 8192
this.defaultMaxFileNameLength = 255
-- These sets are intentionally public so tool-specific rules can evolve as MWSE UI behavior is verified.
this.reservedUiTextCharacters = { "|", "@", "#", "^" }
this.reservedFileNameCharacters = { "\\", "/", ":", "*", "?", "\"", "<", ">", "|" }

--- Error paths are display locations, not schema objects. Use argument names such as "file_name" when known;
--- use "$" for errors that belong to the whole input value or when no argument name is available.
---@class InputValidator.Error
---@field path string
---@field message string

---@class InputValidator.Result
---@field valid boolean
---@field errors InputValidator.Error[]

---@class InputValidator.UiTextOptions
---@field allowNewlines boolean?
---@field reservedCharacters string[]?
---@field maxLength integer?

---@class InputValidator.FileNameOptions
---@field maxLength integer?
---@field reservedCharacters string[]?

---@param errors InputValidator.Error[]
---@param path string
---@param message string
local function AddError(errors, path, message)
    table.insert(errors, {
        path = path,
        message = message,
    })
end

---@param value any
---@return string
local function TypeName(value)
    return type(value)
end

---@param value string
---@return string
local function EscapeControlCharacters(value)
    -- Validation errors are echoed to MCP responses and logs, so keep control bytes visible and non-structural.
    local escaped = {}
    local index = 1
    while index <= #value do
        local byte = string.byte(value, index)
        if byte == string.byte("\r") then
            table.insert(escaped, "\\r")
        elseif byte == string.byte("\n") then
            table.insert(escaped, "\\n")
        elseif byte == string.byte("\t") then
            table.insert(escaped, "\\t")
        elseif byte < 32 or byte == 127 then
            table.insert(escaped, string.format("\\x%02X", byte))
        else
            table.insert(escaped, string.char(byte))
        end
        index = index + 1
    end
    return table.concat(escaped)
end

---@param value any
---@return boolean
local function IsIntegerKey(value)
    return type(value) == "number" and value >= 1 and math.floor(value) == value
end

---@param value any
---@return boolean
local function IsArray(value)
    if type(value) ~= "table" then
        return false
    end

    local mt = getmetatable(value)
    if mt and mt.__jsontype == "array" then
        return true
    end
    if mt and mt.__jsontype == "object" then
        return false
    end

    local count = 0
    local maxIndex = 0
    for key, _ in pairs(value) do
        if not IsIntegerKey(key) then
            return false
        end
        count = count + 1
        if key > maxIndex then
            maxIndex = key
        end
    end
    return count == maxIndex
end

---@param value any
---@return boolean
local function IsObject(value)
    if type(value) ~= "table" then
        return false
    end

    local mt = getmetatable(value)
    if mt and mt.__jsontype == "object" then
        return true
    end
    if mt and mt.__jsontype == "array" then
        return false
    end

    for key, _ in pairs(value) do
        if IsIntegerKey(key) then
            return false
        end
    end
    return true
end

---@param values table?
---@param value any
---@return boolean
local function Contains(values, value)
    if type(values) ~= "table" then
        return false
    end
    for _, candidate in ipairs(values) do
        if candidate == value then
            return true
        end
    end
    return false
end

---@param oneOf table?
---@param value any
---@return boolean
local function ContainsConst(oneOf, value)
    if type(oneOf) ~= "table" then
        return false
    end
    for _, candidate in ipairs(oneOf) do
        if type(candidate) == "table" and candidate.const == value then
            return true
        end
    end
    return false
end

---@param property MCP.JsonSchemaProperty
---@param value any
---@return boolean
local function IsEnumValue(property, value)
    if property.enum then
        return Contains(property.enum, value)
    end
    if property.oneOf then
        return ContainsConst(property.oneOf, value)
    end
    return true
end

---@param items MCP.UntitledMultiSelectEnumSchemaItems|MCP.TitledMultiSelectEnumSchemaItems?
---@param value any
---@return boolean
local function IsArrayItemValid(items, value)
    if not items then
        return true
    end
    if items.type and type(value) ~= items.type then
        return false
    end
    if items.enum then
        return Contains(items.enum, value)
    end
    if items.anyOf then
        return ContainsConst(items.anyOf, value)
    end
    return true
end

--- minItems/maxItems currently require an extra pass over large arrays.
--- This stays separate so the count matches ipairs-based item validation; merge the passes if large arrays become common.
---@param value any
---@return integer
local function ArraySize(value)
    local count = 0
    for _, _ in ipairs(value) do
        count = count + 1
    end
    return count
end

---@param errors InputValidator.Error[]
---@return InputValidator.Result
local function Result(errors)
    return {
        valid = table.size(errors) == 0,
        errors = errors,
    }
end

--- Copy schema defaults without relying on MWSE-specific table helpers, keeping this core module portable.
--- Table defaults are deep-copied so a tool cannot mutate the schema's reusable default value.
---@param value any
---@param seen table<any, any>?
---@return any
local function CopyDefaultValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[CopyDefaultValue(key, seen)] = CopyDefaultValue(item, seen)
    end

    local mt = getmetatable(value)
    if mt then
        -- Preserve jsonrpc.array/jsonrpc.object tags and any other schema default table identity metadata.
        setmetatable(copy, mt)
    end
    return copy
end

---@param ch integer
---@return boolean
local function IsHexByte(ch)
    return
        (ch >= string.byte("0") and ch <= string.byte("9")) or
        (ch >= string.byte("A") and ch <= string.byte("F")) or
        (ch >= string.byte("a") and ch <= string.byte("f"))
end

---@param hexPair string
---@return integer?
local function HexPairToByte(hexPair)
    local high = tonumber(string.sub(hexPair, 1, 1), 16)
    local low = tonumber(string.sub(hexPair, 2, 2), 16)
    if not high or not low then
        return nil
    end
    return high * 16 + low
end

---@param path string
---@return string?
local function PercentDecodePath(path)
    -- URI validation must inspect the decoded logical path so encoded traversal attempts are rejected.
    local result = {}
    local len = string.len(path)
    local i = 1
    while i <= len do
        local ch = string.byte(path, i)
        if ch == string.byte("%") then
            if i + 2 > len then
                return nil
            end
            local h1 = string.byte(path, i + 1)
            local h2 = string.byte(path, i + 2)
            if not IsHexByte(h1) or not IsHexByte(h2) then
                return nil
            end
            local byteValue = HexPairToByte(string.sub(path, i + 1, i + 2))
            if not byteValue then
                return nil
            end
            table.insert(result, string.char(byteValue))
            i = i + 3
        else
            table.insert(result, string.char(ch))
            i = i + 1
        end
    end
    return table.concat(result)
end

---@param value string
---@param characters string[]
---@return string?
local function FindReservedCharacter(value, characters)
    for _, character in ipairs(characters) do
        if character ~= "" and string.find(value, character, 1, true) then
            return character
        end
    end
    return nil
end

---@param value string
---@return boolean
local function ContainsControlCharacter(value)
    local index = 1
    while index <= #value do
        local byte = string.byte(value, index)
        if byte < 32 or byte == 127 then
            return true
        end
        index = index + 1
    end
    return false
end

---@param value string
---@return boolean
local function ContainsNewline(value)
    return string.find(value, "\r", 1, true) ~= nil or string.find(value, "\n", 1, true) ~= nil
end

---@param resourcePath string
---@return boolean
local function IsSafeResourcePath(resourcePath)
    -- Resource paths are logical paths below resourceRootDir, never filesystem paths or URI fragments.
    if resourcePath == "" or string.startswith(resourcePath, "/") then
        return false
    end

    if string.find(resourcePath, "\\", 1, true) or string.find(resourcePath, ":", 1, true) then
        return false
    end

    local pathLen = string.len(resourcePath)
    local segmentStart = 1
    while segmentStart <= pathLen + 1 do
        local separatorIndex = string.find(resourcePath, "/", segmentStart, true)
        local segmentEnd = separatorIndex and (separatorIndex - 1) or pathLen
        local segment = string.sub(resourcePath, segmentStart, segmentEnd)
        if segment == "" or segment == "." or segment == ".." then
            return false
        end
        if not separatorIndex then
            break
        end
        segmentStart = separatorIndex + 1
    end

    return true
end

---@param value any
---@param path string?
---@param options InputValidator.UiTextOptions|string[]?
---@return InputValidator.Result
function this.ValidateUiText(value, path, options)
    -- JSON schema can describe string length, but it cannot express MWSE UI markup or input-sink semantics.
    ---@type InputValidator.Error[]
    local errors = {}
    local fieldPath = path or "$"
    if type(value) ~= "string" then
        AddError(errors, fieldPath, string.format("Expected string, got %s.", TypeName(value)))
        return Result(errors)
    end

    -- UI text has both single-line and multi-line sinks; callers choose newline policy explicitly.
    local allowNewlines = false
    local maxLength = this.defaultMaxStringLength
    local reservedCharacters = this.reservedUiTextCharacters
    if type(options) == "table" then
        if options.reservedCharacters then
            reservedCharacters = options.reservedCharacters
        elseif options[1] ~= nil then
            reservedCharacters = options
        end
        allowNewlines = options.allowNewlines == true
        if options.maxLength then
            maxLength = options.maxLength
        end
    end

    if maxLength and #value > maxLength then
        AddError(errors, fieldPath, string.format("Expected string length to be at most %d.", maxLength))
    end
    if not allowNewlines and ContainsNewline(value) then
        AddError(errors, fieldPath, "Expected single-line UI text.")
    end
    local reservedCharacter = FindReservedCharacter(value, reservedCharacters or this.reservedUiTextCharacters)
    if reservedCharacter then
        AddError(errors, fieldPath, string.format("Reserved UI text character is not allowed: %s.", reservedCharacter))
    end
    return Result(errors)
end

---@param value any
---@param path string?
---@param reservedCharacters string[]?
---@return InputValidator.Result
function this.ValidateSingleLineUiText(value, path, reservedCharacters)
    -- Single-line UI sinks reject newlines before the value reaches tes3uiElement.text.
    return this.ValidateUiText(value, path, {
        allowNewlines = false,
        reservedCharacters = reservedCharacters,
    })
end

---@param value any
---@param path string?
---@param reservedCharacters string[]?
---@return InputValidator.Result
function this.ValidateMultiLineUiText(value, path, reservedCharacters)
    -- Multi-line sinks still keep the same reserved-character checks unless the caller overrides them.
    return this.ValidateUiText(value, path, {
        allowNewlines = true,
        reservedCharacters = reservedCharacters,
    })
end

---@param fileName any
---@param path string?
---@param options InputValidator.FileNameOptions?
---@return InputValidator.Result
function this.ValidateFileName(fileName, path, options)
    -- This is for caller-provided names before an extension or directory is appended.
    ---@type InputValidator.Error[]
    local errors = {}
    local fieldPath = path or "$"
    if type(fileName) ~= "string" then
        AddError(errors, fieldPath, string.format("Expected file name string, got %s.", TypeName(fileName)))
        return Result(errors)
    end

    -- File names are validated as a single path segment; path traversal belongs to resource path validation.
    local maxLength = this.defaultMaxFileNameLength
    local reservedCharacters = this.reservedFileNameCharacters
    if type(options) == "table" then
        maxLength = options.maxLength or maxLength
        reservedCharacters = options.reservedCharacters or reservedCharacters
    end

    if fileName == "" then
        AddError(errors, fieldPath, "Expected non-empty file name.")
    end
    if maxLength and #fileName > maxLength then
        AddError(errors, fieldPath, string.format("Expected file name length to be at most %d.", maxLength))
    end
    local reservedCharacter = FindReservedCharacter(fileName, reservedCharacters)
    if reservedCharacter then
        AddError(errors, fieldPath, string.format("Reserved file name character is not allowed: %s.", reservedCharacter))
    end
    if ContainsControlCharacter(fileName) then
        AddError(errors, fieldPath, "Control characters are not allowed in file names.")
    end
    if string.endswith(fileName, ".") or string.endswith(fileName, " ") then
        AddError(errors, fieldPath, "File name must not end with a dot or space.")
    end

    local firstDot = string.find(fileName, ".", 1, true)
    local deviceName = firstDot and string.sub(fileName, 1, firstDot - 1) or fileName
    deviceName = string.upper(deviceName)
    -- Windows reserves these device names even when an extension is present.
    if deviceName == "CON" or deviceName == "PRN" or deviceName == "AUX" or deviceName == "NUL" or
        string.match(deviceName, "^COM[1-9]$") or string.match(deviceName, "^LPT[1-9]$") then
        AddError(errors, fieldPath, "Reserved Windows device file name is not allowed.")
    end

    return Result(errors)
end

---@param resourcePath any
---@param path string?
---@return InputValidator.Result
function this.ValidateResourcePath(resourcePath, path)
    -- Resource paths are safe only after they are proven relative to the configured resource root.
    ---@type InputValidator.Error[]
    local errors = {}
    local fieldPath = path or "$"
    if type(resourcePath) ~= "string" then
        AddError(errors, fieldPath, string.format("Expected resource path string, got %s.", TypeName(resourcePath)))
        return Result(errors)
    end
    if not IsSafeResourcePath(resourcePath) then
        AddError(errors, fieldPath, "Expected safe resource-root-relative path.")
    end
    return Result(errors)
end

---@param uri any
---@param uriScheme string
---@param path string?
---@return InputValidator.Result
function this.ValidateResourceUri(uri, uriScheme, path)
    -- Validate URI ownership first, then validate the decoded path with the same resource-root rules.
    ---@type InputValidator.Error[]
    local errors = {}
    local fieldPath = path or "$"
    if type(uri) ~= "string" then
        AddError(errors, fieldPath, string.format("Expected resource URI string, got %s.", TypeName(uri)))
        return Result(errors)
    end
    if type(uriScheme) ~= "string" or uriScheme == "" then
        AddError(errors, fieldPath, "Resource URI scheme is required.")
        return Result(errors)
    end
    if not string.startswith(uri, uriScheme) then
        AddError(errors, fieldPath, "Expected resource URI to use the configured scheme.")
        return Result(errors)
    end

    local encodedPath = string.sub(uri, string.len(uriScheme) + 1)
    local resourcePath = PercentDecodePath(encodedPath)
    if not resourcePath then
        AddError(errors, fieldPath, "Expected resource URI path to use valid percent encoding.")
        return Result(errors)
    end

    local resourcePathResult = this.ValidateResourcePath(resourcePath, fieldPath)
    for _, validationError in ipairs(resourcePathResult.errors) do
        table.insert(errors, validationError)
    end
    return Result(errors)
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
---@param property MCP.JsonSchemaProperty
local function ValidateString(errors, path, value, property)
    if type(value) ~= "string" then
        AddError(errors, path, string.format("Expected string, got %s.", TypeName(value)))
        return
    end
    if property.minLength and #value < property.minLength then
        AddError(errors, path, string.format("Expected string length to be at least %d.", property.minLength))
    end
    if property.maxLength and #value > property.maxLength then
        AddError(errors, path, string.format("Expected string length to be at most %d.", property.maxLength))
    end
    -- A missing maxLength should not make unbounded strings acceptable for logs, JSON, or game sinks.
    if not property.maxLength and this.defaultMaxStringLength and #value > this.defaultMaxStringLength then
        AddError(errors, path, string.format("Expected string length to be at most %d.", this.defaultMaxStringLength))
    end
    if not IsEnumValue(property, value) then
        AddError(errors, path, "Expected value to be one of the schema enum values.")
    end
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
---@param property MCP.JsonSchemaProperty
local function ValidateNumber(errors, path, value, property)
    if type(value) ~= "number" then
        AddError(errors, path, string.format("Expected number, got %s.", TypeName(value)))
        return
    end
    if property.minimum and value < property.minimum then
        AddError(errors, path, string.format("Expected number to be at least %s.", tostring(property.minimum)))
    end
    if property.maximum and value > property.maximum then
        AddError(errors, path, string.format("Expected number to be at most %s.", tostring(property.maximum)))
    end
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
local function ValidateBoolean(errors, path, value)
    if type(value) ~= "boolean" then
        AddError(errors, path, string.format("Expected boolean, got %s.", TypeName(value)))
    end
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
---@param property MCP.JsonSchemaProperty
local function ValidateArray(errors, path, value, property)
    if not IsArray(value) then
        AddError(errors, path, string.format("Expected array, got %s.", TypeName(value)))
        return
    end

    local size = ArraySize(value)
    if property.minItems and size < property.minItems then
        AddError(errors, path, string.format("Expected array to contain at least %d item(s).", property.minItems))
    end
    if property.maxItems and size > property.maxItems then
        AddError(errors, path, string.format("Expected array to contain at most %d item(s).", property.maxItems))
    end

    for index, item in ipairs(value) do
        if not IsArrayItemValid(property.items, item) then
            AddError(errors, string.format("%s[%d]", path, index), "Expected item to match the schema item definition.")
        end
    end
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
local function ValidateObject(errors, path, value)
    if not IsObject(value) then
        AddError(errors, path, string.format("Expected object, got %s.", TypeName(value)))
    end
end

---@param errors InputValidator.Error[]
---@param path string
---@param value any
---@param property MCP.JsonSchemaProperty
local function ValidateProperty(errors, path, value, property)
    if type(property) ~= "table" then
        AddError(errors, path, "Expected property schema to be an object.")
        return
    end

    if property.type == "string" then
        ValidateString(errors, path, value, property)
    elseif property.type == "number" then
        ValidateNumber(errors, path, value, property)
    elseif property.type == "boolean" then
        ValidateBoolean(errors, path, value)
    elseif property.type == "array" then
        ValidateArray(errors, path, value, property)
    elseif property.type == "object" then
        ValidateObject(errors, path, value)
    else
        AddError(errors, path, string.format("Unsupported schema type: %s.", tostring(property.type)))
    end
end

---@param properties table<string, MCP.JsonSchemaProperty>?
---@param required string[]?
---@param errors InputValidator.Error[]
local function ValidateRequired(properties, required, errors)
    if type(required) ~= "table" then
        return
    end
    for _, key in ipairs(required) do
        if not properties or not properties[key] then
            AddError(errors, key, "Required field is not defined in inputSchema.properties.")
        end
    end
end

---@param arguments MCP.AnyMap
---@param inputSchema MCP.InputSchema
---@param errors InputValidator.Error[]
local function ValidateObjectArguments(arguments, inputSchema, errors)
    local properties = inputSchema.properties
    ValidateRequired(properties, inputSchema.required, errors)

    if inputSchema.additionalProperties == false then
        for key, _ in pairs(arguments) do
            if not properties or not properties[key] then
                AddError(errors, tostring(key), "Unexpected argument.")
            end
        end
    end

    if type(inputSchema.required) == "table" then
        for _, key in ipairs(inputSchema.required) do
            if arguments[key] == nil then
                AddError(errors, key, "Required argument is missing.")
            end
        end
    end

    if type(properties) ~= "table" then
        return
    end

    for key, property in pairs(properties) do
        local value = arguments[key]
        if value ~= nil then
            ValidateProperty(errors, key, value, property)
        end
    end
end

---@param arguments MCP.AnyMap?
---@param inputSchema MCP.InputSchema
---@return InputValidator.Result
function this.ValidateArguments(arguments, inputSchema)
    -- Keep this schema-only so every tool gets the same baseline checks before tool-specific validation runs.
    ---@type InputValidator.Error[]
    local errors = {}

    if not inputSchema then
        AddError(errors, "$", "inputSchema is required.")
        return { valid = false, errors = errors }
    end
    if inputSchema.type ~= "object" then
        AddError(errors, "$", "Expected inputSchema.type to be object.")
        return { valid = false, errors = errors }
    end

    local actualArguments = arguments or {}
    if not IsObject(actualArguments) then
        AddError(errors, "$", string.format("Expected arguments object, got %s.", TypeName(actualArguments)))
        return { valid = false, errors = errors }
    end

    ValidateObjectArguments(actualArguments, inputSchema, errors)

    return Result(errors)
end

--- Apply schema defaults to a request-local argument table before validation and tool-specific checks run.
--- Non-table arguments are returned unchanged so ValidateArguments can report the original shape error.
---@param arguments MCP.AnyMap?
---@param inputSchema MCP.InputSchema
---@return MCP.AnyMap?
function this.NormalizeArguments(arguments, inputSchema)
    if arguments ~= nil and type(arguments) ~= "table" then
        return arguments
    end

    -- Build a new top-level table so normalization does not mutate the decoded JSON-RPC request object in-place.
    local normalizedArguments = {}
    if type(arguments) == "table" then
        for key, value in pairs(arguments) do
            normalizedArguments[key] = value
        end
    end

    if not inputSchema or type(inputSchema.properties) ~= "table" then
        return normalizedArguments
    end

    for key, property in pairs(inputSchema.properties) do
        if type(property) == "table" and normalizedArguments[key] == nil and property.default ~= nil then
            -- Missing and nil are equivalent in Lua tables; explicit non-nil values are never overwritten.
            normalizedArguments[key] = CopyDefaultValue(property.default)
        end
    end
    return normalizedArguments
end

---@param result InputValidator.Result
---@return string
function this.FormatErrors(result)
    -- The formatted message is client-visible TextContent and may also be written to MWSE.log.
    if result.valid then
        return ""
    end

    local messages = {}
    for _, validationError in ipairs(result.errors) do
        -- Paths can contain user-provided argument keys, so escape them before logging or returning text content.
        table.insert(messages, string.format("%s: %s", EscapeControlCharacters(validationError.path),
            EscapeControlCharacters(validationError.message)))
    end
    return table.concat(messages, "\n")
end

return this
