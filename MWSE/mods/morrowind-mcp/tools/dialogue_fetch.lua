local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local dialogue = require("morrowind-mcp.util.dialogue")
local mcpui = require("morrowind-mcp.util.mcpui")
local summary = require("morrowind-mcp.tes3.object_summary")
local ui = require("morrowind-mcp.tes3.ui")
local dialogueMenu = require("morrowind-mcp.util.dialogue_menu")

---@class MCP.Tools.DialogueFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.DialogueFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.DialogueFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "dialogue_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "dialogue-fetch",
        description =
        "Fetch the current dialogue menu conversation, notifications, choices, topics, services, persuasion action, and unclassified actions. This includes only text displayed in the current conversation; use memory resources for past conversations. Unclassified actions cannot be selected by mw-dialogue-action.",
        inputSchema = jsonrpc.InputSchema(),
        outputSchema = jsonrpc.OutputSchema({
            actor = jsonrpc.JsonObjectSchema(),
            dialogues = jsonrpc.JsonArraySchema(),
            notifications = jsonrpc.JsonArraySchema(),
            choices = jsonrpc.JsonArraySchema(),
            topics = jsonrpc.JsonArraySchema(),
            services = jsonrpc.JsonArraySchema(),
            persuasion = jsonrpc.JsonArraySchema(),
            unknown_actions = jsonrpc.JsonArraySchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Available only in an active loaded game while MenuDialog is open, visible, and enabled."
end

--- Build a round-trippable identity for a currently visible selectable dialogue element.
---@param element tes3uiElement
---@param kind string
---@param index number?
---@return MCP.AnyMap?
local function SerializeAction(element, kind, index)
    local text = ui.ExtractVisibleText(element)
    local menuPath = ui.FindPath(tes3.worldController.menuController.mainRoot, element)
    if not text or not menuPath then
        return nil
    end
    local result = jsonrpc.object({
        kind = kind,
        text = text,
        menu_path = menuPath,
        name = element.name,
    })
    if index then
        result.index = index
    end
    return result
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
                    name = "mw-menu-fetch",
                    relationship = "reports the current MenuDialog UI state.",
                },
            },
        })
    end
    return true
end

--- Fetch only the live contents of MenuDialog. Historical dialogue remains owned by memory resources.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local menu = dialogueMenu.GetDialogueMenu()
    if not menu then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The dialogue menu is no longer open."), nil, true)
    end

    local dialogues = jsonrpc.array()
    local notifications = jsonrpc.array()
    local choices = jsonrpc.array()
    local topics = jsonrpc.array()
    local services = jsonrpc.array()
    local persuasion = jsonrpc.array()
    local unknownActions = jsonrpc.array()
    local choiceIndex = 0

    --- Walk the menu in display order. Hyperlink children are intentionally not re-read because their parent owns the complete text.
    ---@param element tes3uiElement
    ---@param underTopicsPane boolean
    local function Visit(element, underTopicsPane)
        if not element or not element:isValid() or not element.visible then
            return
        end
        local inTopicsPane = underTopicsPane or element.name == "MenuDialog_topics_pane"
        if element.name == "MenuDialog_hyper" then
            local text = dialogue.NormalizeDialogueText(element.text)
            if text ~= "" then
                table.insert(dialogues, jsonrpc.object({ kind = "response", text = text }))
            end
        elseif element.name == "MenuDialog_header" then
            local text = dialogue.NormalizeDialogueText(element.text)
            if text ~= "" then
                table.insert(dialogues, jsonrpc.object({ kind = "header", text = text }))
            end
        elseif element.name == "MenuDialog_notify" then
            local rawText = element.text
            local text = dialogue.NormalizeDialogueText(rawText)
            if text ~= "" and not mcpui.isOwnNotify(rawText) then
                table.insert(notifications, jsonrpc.object({ text = text }))
            end
        elseif element.name == "MenuDialog_answer_block" and dialogueMenu.IsClickableTextSelect(element) then
            choiceIndex = choiceIndex + 1
            local entry = SerializeAction(element, "choice", choiceIndex)
            if entry then
                table.insert(choices, entry)
            end
        elseif inTopicsPane and dialogueMenu.IsClickableTextSelect(element) then
            local kind = dialogueMenu.GetSideActionKind(element)
            local entry = SerializeAction(element, kind)
            if entry then
                local collection = kind == "topic" and topics or kind == "service" and services or kind == "persuasion" and persuasion or unknownActions
                table.insert(collection, entry)
            end
        end

        for _, child in ipairs(element.children or {}) do
            Visit(child, inTopicsPane)
        end
    end
    Visit(menu, false)

    local serviceActor = tes3ui.getServiceActor()
    local reference = serviceActor and (serviceActor.reference or serviceActor) or nil
    local serializer = summary.new({ detailLevel = summary.level.minimal, origin = tes3.player and tes3.player.position or nil })
    local actor = reference and serializer:tes3reference(reference) or nil
    if not actor then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The dialogue actor could not be resolved."), nil, true)
    end

    return jsonrpc.CallToolResult(nil, jsonrpc.object({
        actor = actor,
        dialogues = dialogues,
        notifications = notifications,
        choices = choices,
        topics = topics,
        services = services,
        persuasion = persuasion,
        unknown_actions = unknownActions,
    }))
end

return this

