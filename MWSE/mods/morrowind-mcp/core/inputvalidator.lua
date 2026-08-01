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

---@param errors InputValidator.Error[]
---@return InputValidator.Result
local function Result(errors)
    return {
        valid = table.size(errors) == 0,
        errors = errors,
    }
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
