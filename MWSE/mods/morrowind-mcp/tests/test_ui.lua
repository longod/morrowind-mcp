local this = {}

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
    local ui = require("morrowind-mcp.tes3.ui")
    local mcpui = require("morrowind-mcp.util.mcpui")

    unitwind:start("morrowind-mcp.tes3.ui")

    unitwind:test("tes3uiElement includes only visible valid children", function()
        local function ValidElement(properties)
            properties.isValid = function()
                return true
            end
            properties.children = properties.children or {}
            return properties
        end

        local root = ValidElement({
            id = 1,
            name = "root",
            type = "layout",
            visible = true,
            children = {
                ValidElement({ id = 2, name = "hidden", type = "layout", visible = false }),
                {
                    isValid = function()
                        return false
                    end,
                },
                ValidElement({ id = 3, name = "visible", type = "layout", visible = true }),
            },
        })

        local serialized = ui.tes3uiElement(root)
        if not serialized then
            error("Expected visible root to be serialized.")
        end
        local children = serialized.children
        if not children then
            error("Expected visible child to be serialized.")
        end

        unitwind:expect(table.size(children)).toBe(1)
        unitwind:expect(children[1].path).toBe("/children/2")
        unitwind:expect(children[1].name).toBe("visible")
    end)

    unitwind:test("tes3uiElement preserves raw indexes at every visible depth", function()
        local function ValidElement(properties)
            properties.isValid = function()
                return true
            end
            properties.children = properties.children or {}
            return properties
        end

        local nestedVisible = ValidElement({ id = 5, name = "nestedVisible", type = "layout", visible = true })
        local visibleParent = ValidElement({
            id = 2,
            name = "visibleParent",
            type = "layout",
            visible = true,
            children = {
                ValidElement({ id = 3, name = "nestedHidden", type = "layout", visible = false }),
                nestedVisible,
            },
        })
        local root = ValidElement({
            id = 1,
            name = "root",
            type = "layout",
            visible = true,
            children = {
                ValidElement({ id = 4, name = "hidden", type = "layout", visible = false }),
                visibleParent,
            },
        })

        local serialized = ui.tes3uiElement(root)
        if not serialized or not serialized.children or not serialized.children[1].children then
            error("Expected visible nested elements to be serialized.")
        end

        unitwind:expect(serialized.children[1].path).toBe("/children/1")
        unitwind:expect(serialized.children[1].children[1].path).toBe("/children/1/children/1")
        unitwind:expect(serialized.children[1].children[1].name).toBe("nestedVisible")
    end)

    unitwind:test("ResolvePath selects duplicate-name children by raw index", function()
        local first = { name = "duplicate" }
        local second = { name = "duplicate" }
        local root = { children = { first, second } }

        local target, errorMessage = ui.ResolvePath(root, "/children/1")

        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(target).toBe(second)
    end)

    unitwind:test("ResolvePath preserves hidden and invalid raw child slots", function()
        local hidden = { visible = false, isValid = function() return true end }
        local invalid = { visible = true, isValid = function() return false end }
        local visible = { name = "visible", visible = true, isValid = function() return true end }
        local root = { children = { hidden, invalid, visible } }

        local target, errorMessage = ui.ResolvePath(root, "/children/2")

        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(target).toBe(visible)
    end)

    unitwind:test("ResolvePath preserves nested hidden raw child slots", function()
        local hidden = { visible = false, isValid = function() return true end }
        local visible = { name = "visible", visible = true, isValid = function() return true end }
        local parent = { children = { hidden, visible } }
        local root = { children = { parent } }

        local target, errorMessage = ui.ResolvePath(root, "/children/0/children/1")

        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(target).toBe(visible)
    end)

    unitwind:test("ResolvePath rejects malformed or unsupported paths", function()
        local root = { children = { {} } }

        local malformedTarget, malformedError = ui.ResolvePath(root, "/children~2/0")
        local canonicalTarget, canonicalError = ui.ResolvePath(root, "/children/01")
        local propertyTarget, propertyError = ui.ResolvePath(root, "/parent/0")
        local missingTarget, missingError = ui.ResolvePath(root, "/children/5")

        unitwind:expect(malformedTarget).toBe(nil)
        unitwind:expect(malformedError ~= nil).toBe(true)
        unitwind:expect(canonicalTarget).toBe(nil)
        unitwind:expect(canonicalError).toBe("menu_path contains an invalid children index.")
        unitwind:expect(propertyTarget).toBe(nil)
        unitwind:expect(propertyError).toBe("menu_path may only traverse children arrays.")
        unitwind:expect(missingTarget).toBe(nil)
        unitwind:expect(missingError).toBe("menu_path points to a missing child.")
    end)

    unitwind:test("ExtractVisibleText returns ordered unique visible text", function()
        local function ValidElement(properties)
            properties.isValid = function()
                return true
            end
            properties.children = properties.children or {}
            return properties
        end

        local root = ValidElement({
            visible = true,
            text = "First",
            children = {
                ValidElement({ visible = false, text = "Hidden" }),
                ValidElement({ visible = true, text = "Second" }),
                ValidElement({ visible = true, text = "First" }),
            },
        })

        unitwind:expect(ui.ExtractVisibleText(root)).toBe("First\nSecond")
    end)

    unitwind:test("CollectActionable includes a live inventory tile with its raw-index path", function()
        local tileElement = {
            id = 3,
            name = "itemTile",
            type = "layout",
            visible = true,
            children = {},
            isValid = function()
                return true
            end,
            getTopLevelMenu = function()
                return { name = "MenuInventory" }
            end,
        }
        local root = {
            visible = true,
            children = {
                {
                    visible = false,
                    children = {},
                    isValid = function()
                        return true
                    end,
                },
                tileElement,
            },
            isValid = function()
                return true
            end,
        }
        local item = { id = "iron_spear", name = "Iron Spear" }
        local tile = {
            item = item,
            count = 2,
            isEquipped = false,
            isBartered = false,
            isBoundItem = false,
            type = 0,
        }
        tileElement.getPropertyObject = function(_, property, typeCast)
            if property == "MenuInventory_Thing" and typeCast == "tes3inventoryTile" then
                return tile
            end
            return nil
        end

        local actions = ui.CollectActionable(root)

        unitwind:expect(table.size(actions)).toBe(1)
        unitwind:expect(actions[1].path).toBe("/children/1")
        unitwind:expect(actions[1].actions[1]).toBe("mouseClick")
        unitwind:expect(actions[1].inventory_tile.item.id).toBe("iron_spear")
        unitwind:expect(actions[1].inventory_tile.inventory_pane).toBe("player")
    end)

    unitwind:test("CollectActionable distinguishes barter and contents inventory panes", function()
        local function ValidElement(properties)
            properties.isValid = function()
                return true
            end
            properties.children = properties.children or {}
            return properties
        end

        for _, expectedPane in ipairs({ "barter", "contents" }) do
            local menuName = expectedPane == "barter" and "MenuBarter" or "MenuContents"
            local property = expectedPane == "barter" and "MenuBarter_Thing" or "MenuContents_Thing"
            local tileElement = ValidElement({
                visible = true,
                type = "layout",
                children = {},
                getTopLevelMenu = function()
                    return { name = menuName }
                end,
            })
            local tile = { count = 1, type = 0 }
            tileElement.getPropertyObject = function(_, requestedProperty, typeCast)
                if requestedProperty == property and typeCast == "tes3inventoryTile" then
                    return tile
                end
                return nil
            end

            local actions = ui.CollectActionable(ValidElement({ visible = true, children = { tileElement } }))

            unitwind:expect(table.size(actions)).toBe(1)
            unitwind:expect(actions[1].inventory_tile.inventory_pane).toBe(expectedPane)
        end
    end)

    unitwind:test("CollectActionable excludes elements with no executable action", function()
        local fillbar = {
            id = 2,
            name = "Fill",
            type = "fillbar",
            visible = true,
            children = {},
            isValid = function()
                return true
            end,
            widget = {
                element = { type = "fillbar" },
            },
        }
        local root = {
            visible = true,
            children = { fillbar },
            isValid = function()
                return true
            end,
        }

        unitwind:expect(table.size(ui.CollectActionable(root))).toBe(0)
    end)

    unitwind:test("mcpui marks and safely formats owned notifications", function()
        local receivedFormat = nil
        local receivedText = nil
        local expectedElement = {}
        unitwind:mock(tes3ui, "showNotifyMenu", function(format, text)
            receivedFormat = format
            receivedText = text
            return expectedElement
        end)

        local element = mcpui.showNotifyMenu("Status: %s", "100%")

        unitwind:expect(element).toBe(expectedElement)
        unitwind:expect(receivedFormat).toBe("%s")
        unitwind:expect(receivedText).toBe("Morrowind MCP: Status: 100%")
        unitwind:expect(mcpui.isOwnNotify(receivedText)).toBe(true)
        unitwind:expect(mcpui.isOwnNotify("Morrowind MCPX: Status")).toBe(false)

        mcpui.showNotifyMenu("Already formatted: 100%")
        unitwind:expect(receivedText).toBe("Morrowind MCP: Already formatted: 100%")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
