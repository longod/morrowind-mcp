local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "tes3ui" })
local enumname = require("morrowind-mcp.tes3.enumname")
local ui_action = require("morrowind-mcp.util.ui_action")
local jsonpointer = require("morrowind-mcp.core.json_pointer")
local strutil = require("morrowind-mcp.core.strutil")
local widgetutil = require("morrowind-mcp.tes3.widget")

local this = {}

local fontId = {
    magic_cards_regular = 0,
    century_gothic_font_regular = 1,
    daedric_font = 2,
}

local fontName = {
    [0] = "magic_cards_regular",         -- Magic Cards, default
    [1] = "century_gothic_font_regular", -- Century Sans
    [2] = "daedric_font",
}

--- Validates an RFC 6901 UI path before resolving it against a live UI tree.
---@param menuPath string
---@return boolean valid
---@return string? errorMessage
function this.ValidatePath(menuPath)
    local tokens, errorMessage = jsonpointer.Parse(menuPath)
    return tokens ~= nil, errorMessage
end

--- Resolves a serialized UI path using raw MWSE child indexes.
---@param root tes3uiElement
---@param menuPath string
---@return tes3uiElement? target
---@return string? errorMessage
function this.ResolvePath(root, menuPath)
    local tokens, errorMessage = jsonpointer.Parse(menuPath)
    if not tokens then
        return nil, errorMessage
    end

    local target = root
    local tokenIndex = 1
    while tokenIndex <= table.size(tokens) do
        if tokens[tokenIndex] ~= "children" then
            return nil, "menu_path may only traverse children arrays."
        end
        local rawIndex = tonumber(tokens[tokenIndex + 1])
        if rawIndex == nil or rawIndex < 0 or tostring(rawIndex) ~= tokens[tokenIndex + 1] then
            return nil, "menu_path contains an invalid children index."
        end
        if not target.children then
            return nil, "menu_path traverses an element without children."
        end
        target = target.children[rawIndex + 1]
        if not target then
            return nil, "menu_path points to a missing child."
        end
        tokenIndex = tokenIndex + 2
    end
    return target, nil
end

--- Return visible text in display order without repeating text inherited by nested UI elements.
---@param element tes3uiElement?
---@return string? text
function this.ExtractVisibleText(element)
    local textParts = {}
    local seen = {}

    local function Visit(current)
        if not current or not current:isValid() or not current.visible then
            return
        end

        if type(current.text) == "string" and current.text ~= "" and not seen[current.text] then
            seen[current.text] = true
            table.insert(textParts, current.text)
        end

        for _, child in ipairs(current.children or {}) do
            Visit(child)
        end
    end

    Visit(element)
    if table.size(textParts) == 0 then
        return nil
    end
    return table.concat(textParts, "\n")
end

---@param i tes3uiElement
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
local function tes3uiElementWeak(i, o)
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
    o.id = i.id
    o.name = i.name
    o.type = i.type
    return o
end

---@param i tes3uiButton
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiButton(i, o)
    o.state = enumname.uiState(i.state)
    o.textElement = tes3uiElementWeak(i.textElement)
    return o
end
---@param i tes3uiColorPicker
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiColorPicker(i, o)
    -- o.alphaBar = i.alphaBar
    -- o.alphaCheckerboard = i.alphaCheckerboard
    -- o.currentAlpha = i.currentAlpha
    o.currentColor = jsonrpc.array({i.currentColor.r, i.currentColor.g, i.currentColor.b})
    -- o.height = i.height
    -- o.hueBar = i.hueBar
    -- o.hueWidth = i.hueWidth
    -- o.initialAlpha = i.initialAlpha
    -- o.initialColor = i.initialColor
    -- o.mainImage = i.mainImage
    -- o.mainWidth = i.mainWidth
    -- o.saturationBar = i.saturationBar
    -- o.textures = i.textures
    return o
