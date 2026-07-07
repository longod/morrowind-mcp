local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local config = require("morrowind-mcp.config")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "serializer" })
local enumname = require("morrowind-mcp.tes3.enumname")

local this = {}

local fontName = {
    [0] = "magic_cards_regular",         -- Magic Cards, default
    [1] = "century_gothic_font_regular", -- Century Sans
    [2] = "daedric_font",
}

---@param i tes3uiElement
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiElement(i, o)
    if not i then
        return nil
    end
    if not i:isValid() then
        return nil
    end
    -- same as human visibility
    if not i.visible then
        return nil
    end

    o = o or jsonrpc.object()
    -- o.absolutePosAlignX = i.absolutePosAlignX
    -- o.absolutePosAlignY = i.absolutePosAlignY
    -- o.alpha = i.alpha
    -- o.autoHeight = i.autoHeight
    -- o.autoWidth = i.autoWidth
    -- o.borderAllSides = i.borderAllSides
    -- o.borderBottom = i.borderBottom
    -- o.borderLeft = i.borderLeft
    -- o.borderRight = i.borderRight
    -- o.borderTop = i.borderTop
    -- o.childAlignX = i.childAlignX
    -- o.childAlignY = i.childAlignY
    -- o.childOffsetX = i.childOffsetX
    -- o.childOffsetY = i.childOffsetY
    -- o.color = i.color
    o.consumeMouseEvents = i.consumeMouseEvents
    o.contentPath = i.contentPath
    -- o.contentType = i.contentType -- already a string from MWSE; tes3.contentType holds numbers, not this field
    o.disabled = i.disabled
    -- o.flowDirection = enumname.flowDirection(i.flowDirection)
    o.font = fontName[i.font]
    -- o.height = i.height
    -- o.heightProportional = i.heightProportional
    o.id = i.id
    -- o.ignoreLayoutX = i.ignoreLayoutX
    -- o.ignoreLayoutY = i.ignoreLayoutY
    -- o.imageFilter = i.imageFilter
    -- o.imageScaleX = i.imageScaleX
    -- o.imageScaleY = i.imageScaleY
    -- o.justifyText = i.justifyText
    -- o.maxHeight = i.maxHeight
    -- o.maxWidth = i.maxWidth
    -- o.minHeight = i.minHeight
    -- o.minWidth = i.minWidth
    o.name = i.name
    -- o.paddingAllSides = i.paddingAllSides
    -- o.paddingBottom = i.paddingBottom
    -- o.paddingLeft = i.paddingLeft
    -- o.paddingRight = i.paddingRight
    -- o.paddingTop = i.paddingTop
    -- o.parent = i.parent
    -- o.positionX = i.positionX
    -- o.positionY = i.positionY
    o.rawText = i.rawText
    o.repeatKeys = i.repeatKeys
    -- o.scaleMode = i.scaleMode
    -- o.sceneNode = i.sceneNode, -- need?
    o.text = i.text
    -- o.texture = i.texture, -- need
    o.type = i.type -- already a string from MWSE; tes3.uiElementType holds numbers, not this field
    -- o.visible = i.visible -- if element is not terminated, it is needed to contain
    -- o.widget = ToJsonWidget(i.widget, i.type) -- TODO
    -- o.width = i.width
    -- o.widthProportional = i.widthProportional

    local children = jsonrpc.array(table.size(i.children))
    for _, child in ipairs(i.children) do
        local c = this.tes3uiElement(child)
        if c then
            table.insert(children, c)
        end
    end
    if table.size(children) > 0 then
        o.children = children
    end

    return o
end

return this
