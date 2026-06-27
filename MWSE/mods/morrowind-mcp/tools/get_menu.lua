local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.GetMenu: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.GetMenu
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.GetMenu
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "get_menu" })
    instance.definition = jsonrpc.Tool({
        name = "get_menu",
        description =
        "Get current menus state. menu is user interface such as inventory. help is overlay such as tooltips.",
        inputSchema = jsonrpc.InputSchema(
            {
                menuId = jsonrpc.NumberSchema(
                    "Menu ID",
                    "Find a non-root hierarchy of menu by ID (key name is `id`). If not specified, all menus will be returned. One of `menuId` or `menuName` should be specified."
                ),
                menuName = jsonrpc.StringSchema(
                    "Menu Name",
                    "Find a non-root hierarchy of menu by name (key name is `name`). If not specified, all menus will be returned. One of `menuId` or `menuName` should be specified.",
                    minMenuNameLength,
                    maxMenuNameLength
                ),
                -- filter?
                -- contain help layer?
                -- depth
                -- show invisible? disabled?
                -- top-most menu
                -- get cursor
                -- get cursor tile
                -- focus element
            }
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                menu = jsonrpc.JsonObjectSchema(),
                help = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })
    return instance
end

function this:CanExecute(params)
    if not tes3.worldController or not tes3.worldController.menuController then
        return false
    end

    return true
end

local fonts = {
    "magic_cards_regular",         -- Magic Cards, default
    "century_gothic_font_regular", -- Century Sans
    "daedric_font",
}

--[[
---@param w tes3uiButton|tes3uiColorPicker|tes3uiColorPreview|tes3uiCycleButton|tes3uiFillBar|tes3uiHyperlink|tes3uiParagraphInput|tes3uiScrollPane|tes3uiSlider|tes3uiTabContainer|tes3uiTextInput|tes3uiTextSelect|tes3uiWidget|nil
---@param t tes3.uiElementType
---@return MCP.AnyMap?
local function ToJsonWidget(w, t)
    if not w then
        return nil
    end
    return nil
end
--]]


---@param e tes3uiElement?
---@return MCP.AnyMap?
local function ToJsonElement(e)
    if not e then
        return nil
    end

    -- same as human visibility
    if not e.visible then
        return nil
    end

    local s = jsonrpc.object({
        -- absolutePosAlignX = e.absolutePosAlignX,
        -- absolutePosAlignY = e.absolutePosAlignY,
        -- alpha = e.alpha,
        -- autoHeight = e.autoHeight,
        -- autoWidth = e.autoWidth,
        -- borderAllSides = e.borderAllSides,
        -- borderBottom = e.borderBottom,
        -- borderLeft = e.borderLeft,
        -- borderRight = e.borderRight,
        -- borderTop = e.borderTop,
        -- childAlignX = e.childAlignX,
        -- childAlignY = e.childAlignY,
        -- childOffsetX = e.childOffsetX,
        -- childOffsetY = e.childOffsetY,
        -- children = jsonrpc.array(table.size(e.children)), -- later
        -- color = e.color,
        consumeMouseEvents = e.consumeMouseEvents,
        contentPath = e.contentPath,
        contentType = e.contentType,
        disabled = e.disabled,
        -- flowDirection = e.flowDirection,
        font = fonts[e.font],
        -- height = e.height,
        -- heightProportional = e.heightProportional,
        id = e.id,
        -- ignoreLayoutX = e.ignoreLayoutX,
        -- ignoreLayoutY = e.ignoreLayoutY,
        -- imageFilter = e.imageFilter,
        -- imageScaleX = e.imageScaleX,
        -- imageScaleY = e.imageScaleY,
        -- justifyText = e.justifyText,
        -- maxHeight = e.maxHeight,
        -- maxWidth = e.maxWidth,
        -- minHeight = e.minHeight,
        -- minWidth = e.minWidth,
        name = e.name,
        -- paddingAllSides = e.paddingAllSides,
        -- paddingBottom = e.paddingBottom,
        -- paddingLeft = e.paddingLeft,
        -- paddingRight = e.paddingRight,
        -- paddingTop = e.paddingTop,
        -- parent = e.parent,
        -- positionX = e.positionX,
        -- positionY = e.positionY,
        rawText = e.rawText,
        repeatKeys = e.repeatKeys,
        -- scaleMode = e.scaleMode,
        -- sceneNode = e.sceneNode, -- need?
        text = e.text,
        -- texture = e.texture, -- need?
        type = e.type,
        -- visible = e.visible, -- if element is not terminated, it is needed to contain
        -- widget = ToJsonWidget(e.widget, e.type), -- need?
        -- width = e.width,
        -- widthProportional = e.widthProportional,
    }) or {}

    local children = jsonrpc.array(table.size(e.children))
    for _, child in ipairs(e.children) do
        local c = ToJsonElement(child)
        if c then
            table.insert(children, c)
        end
    end
    if table.size(children) > 0 then
        s.children = children
    end

    if table.size(s) > 0 then
        return s
    end
    return nil
end

function this:Execute(params)
    -- TODO validation for injection
    local arguments = params.arguments or {}
    local menuId = arguments["menuId"]
    local menuName = arguments["menuName"]
    if menuId ~= nil and menuName ~= nil then
        local errorContent = jsonrpc.TextContent("Only one of menuId or menuName should be specified.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local menu = tes3.worldController.menuController.mainRoot
    local help = tes3.worldController.menuController.helpRoot

    -- better distinguish between fineMenu and findChild, but arguments too complex, so just use findChild.

    if menuId ~= nil then
        if type(menuId) ~= "number" then
            local errorContent = jsonrpc.TextContent("menuId should be a number.")
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end

        self.logger:debug("Searching for menu with ID: %d", menuId)

        menu = menu:findChild(menuId)
        help = help:findChild(menuId)
    elseif menuName ~= nil then
        if type(menuName) ~= "string" or #menuName < minMenuNameLength or #menuName > maxMenuNameLength then
            local errorContent = jsonrpc.TextContent(string.format("menuName should be a string with length between %d and %d.", minMenuNameLength, maxMenuNameLength))
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end

        self.logger:debug("Searching for menu with Name: %s", menuName)

        menu = menu:findChild(menuName)
        help = help:findChild(menuName)
    else
        self.logger:debug("No menuId or menuName specified. Returning all menus.")
    end

    local structuredContent = jsonrpc.object({ menu = ToJsonElement(menu), help = ToJsonElement(help) })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
