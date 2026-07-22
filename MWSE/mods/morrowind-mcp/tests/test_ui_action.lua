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

    unitwind:test("BuildElementPath uses the default separator", function()
        local root = NewElement(nil, "layout")
        local menu = NewElement("MenuScroll", "rect", root)
        local main = NewElement("PartNonDragMenu_main", "model", menu)
        local holder = NewElement("null", "layout", main)
        local button = NewElement("MenuBook_PickupButton", "layout", holder)

        unitwind:expect(uiAction.BuildElementPath(button)).toBe(
            "layout|MenuScroll|PartNonDragMenu_main|null|MenuBook_PickupButton")
    end)

    unitwind:test("BuildElementPath accepts an alternate separator", function()
        local root = NewElement(nil, "layout")
        local child = NewElement("Child", "layout", root)

        unitwind:expect(uiAction.BuildElementPath(child, ">")).toBe("layout>Child")
    end)

    unitwind:test("BuildElementPath does not include runtime ids", function()
        local root = NewElement(nil, "layout")
        local child = NewElement("Child", "layout", root)
        child.id = 12345

        unitwind:expect(uiAction.BuildElementPath(child)).toBe("layout|Child")
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