end
---@param i tes3uiColorPreview
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiColorPreview(i, o)
    o.alpha = i.alpha
    -- o.checkerboard = i.checkerboard
    -- o.checkerSize = i.checkerSize
    o.color =  jsonrpc.array({i.color.r, i.color.g, i.color.b})
    -- o.darkGray = i.darkGray
    -- o.height = i.height
    -- o.image = i.image
    -- o.lightGray = i.lightGray
    -- o.texture = i.texture
    -- o.width = i.width
    return o
end
---@param i tes3uiCycleButton
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiCycleButton(i, o)
    o.index = i.index
    -- o.options = i.options -- TODO weak reference
    o.text = i.text
    -- o.value = i.value -- maybe no needed
    return o
end
---@param i tes3uiFillBar
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiFillBar(i, o)
    o.current = i.current
    -- o.fillAlpha = i.fillAlpha
    -- o.fillColor = i.fillColor
    o.max = i.max
    o.normalized = i.normalized
    -- o.showText = i.showText -- maybe no needed
    return o
end
---@param i tes3uiHyperlink
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiHyperlink(i, o)
    o.confirm = i.confirm
    o.url = i.url
    return o
end
---@param i tes3uiParagraphInput
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiParagraphInput(i, o)
    o.lengthLimit = i.lengthLimit or 1023 -- default
    return o
end
---@param i tes3uiScrollPane
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiScrollPane(i, o)
    o.contentPane = tes3uiElementWeak(i.contentPane)
    o.positionX = i.positionX
    o.positionY = i.positionY
    o.scrollbarVisible = i.scrollbarVisible
    return o
end
---@param i tes3uiSlider
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiSlider(i, o)
    o.current = i.current
    o.jump = i.jump
    o.max = i.max
    o.step = i.step
    return o
end
---@param i tes3uiTabContainer
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiTabContainer(i, o)
    o.currentTab = i.currentTab
    return o
end
---@param i tes3uiTextInput
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiTextInput(i, o)
    o.eraseOnFirstKey = i.eraseOnFirstKey or true -- default
    o.lengthLimit  = i.lengthLimit
    return o
end
---@param i tes3uiTextSelect
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiTextSelect(i, o)
    -- o.idle = i.idle
    -- o.idleActive = i.idleActive
    -- o.idleDisabled = i.idleDisabled
    -- o.over = i.over
    -- o.overActive = i.overActive
    -- o.overDisabled = i.overDisabled
    -- o.pressed = i.pressed
    -- o.pressedActive = i.pressedActive
    -- o.pressedDisabled = i.pressedDisabled
    o.state = enumname.uiState(i.state)
    return o
end

local widgetHandler = {
    ["button"] = this.tes3uiButton,
    ["fillbar"] = this.tes3uiFillBar,
    ["image"] = nil,
    ["layout"] = nil,
    ["luaWidget"] = nil,
    ["model"] = nil,
    ["paragraphInput"] = this.tes3uiParagraphInput,
    ["rect"] = nil,
    ["scrollBar"] = this.tes3uiSlider, -- PartScrollBar
    ["scrollPane"] = this.tes3uiScrollPane,
    ["text"] = nil,
    ["textInput"] = this.tes3uiTextInput,
    ["textSelect"] = this.tes3uiTextSelect,
    -- luaWidget
    ["colorPicker"] = this.tes3uiColorPicker,
    ["colorPreview"] = this.tes3uiColorPreview,
    ["cycleButton"] = this.tes3uiCycleButton,
    ["hyperlink"] = this.tes3uiHyperlink,
    ["tabContainer"] = this.tes3uiTabContainer,
}


