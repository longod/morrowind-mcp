local this = {}

---@class MCP.TestDialogueMenuElement : tes3uiElement
---@field valid boolean

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end

    local dialogueMenu = require("morrowind-mcp.util.dialogue_menu")
    local ui = require("morrowind-mcp.tes3.ui")

    unitwind:start("morrowind-mcp.util.dialogue_menu")

    ---@param name string?
    ---@param elementType string
    ---@return MCP.TestDialogueMenuElement
    local function NewElement(name, elementType)
        return { ---@diagnostic disable-line: missing-fields
            name = name,
            type = elementType,
            visible = true,
            disabled = false,
            valid = true,
            isValid = function(self)
                return self.valid
            end,
        }
    end

    unitwind:test("GetSideActionKind uses verified vanilla names and service prefix", function()
        unitwind:expect(dialogueMenu.GetSideActionKind(NewElement("MenuDialog_a_topic", "textSelect"))).toBe("topic")
        unitwind:expect(dialogueMenu.GetSideActionKind(NewElement("MenuDialog_persuasion", "textSelect"))).toBe("persuasion")
        unitwind:expect(dialogueMenu.GetSideActionKind(NewElement("MenuDialog_service_barter", "textSelect"))).toBe("service")
        unitwind:expect(dialogueMenu.GetSideActionKind(NewElement("CustomService", "textSelect"))).toBe("unknown")
    end)

    unitwind:test("IsClickableTextSelect requires textSelect and advertised mouse click", function()
        local clickable = NewElement("MenuDialog_a_topic", "textSelect")
        local nonClickable = NewElement("MenuDialog_a_topic", "textSelect")
        local button = NewElement("MenuDialog_a_topic", "button")
        unitwind:mock(ui, "GetActionProperties", function(element)
            if element == clickable or element == button then
                return { tes3.uiEvent.mouseClick }
            end
            return {}
        end)

        unitwind:expect(dialogueMenu.IsClickableTextSelect(clickable)).toBe(true)
        unitwind:expect(dialogueMenu.IsClickableTextSelect(nonClickable)).toBe(false)
        unitwind:expect(dialogueMenu.IsClickableTextSelect(button)).toBe(false)
    end)

    unitwind:test("GetDialogueMenu rejects missing, hidden, disabled, and invalid menus", function()
        local current = nil
        unitwind:mock(tes3ui, "registerID", function()
            return -237
        end)
        unitwind:mock(tes3ui, "findMenu", function()
            return current
        end)

        unitwind:expect(dialogueMenu.GetDialogueMenu()).toBe(nil)
        current = NewElement("MenuDialog", "layout")
        current.visible = false
        unitwind:expect(dialogueMenu.GetDialogueMenu()).toBe(nil)
        current.visible = true
        current.disabled = true
        unitwind:expect(dialogueMenu.GetDialogueMenu()).toBe(nil)
        current.disabled = false
        current.valid = false
        unitwind:expect(dialogueMenu.GetDialogueMenu()).toBe(nil)
        current.valid = true
        unitwind:expect(dialogueMenu.GetDialogueMenu()).toBe(current)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this