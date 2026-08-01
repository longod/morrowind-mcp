local inputvalidator = require("morrowind-mcp.core.inputvalidator")

local this = {}

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
    if not property.maxLength and inputvalidator.defaultMaxStringLength and #value > inputvalidator.defaultMaxStringLength then
        AddError(errors, path, string.format("Expected string length to be at most %d.", inputvalidator.defaultMaxStringLength))
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

--- Validate Tool arguments against the Tool inputSchema before tool-specific sinks consume them.
---@param arguments MCP.AnyMap?
---@param inputSchema MCP.InputSchema
---@return InputValidator.Result
function this.ValidateArguments(arguments, inputSchema)
    ---@type InputValidator.Error[]
    local errors = {}

    if not inputSchema then
        AddError(errors, "$", "inputSchema is required.")
        return Result(errors)
    end
    if inputSchema.type ~= "object" then
        AddError(errors, "$", "Expected inputSchema.type to be object.")
        return Result(errors)
    end

    local actualArguments = arguments or {}
    if not IsObject(actualArguments) then
        AddError(errors, "$", string.format("Expected arguments object, got %s.", TypeName(actualArguments)))
        return Result(errors)
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
            normalizedArguments[key] = CopyDefaultValue(property.default)
        end
    end
    return normalizedArguments
end

return this