---@param i tes3uiButton|tes3uiColorPicker|tes3uiColorPreview|tes3uiCycleButton|tes3uiFillBar|tes3uiHyperlink|tes3uiParagraphInput|tes3uiScrollPane|tes3uiSlider|tes3uiTabContainer|tes3uiTextInput|tes3uiTextSelect|tes3uiWidget|nil
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiWidget(i, o)
    if i == nil then
        return nil
    end

    o = o or jsonrpc.object()

    local widgetType = widgetutil.GetType(i)
    o.type = widgetType
    -- Always expose an array so unsupported widgets are distinguishable from omitted metadata.
    o.actionable = jsonrpc.array(ui_action.GetWidgetActionProperties(i))
    -- o.element = i.element -- parent

    local handler = widgetHandler[widgetType]
    if handler then
        o = handler(i, o)
    else
        logger:warn("No serializer for widget type '%s'", widgetType)
    end

    return o
end

--- Returns the actions that can be executed against a live UI element.
--- This is shared by UI serialization and menu actions so advertised actions remain executable.
---@param element tes3uiElement
---@return string[]? properties
function this.GetActionProperties(element)
    local properties = ui_action.GetActionProperties(element)
    if properties then
        return properties
    end
    if element.widget then
        return ui_action.GetWidgetActionProperties(element.widget)
    end
    return nil
end

--- Builds the stable item identity included with an inventory tile action.
---@param tile tes3inventoryTile
---@param menu tes3uiElement?
---@return MCP.AnyMap
local function SerializeInventoryTile(tile, menu)
    local item = tile.item
    ---@type MCP.AnyMap
    local metadata = jsonrpc.object({
        item = item and jsonrpc.object({ id = item.id, name = item.name }) or nil,
        count = tile.count,
        is_equipped = tile.isEquipped,
        is_bartered = tile.isBartered,
        is_bound_item = tile.isBoundItem,
        tile_type = tostring(tile.type),
        menu_name = menu and menu.name or nil,
    })

    if menu and menu.name == "MenuInventory" then
        metadata.inventory_pane = "player"
    elseif menu and menu.name == "MenuBarter" then
        metadata.inventory_pane = "barter"
    elseif menu and menu.name == "MenuContents" then
        metadata.inventory_pane = "contents"
    end
    return metadata
end

--- Finds a live element's raw-index path relative to a root so filtered action paths remain executable from mainRoot.
---@param root tes3uiElement?
---@param target tes3uiElement?
---@return string? path
function this.FindPath(root, target)
    if not root or not target then
        return nil
    end
    if root == target then
        return ""
    end

    local function Visit(current, currentPath)
        for childIndex, child in ipairs(current.children or {}) do
            local childPath = currentPath .. "/children/" .. tostring(childIndex - 1)
            if child == target then
                return childPath
            end
            local found = Visit(child, childPath)
            if found then
                return found
            end
        end
        return nil
    end

    return Visit(root, "")
end

--- Returns an element rectangle in the scaled UI viewport coordinate system.
--- Top-level Morrowind menus are positioned relative to the viewport center.
---@param element tes3uiElement?
---@return MCP.AnyMap? rect
function this.GetScreenRect(element)
    if not element or type(tes3ui.getViewportSize) ~= "function" then
        return nil
    end

    local viewportWidth, viewportHeight = tes3ui.getViewportSize()
    if type(viewportWidth) ~= "number" or type(viewportHeight) ~= "number" then
        return nil
    end

    local x = viewportWidth / 2
    local y = -viewportHeight / 2
    local current = element
    while current do
        x = x + (current.positionX or 0)
        y = y + (current.positionY or 0)
        current = current.parent
    end
    return jsonrpc.object({
        x = x,
        y = y,
        width = element.width,
        height = element.height,
        viewport_width = viewportWidth,
        viewport_height = viewportHeight,
    })
end

