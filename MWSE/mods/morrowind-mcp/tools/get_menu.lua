
local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")


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
        description = "Get current menus state. menu is user interface such as inventory. help is overlay such as tooltips.",
        inputSchema = jsonrpc.InputSchema(
            -- menu name, path or all
            -- filter?
            -- contain help layer
            -- depth
            -- show invisible
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                menu = jsonrpc.JsonObjectSchema(),
                help = jsonrpc.JsonObjectSchema(),
            }
            -- , jsonrpc.array({"menu"})
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
    "magic_cards_regular", -- Magic Cards, default
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
        -- visible = e.visible, -- terminate?
        -- widget = ToJsonWidget(e.widget, e.type), -- need?
        -- width = e.width,
        -- widthProportional = e.widthProportional,
    }) or {}

    local children = jsonrpc.array(table.size(e.children))
    for _, child in ipairs(e.children) do
        local c =ToJsonElement(child)
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
    local arguments = params.arguments or {}

    local main = tes3.worldController.menuController.mainRoot
    local help = tes3.worldController.menuController.helpRoot

    local structuredContent = jsonrpc.object({menu = ToJsonElement(main), help = ToJsonElement(help)})
    return jsonrpc.CallToolResult(nil, structuredContent)
end



return this
