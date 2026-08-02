local this = {}

-- Scroll widgets receive input through their arrow children rather than their widget roots.
local scrollArrowName = {
    PartScrollBar_left_arrow = true,
    PartScrollBar_right_arrow = true,
}

--- Returns MWSE's public widget type, including the concrete type of luaWidget extensions.
---@param widget tes3uiWidget
---@return string? widgetType
function this.GetType(widget)
    if not widget or not widget.element then
        return nil
    end

    local element = widget.element
    local widgetType = element.type
    if widgetType == "luaWidget" then
        local luaWidgetType = element:getLuaData("MWSE:WidgetTypeName")
        if type(luaWidgetType) == "string" and luaWidgetType ~= "" then
            return luaWidgetType
        end
    end
    return widgetType
end

--- Reports whether an element is one of the arrow children of a scroll widget.
---@param element tes3uiElement
---@return boolean
function this.IsScrollArrow(element)
    if not element or not scrollArrowName[element.name] then
        return false
    end

    local parent = element.parent
    if not parent then
        return false
    end
    if parent.type ~= "scrollBar" and parent.type ~= "scrollPane" then
        return false
    end
    return parent.widget ~= nil
end

return this