--- Collects visible, enabled action targets with raw-index paths suitable for mw-menu-action.
---@param root tes3uiElement?
---@param rootPath string?
---@return MCP.AnyMap[] actions
function this.CollectActionable(root, rootPath)
    local actions = jsonrpc.array()
    if not root then
        return actions
    end

    local function Visit(element, elementPath)
        if not element or not element:isValid() or not element.visible then
            return
        end

        local actionable = this.GetActionProperties(element)
        if actionable and table.size(actionable) > 0 and not element.disabled then
            local action = jsonrpc.object({
                path = elementPath,
                actions = jsonrpc.array(actionable),
                id = element.id,
                name = element.name,
                type = element.type,
                text = element.text,
                screen_rect = this.GetScreenRect(element),
            })
            local tile = ui_action.GetInventoryTile(element)
            if tile then
                action.inventory_tile = SerializeInventoryTile(tile, element:getTopLevelMenu())
            end
            table.insert(actions, action)
        end

        for childIndex, child in ipairs(element.children or {}) do
            Visit(child, elementPath .. "/children/" .. tostring(childIndex - 1))
        end
    end

    Visit(root, rootPath or "")
    return actions
end

--- Serializes the current cursor tile and associates it with its live action path.
---@param mainRoot tes3uiElement
---@return MCP.AnyMap? cursorTile
function this.GetCursorTile(mainRoot)
    local tile = tes3ui.getCursorTile()
    if not tile then
        return nil
    end

    local menu = tile.element and tile.element:getTopLevelMenu() or nil
    local metadata = SerializeInventoryTile(tile, menu)
    if tile.element and ui_action.GetInventoryTile(tile.element) then
        metadata.path = this.FindPath(mainRoot, tile.element)
    end
    return metadata
end

---@param i tes3uiElement
---@param o MCP.AnyMap?
---@return MCP.AnyMap?
function this.tes3uiElement(i, o, path)
    if not i then
        return nil
    end
    local elementPath = path or ""
    if not i:isValid() or not i.visible then
        -- Menu fetch exposes only live controls a player can currently see.
        return nil
    end

    o = o or jsonrpc.object()
    -- This RFC 6901 pointer addresses the serialized tree, so duplicate names and IDs remain unambiguous.
    o.path = elementPath
    o.screen_rect = this.GetScreenRect(i)
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
    -- o.consumeMouseEvents = i.consumeMouseEvents
    o.contentPath = i.contentPath
    -- o.contentType = i.contentType -- already a string from MWSE; tes3.contentType holds numbers, not this field
    if i.disabled then
        o.disabled = i.disabled
    end
    -- o.flowDirection = enumname.flowDirection(i.flowDirection)
    -- o.font = fontName[i.font]
    if i.font == fontId.daedric_font then
        o.writtenInDaedric = true -- only for daedric texts, because they are like ciphers.
    end
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
    -- o.rawText = i.rawText
    -- o.repeatKeys = i.repeatKeys -- need?
    -- o.scaleMode = i.scaleMode
    -- o.sceneNode = i.sceneNode, -- need?
    -- o.text = i.text
    -- Same condition, because rawText is text + formatting and caret.
    -- We want to output text if they exsist and text is empty, because they indicate this element is any text type.
    if strutil.IsNullOrEmpty(i.rawText) == false then
        if i.text ~= i.rawText then -- not same as text, because text is rawText stripped of formatting and caret.
            o.rawText = i.rawText
        end
        o.text = i.text
    end
    -- o.texture = i.texture, -- need
    o.type = i.type -- already a string from MWSE; tes3.uiElementType holds numbers, not this field
    o.widget = this.tes3uiWidget(i.widget)
    -- o.width = i.width
    -- o.widthProportional = i.widthProportional

    -- Native widgetless layout action properties, if known.
    local actionable = ui_action.GetActionProperties(i)
    if actionable then
        o.actionable = jsonrpc.array(actionable)
    end

    local children = jsonrpc.array()
    for childIndex, child in ipairs(i.children) do
        -- Paths use raw MWSE child indexes so visible siblings do not shift when hidden ones toggle.
        local childPath = elementPath .. "/children/" .. tostring(childIndex - 1)
        local c = this.tes3uiElement(child, nil, childPath)
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
