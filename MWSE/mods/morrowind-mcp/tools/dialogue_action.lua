local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local ui = require("morrowind-mcp.tes3.ui")
local dialogueMenu = require("morrowind-mcp.util.dialogue_menu")

---@class MCP.Tools.DialogueAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DialogueAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DialogueAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue_action" })
    instance.definition = jsonrpc.Tool({
        name = "dialogue-action",
        description = "Select a topic, choice, service, or persuasion action returned by mw-dialogue-fetch, or close MenuDialog with the bye shortcut.",
        inputSchema = jsonrpc.InputSchema({
            kind = jsonrpc.UntitledSingleSelectEnumSchema(
                { "topic", "choice", "service", "persuasion", "bye" },
                "Kind",
                "Kind returned by mw-dialogue-fetch, or bye to close MenuDialog."
            ),
            text = jsonrpc.StringSchema("Text", "Exact displayed text returned by mw-dialogue-fetch. Not used by bye.", 1, 1024),
            menu_path = jsonrpc.StringSchema(
                "Menu Path",
                "Optional exact path returned by mw-dialogue-fetch. It detects a changed or ambiguous dialogue menu.",
                1,
                1024
            ),
        }, jsonrpc.array({ "kind" })),
        outputSchema = jsonrpc.OutputSchema({
            selected = jsonrpc.JsonObjectSchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Available only in an active loaded game while MenuDialog is open, visible, and enabled."
end

--- Check whether a live target still belongs to MenuDialog and matches the requested semantic selector.
---@param target tes3uiElement?
---@param menu tes3uiElement
---@param arguments MCP.AnyMap
---@return boolean
local function MatchesSelection(target, menu, arguments)
    if not target or not target:isValid() or target:getTopLevelMenu() ~= menu or target.disabled or not target.visible then
        return false
    end
    if not dialogueMenu.SupportsMouseClick(target) then
        return false
    end
    local kind = arguments["kind"]
    if kind == "bye" then
        return target.name == "MenuDialog_button_bye"
            and (arguments["text"] == nil or ui.ExtractVisibleText(target) == arguments["text"])
    elseif kind == "choice" then
        if target.name ~= "MenuDialog_answer_block" or target.type ~= "textSelect" then
            return false
        end
    elseif target.type ~= "textSelect" or dialogueMenu.GetSideActionKind(target) ~= kind then
        return false
    end
    return ui.ExtractVisibleText(target) == arguments["text"]
end

function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end
    ok, reason = availability.PausedInMenuMode()
    if not ok then
        return false, reason
    end
    if not dialogueMenu.GetDialogueMenu() then
        return false, availability.Unavailable(availability.reason.menu_unavailable, {
            unavailableBecause = "MenuDialog is not visible, valid, and enabled in menu mode.",
            availableWhen = "MenuDialog is visible, valid, and enabled in menu mode.",
            relatedTools = {
                {
                    name = "mw-dialogue-fetch",
                    relationship = "reports the current dialogue action identity.",
                },
            },
        })
    end
    return true
end

--- Validate the optional raw UI path before it is resolved against the live dialogue tree.
---@param params MCP.CallToolRequestParams
---@return InputValidator.Result
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end
    local menuPath = params.arguments and params.arguments["menu_path"] or nil
    local kind = params.arguments and params.arguments["kind"] or nil
    local text = params.arguments and params.arguments["text"] or nil
    if kind ~= "bye" and text == nil then
        table.insert(result.errors, { path = "text", message = "text is required unless kind is bye." })
        result.valid = false
    end
    if menuPath then
        local validPath, pathError = ui.ValidatePath(menuPath)
        if not validPath then
            table.insert(result.errors, { path = "menu_path", message = pathError })
            result.valid = false
        end
    end
    return result
end

--- Select one current dialogue action, rejecting changed or ambiguous live menu entries.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local menu = dialogueMenu.GetDialogueMenu()
    if not menu then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The dialogue menu is no longer open."), nil, true)
    end

    local root = tes3.worldController.menuController.mainRoot
    local requestedPath = arguments["menu_path"]
    ---@type tes3uiElement[]
    local matches = {}
    if requestedPath then
        local target = ui.ResolvePath(root, requestedPath)
        if MatchesSelection(target, menu, arguments) then
            table.insert(matches, target)
        else
            return jsonrpc.CallToolResult(jsonrpc.TextContent("The dialogue action no longer matches the supplied menu_path."), nil, true)
        end
    else
        --- Search only currently visible UI so a label match cannot select a stale hidden row.
        ---@param element tes3uiElement
        local function Visit(element)
            if not element or not element:isValid() or not element.visible then
                return
            end
            if MatchesSelection(element, menu, arguments) then
                table.insert(matches, element)
            end
            for _, child in ipairs(element.children or {}) do
                Visit(child)
            end
        end
        Visit(menu)
    end

    if table.size(matches) == 0 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("No matching dialogue action was found."), nil, true)
    end
    if table.size(matches) > 1 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Multiple dialogue actions matched. Specify menu_path."), nil, true)
    end

    local selected = matches[1]
    if not selected then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The matching dialogue action is no longer available."), nil, true)
    end
    local selectedPath = ui.FindPath(root, selected)
    if not selectedPath then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The matching dialogue action no longer has a menu path."), nil, true)
    end
    selected:triggerEvent(tes3.uiEvent.mouseClick)
    return jsonrpc.CallToolResult(nil, jsonrpc.object({
        selected = jsonrpc.object({
            kind = arguments["kind"],
            text = arguments["text"] or ui.ExtractVisibleText(selected),
            menu_path = selectedPath,
            operation = "ui_click",
            requires_follow_up = true,
        }),
    }))
end

return this
