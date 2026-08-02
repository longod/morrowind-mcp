local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    local ui = require("morrowind-mcp.tes3.ui")

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

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
