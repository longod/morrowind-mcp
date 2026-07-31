local base = require("morrowind-mcp.core.iprompt")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")


---@return string? launguage
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
                "Launguage",
                "The name of any language you want to use. If not specified, the system locale will be used.",
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

function this:Execute(params, context)
    -- TODO need arguments validatior.

    local arguments = params.arguments or {}
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
