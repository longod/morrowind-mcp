local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")

local maxLanguageTagLength = 12

--- Parse a language tag without regex so the accepted BCP 47 subset remains explicit and bounded.
---@param value string
---@return boolean
local function IsAsciiLetters(value)
    local index = 1
    while index <= #value do
        local byte = string.byte(value, index)
        local isLetter =
            (byte >= string.byte("A") and byte <= string.byte("Z")) or
            (byte >= string.byte("a") and byte <= string.byte("z"))
        if not isLetter then
            return false
        end
        index = index + 1
    end
    return true
end

---@param value string
---@return boolean
local function IsAsciiDigits(value)
    local index = 1
    while index <= #value do
        local byte = string.byte(value, index)
        if byte < string.byte("0") or byte > string.byte("9") then
            return false
        end
        index = index + 1
    end
    return true
end

--- Accept only language[-script][-region], which is sufficient for translation targets and cannot carry free-form instructions.
---@param value string
---@return boolean
local function IsLanguageTag(value)
    if value == "" or #value > maxLanguageTagLength then
        return false
    end

    local subtags = {}
    local segmentStart = 1
    while segmentStart <= #value do
        local separatorIndex = string.find(value, "-", segmentStart, true)
        local segmentEnd = separatorIndex and separatorIndex - 1 or #value
        local subtag = string.sub(value, segmentStart, segmentEnd)
        if subtag == "" then
            return false
        end
        table.insert(subtags, subtag)
        if not separatorIndex then
            break
        end
        segmentStart = separatorIndex + 1
    end

    local subtagCount = table.size(subtags)
    local primaryLanguage = subtags[1]
    if #primaryLanguage < 2 or #primaryLanguage > 3 or not IsAsciiLetters(primaryLanguage) then
        return false
    end

    local nextIndex = 2
    local script = subtags[nextIndex]
    if script and #script == 4 and IsAsciiLetters(script) then
        nextIndex = nextIndex + 1
    end

    local region = subtags[nextIndex]
    if region and ((#region == 2 and IsAsciiLetters(region)) or (#region == 3 and IsAsciiDigits(region))) then
        nextIndex = nextIndex + 1
    end

    return nextIndex > subtagCount
end

---@return string? language
---@return string? region
---@return string? codepage
local function GetLocale()
    local original = os.setlocale(nil, "ctype") or "C"
    local success = os.setlocale("", "ctype")
    local locale = nil
    if success then
        locale = os.setlocale(nil, "ctype")
    end
    os.setlocale(original, "ctype")

    if not locale or locale == "C" or locale == "" then
        return nil
    end

    local locale_code = string.split(locale, ".")
    local codepage = locale_code[2]
    local lang_region = string.split(locale_code[1], "_")
    local lang = lang_region[1]
    local region = lang_region[2]

    return lang, region, codepage
end

---@class MCP.Prompts.Translate : MCP.IPrompt
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Prompts.Translate
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Prompts.Translate
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "translate" })

    instance.definition = jsonrpc.Prompt({
        name = "translate",
        description = "Translate it!",
        arguments =  {
            jsonrpc.PromptArgument(
                "language",
                "Language",
                "BCP 47 language tag for translation, such as en, ja, en-US, or zh-Hant-TW. If omitted, the system locale is used.",
                false
            ),
        },
    })

    -- target?
    -- other specific language. or auto detect.
    return instance
end

function this:CanExecute(params)
    return true
end

---@param params MCP.GetPromptRequestParams
---@return InputValidator.Result
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    local arguments = params.arguments or {}
    local language = arguments["language"]
    if language ~= nil and not IsLanguageTag(language) then
        -- The language tag is interpolated into an instruction, so accept only a bounded structured identifier.
        table.insert(result.errors, {
            path = "language",
            message = "Expected a BCP 47 language tag with optional script and region subtags.",
        })
        result.valid = false
    end
    return result
end

---@param arguments table<string, string>
---@param context table?
---@return MCP.GetPromptResult
function this:Execute(arguments, context)
    local language = arguments["language"]
    if not language then
        local lang, _, _ = GetLocale()
        if not lang then
            lang = tes3.getLanguage()
        end
        language = lang or "English" -- or config, first priority?
    end

    return jsonrpc.GetPromptResult(
        {
            jsonrpc.PromptMessage(
                mcp.role.user,
                jsonrpc.TextContent(
                string.format("In this session, you MUST speak and translate contents using `%s`.", language))
            ),
            -- add assistant message?
        },
        nil -- How to write this description?
    )
end

return this
