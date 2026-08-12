local inputvalidator = require("morrowind-mcp.core.input_validator")

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
---@return boolean
local function IsIntegerKey(value)
    return type(value) == "number" and value >= 1 and math.floor(value) == value
end

---@param value any
---@return boolean
local function IsObject(value)
    if type(value) ~= "table" then
        return false
    end

    local mt = getmetatable(value)
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

---@param errors InputValidator.Error[]
---@return InputValidator.Result
local function Result(errors)
    return {
        valid = table.size(errors) == 0,
        errors = errors,
    }
end

--- Copy request arguments so prompt execution receives a stable table rather than the decoded JSON-RPC request object.
--- Non-table values are preserved so ValidateArguments can report the original request-shape error.
---@param arguments any
---@return any
function this.NormalizeArguments(arguments)
    if arguments ~= nil and type(arguments) ~= "table" then
        return arguments
    end

    local normalizedArguments = {}
    if type(arguments) == "table" then
        for key, value in pairs(arguments) do
            normalizedArguments[key] = value
        end
    end
    return normalizedArguments
end

--- Validate the shared MCP prompts/get argument contract before a prompt-specific sink consumes values.
--- PromptArgument only declares names and requiredness, so per-prompt semantic restrictions remain in MCP.IPrompt:Validate.
---@param arguments table<string, string>?
---@param promptArguments MCP.PromptArgument[]?
---@return InputValidator.Result
function this.ValidateArguments(arguments, promptArguments)
    ---@type InputValidator.Error[]
    local errors = {}
    local actualArguments = arguments or {}
    if not IsObject(actualArguments) then
        AddError(errors, "arguments", string.format("Expected arguments object, got %s.", type(actualArguments)))
        return Result(errors)
    end

    ---@type table<string, MCP.PromptArgument>
    local definedArguments = {}
    if type(promptArguments) == "table" then
        for _, promptArgument in ipairs(promptArguments) do
            if type(promptArgument) == "table" and type(promptArgument.name) == "string" then
                definedArguments[promptArgument.name] = promptArgument
                if promptArgument.required == true and actualArguments[promptArgument.name] == nil then
                    AddError(errors, promptArgument.name, "Required argument is missing.")
                end
            end
        end
    end

    -- Keep Tool behavior: prompts without declared arguments reject all values, while declared prompts accept extensions.
    if table.size(definedArguments) == 0 then
        for key, _ in pairs(actualArguments) do
            AddError(errors, tostring(key), "Unexpected argument.")
        end
    end

    for key, value in pairs(actualArguments) do
        if type(value) ~= "string" then
            AddError(errors, tostring(key), string.format("Expected string, got %s.", type(value)))
        elseif #value > inputvalidator.defaultMaxStringLength then
            AddError(errors, tostring(key), string.format("Expected string length to be at most %d.",
                inputvalidator.defaultMaxStringLength))
        end
    end

    return Result(errors)
end

return this
