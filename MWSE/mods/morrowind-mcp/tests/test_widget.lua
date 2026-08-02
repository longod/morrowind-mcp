local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local widgetutil = require("morrowind-mcp.tes3.widget")

    unitwind:start("morrowind-mcp.tes3.widget")

    unitwind:test("GetType returns element type for plain widgets", function()
        local widget = { element = { type = "button" } }
        unitwind:expect(widgetutil.GetType(widget)).toBe("button")
    end)

    unitwind:test("GetType returns luaWidget subtype when present", function()
        local widget = {
            element = {
                type = "luaWidget",
                getLuaData = function(_, key)
                    if key == "MWSE:WidgetTypeName" then
                        return "hyperlink"
                    end
                    return nil
                end,
            },
        }
        unitwind:expect(widgetutil.GetType(widget)).toBe("hyperlink")
    end)

    unitwind:test("GetType keeps luaWidget when subtype metadata is missing", function()
        local widget = {
            element = {
                type = "luaWidget",
                getLuaData = function()
                    return nil
                end,
            },
        }
        unitwind:expect(widgetutil.GetType(widget)).toBe("luaWidget")
    end)

    unitwind:test("GetType keeps luaWidget when subtype metadata is empty", function()
        local widget = {
            element = {
                type = "luaWidget",
                getLuaData = function()
                    return ""
                end,
            },
        }
        unitwind:expect(widgetutil.GetType(widget)).toBe("luaWidget")
    end)

    unitwind:test("GetType returns nil for missing widget or element", function()
        ---@diagnostic disable-next-line: param-type-mismatch
        unitwind:expect(widgetutil.GetType(nil)).toBe(nil)
        ---@diagnostic disable-next-line: missing-fields
        unitwind:expect(widgetutil.GetType({})).toBe(nil)
    end)

    unitwind:test("IsScrollArrow accepts arrows below scrollBar widgets", function()
        local scrollBar = { type = "scrollBar", widget = {} }
        local arrow = { name = "PartScrollBar_left_arrow", parent = scrollBar }
        unitwind:expect(widgetutil.IsScrollArrow(arrow)).toBe(true)
    end)

    unitwind:test("IsScrollArrow accepts arrows below scrollPane widgets", function()
        local scrollPane = { type = "scrollPane", widget = {} }
        local arrow = { name = "PartScrollBar_right_arrow", parent = scrollPane }
        unitwind:expect(widgetutil.IsScrollArrow(arrow)).toBe(true)
    end)

    unitwind:test("IsScrollArrow rejects arrows outside scroll widgets", function()
        local layout = { type = "layout" }
        local arrow = { name = "PartScrollBar_left_arrow", parent = layout }
        unitwind:expect(widgetutil.IsScrollArrow(arrow)).toBe(false)
    end)

    unitwind:test("IsScrollArrow rejects non-arrow children", function()
        local scrollBar = { type = "scrollBar", widget = {} }
        local child = { name = "PartScrollBar_bar_back", parent = scrollBar }
        unitwind:expect(widgetutil.IsScrollArrow(child)).toBe(false)
    end)

    unitwind:test("IsScrollArrow requires a parent widget", function()
        local scrollBar = { type = "scrollBar" }
        local arrow = { name = "PartScrollBar_left_arrow", parent = scrollBar }
        unitwind:expect(widgetutil.IsScrollArrow(arrow)).toBe(false)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
