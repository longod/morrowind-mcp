local this = {}

local function NewElement(name, elementType, parent)
    return {
        name = name,
        type = elementType,
        parent = parent,
        visible = true,
        isValid = function()
            return true
        end,
    }
end

---@param source tes3uiElement
---@param property tes3.uiProperty
---@return uiPreEventEventData
local function NewUiPreEvent(source, property)
    return {
        block = false,
        claim = false,
        parent = source.parent,
        property = property,
        source = source,
        var1 = 0,
        var2 = 0,
    }
end

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local uiAction = require("morrowind-mcp.util.ui_action")
    uiAction.ClearObservedHints()

    unitwind:start("morrowind-mcp.util.ui_action")

    unitwind:test("BuildElementPath uses RFC 6901 separators", function()
        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuScroll", "rect", root)
        local main = NewElement("PartNonDragMenu_main", "model", menu)
        local holder = NewElement("null", "layout", main)
        local button = NewElement("MenuBook_PickupButton", "layout", holder)

        unitwind:expect(uiAction.BuildElementPath(button)).toBe(
            "layout/MenuScroll/PartNonDragMenu_main/null/MenuBook_PickupButton")
    end)

    unitwind:test("BuildElementPath escapes RFC 6901 token characters", function()
        local root = NewElement(nil, "layout")
        local child = NewElement("Child/with~characters", "layout", root)

        unitwind:expect(uiAction.BuildElementPath(child)).toBe("layout/Child~1with~0characters")
    end)

    unitwind:test("BuildElementPath does not include runtime ids", function()
        local root = NewElement(nil, "layout")
        local child = NewElement("Child", "layout", root)
        child.id = 12345

        unitwind:expect(uiAction.BuildElementPath(child)).toBe("layout/Child")
    end)

    unitwind:test("BuildElementPath rejects elements without name or type", function()
        local root = NewElement(nil, nil)

        unitwind:expect(uiAction.BuildElementPath(root)).toBe(nil)
    end)

    unitwind:test("GetActionProperties skips widget elements", function()
        local root = NewElement(nil, "layout")
        local button = NewElement("MenuBook_PickupButton", "layout", root)
        button.widget = {}

        unitwind:expect(uiAction.GetActionProperties(button)).toBe(nil)
    end)

    unitwind:test("GetInventoryTile resolves each supported inventory pane property", function()
        for _, property in ipairs({ "MenuInventory_Thing", "MenuContents_Thing", "MenuBarter_Thing" }) do
            local element = NewElement(nil, "layout")
            local tile = {}
            element.getPropertyObject = function(_, requestedProperty, typeCast)
                if requestedProperty == property and typeCast == "tes3inventoryTile" then
                    return tile
                end
                return nil
            end

            unitwind:expect(uiAction.GetInventoryTile(element)).toBe(tile)
        end
    end)

    unitwind:test("GetWidgetActionProperties returns supported actions", function()
        local buttonElement = NewElement("Button", "button")
        local properties = uiAction.GetWidgetActionProperties({ element = buttonElement })

        unitwind:expect(table.size(properties)).toBe(1)
        unitwind:expect(properties[1]).toBe("mouseClick")
    end)

    unitwind:test("GetWidgetActionProperties makes unsupported widgets explicit", function()
        local fillbarElement = NewElement("Fill", "fillbar")
        local properties = uiAction.GetWidgetActionProperties({ element = fillbarElement })

        unitwind:expect(table.size(properties)).toBe(0)
    end)

    unitwind:test("tes3 ui action properties use widget actions when no native hint exists", function()
        local ui = require("morrowind-mcp.tes3.ui")
        local button = NewElement("Button", "button")
        button.widget = { element = button }

        local properties = ui.GetActionProperties(button)

        unitwind:expect(properties == nil).toBe(false)
        if properties then
            unitwind:expect(properties[1]).toBe("mouseClick")
        end
    end)

    unitwind:test("tes3 ui action properties distinguish unsupported and non-widget elements", function()
        local ui = require("morrowind-mcp.tes3.ui")
        local fillbar = NewElement("Fill", "fillbar")
        fillbar.widget = { element = fillbar }
        local layout = NewElement("Unknown", "layout")

        local fillbarProperties = ui.GetActionProperties(fillbar)

        unitwind:expect(fillbarProperties == nil).toBe(false)
        if fillbarProperties then
            unitwind:expect(table.size(fillbarProperties)).toBe(0)
        end
        unitwind:expect(ui.GetActionProperties(layout)).toBe(nil)
    end)

    unitwind:test("GetActionProperties exposes scroll arrow mouse clicks", function()
        local root = NewElement(nil, "layout")
        local scrollBar = NewElement("Slider", "scrollBar", root)
        scrollBar.widget = {}
        local arrow = NewElement("PartScrollBar_left_arrow", "model", scrollBar)

        local properties = uiAction.GetActionProperties(arrow)

        unitwind:expect(properties == nil).toBe(false)
        if properties then
            unitwind:expect(properties[1]).toBe("mouseClick")
        end
    end)

    unitwind:test("tes3uiElement emits unique structural paths for duplicate names", function()
        local ui = require("morrowind-mcp.tes3.ui")
        local root = NewElement(nil, "layout")
        root.children = {}
        local first = NewElement("duplicate", "layout", root)
        local second = NewElement("duplicate", "layout", root)
        first.children = {}
        second.children = {}
        root.children = { first, second }

        local serialized = ui.tes3uiElement(root)

        unitwind:expect(serialized == nil).toBe(false)
        if serialized and serialized.children then
            unitwind:expect(serialized.path).toBe("")
            unitwind:expect(serialized.children[1].path).toBe("/children/0")
            unitwind:expect(serialized.children[2].path).toBe("/children/1")
        end
    end)

    unitwind:test("tes3uiElement keeps widget actions off the parent element", function()
        local ui = require("morrowind-mcp.tes3.ui")
        local element = NewElement("Button", "button")
        element.children = {}
        element.widget = { element = element }

        local serialized = ui.tes3uiElement(element)

        unitwind:expect(serialized == nil).toBe(false)
        if serialized then
            unitwind:expect(serialized.actionable).toBe(nil)
            unitwind:expect(serialized.widget == nil).toBe(false)
            if serialized.widget and serialized.widget.actionable then
                unitwind:expect(serialized.widget.actionable[1]).toBe("mouseClick")
            end
        end
    end)

    unitwind:test("tes3uiWidget exposes an empty actionable array for unsupported widgets", function()
        local ui = require("morrowind-mcp.tes3.ui")
        local fillbarElement = NewElement("Fill", "fillbar")
        local serialized = ui.tes3uiWidget({ element = fillbarElement })

        unitwind:expect(serialized == nil).toBe(false)
        if serialized then
            unitwind:expect(serialized.actionable == nil).toBe(false)
            if serialized.actionable then
                unitwind:expect(table.size(serialized.actionable)).toBe(0)
            end
        end
    end)

    unitwind:test("GetActionProperties skips non-layout elements", function()
        local root = NewElement(nil, "layout")
        local rect = NewElement("MenuBook_PickupButton", "rect", root)

        unitwind:expect(uiAction.GetActionProperties(rect)).toBe(nil)
    end)

    unitwind:test("GetActionProperties returns static properties", function()
        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuScroll", "rect", root)
        local main = NewElement("PartNonDragMenu_main", "model", menu)
        local holder = NewElement("null", "layout", main)
        local button = NewElement("MenuBook_PickupButton", "layout", holder)

        local properties = uiAction.GetActionProperties(button)

        unitwind:expect(properties == nil).toBe(false)
        if properties then
            unitwind:expect(table.size(properties)).toBe(1)
            unitwind:expect(properties[1]).toBe("mouseClick")
        end
    end)

    unitwind:test("Observed properties override static properties", function()
        uiAction.ClearObservedHints()

        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuScroll", "rect", root)
        local main = NewElement("PartNonDragMenu_main", "model", menu)
        local holder = NewElement("null", "layout", main)
        local button = NewElement("MenuScroll_Close", "layout", holder)

        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.mouseClick))

        local properties = uiAction.GetActionProperties(button)

        unitwind:expect(properties == nil).toBe(false)
        if properties then
            unitwind:expect(table.size(properties)).toBe(1)
            unitwind:expect(properties[1]).toBe("mouseClick")
        end
    end)

    unitwind:test("Observed properties keep actionable uiPreEvent properties", function()
        uiAction.ClearObservedHints()

        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuCustom", "rect", root)
        local button = NewElement("MenuCustom_Button", "layout", menu)

        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.mouseOver))
        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.release))
        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.mouseClick))
        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.mouseClick))

        local properties = uiAction.GetActionProperties(button)

        unitwind:expect(properties == nil).toBe(false)
        if properties then
            unitwind:expect(table.size(properties)).toBe(2)
            unitwind:expect(properties[1]).toBe("release")
            unitwind:expect(properties[2]).toBe("mouseClick")
        end
    end)

    unitwind:test("FormatObservedHintsForStaticList emits copyable rows without ids", function()
        uiAction.ClearObservedHints()

        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuDump", "rect", root)
        local button = NewElement("MenuDump_Button", "layout", menu)
        button.id = 777

        uiAction.ObserveUiPreEvent(NewUiPreEvent(button, tes3.uiProperty.mouseClick))

        local dump = uiAction.FormatObservedHintsForStaticList()

        unitwind:expect(string.find(dump, "MenuDump_Button", 1, true) ~= nil).toBe(true)
        unitwind:expect(string.find(dump, "properties = { \"mouseClick\" }", 1, true) ~= nil).toBe(true)
        unitwind:expect(string.find(dump, "id", 1, true)).toBe(nil)
    end)

    uiAction.ClearObservedHints()

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
