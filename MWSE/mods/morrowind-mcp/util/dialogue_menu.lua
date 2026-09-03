local ui = require("morrowind-mcp.tes3.ui")

--- Shared live MenuDialog helpers used by dialogue fetch and action tools.
local this = {}

--- Return the currently usable vanilla dialogue menu, if it is open and interactive.
---@return tes3uiElement? menu
function this.GetDialogueMenu()
    local menu = tes3ui.findMenu(tes3ui.registerID("MenuDialog"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return nil
    end
    return menu
end

--- Return whether an element advertises a mouse click through the shared UI action rules.
---@param element tes3uiElement
---@return boolean
function this.SupportsMouseClick(element)
    for _, action in ipairs(ui.GetActionProperties(element) or {}) do
        if action == tes3.uiEvent.mouseClick then
            return true
        end
    end
    return false
end

--- Return whether an element is a clickable text-select widget.
---@param element tes3uiElement
---@return boolean
function this.IsClickableTextSelect(element)
    return element.type == "textSelect" and this.SupportsMouseClick(element)
end

--- Classify a selectable side-panel entry without inferring semantics from its localized label.
---@param element tes3uiElement
---@return "topic"|"service"|"persuasion"|"unknown"
function this.GetSideActionKind(element)
    if element.name == "MenuDialog_a_topic" then
        return "topic"
    end
    if element.name == "MenuDialog_persuasion" then
        return "persuasion"
    end
    if type(element.name) == "string" and string.sub(element.name, 1, string.len("MenuDialog_service_")) == "MenuDialog_service_" then
        return "service"
    end
    return "unknown"
end

return this
