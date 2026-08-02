local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    local menuAction = require("morrowind-mcp.tools.menu_action")

    unitwind:start("morrowind-mcp.tools.menu_action")

    unitwind:test("ResolveMenuPath selects a duplicate-name child by serialized index", function()
        local first = { name = "duplicate" }
        local second = { name = "duplicate" }
        local root = { children = { first, second } }

        local target, errorMessage = menuAction.ResolveMenuPath(root, "/children/1")

        unitwind:expect(errorMessage).toBe(nil)
        unitwind:expect(target).toBe(second)
    end)

    unitwind:test("ResolveMenuPath rejects malformed pointer escapes", function()
        local root = { children = {} }

        local target, errorMessage = menuAction.ResolveMenuPath(root, "/children~2/0")

        unitwind:expect(target).toBe(nil)
        unitwind:expect(errorMessage ~= nil).toBe(true)
    end)

    unitwind:test("ResolveMenuPath rejects non-canonical child indexes", function()
        local root = { children = { {} } }

        local target, errorMessage = menuAction.ResolveMenuPath(root, "/children/01")

        unitwind:expect(target).toBe(nil)
        unitwind:expect(errorMessage).toBe("menu_path contains an invalid children index.")
    end)

    unitwind:test("ResolveMenuPath rejects tokens outside the children array", function()
        local root = { children = { {} } }

        local target, errorMessage = menuAction.ResolveMenuPath(root, "/parent/0")

        unitwind:expect(target).toBe(nil)
        unitwind:expect(errorMessage).toBe("menu_path may only traverse children arrays.")
    end)

    unitwind:test("ResolveMenuPath rejects indexes out of range", function()
        local root = { children = { {} } }

        local target, errorMessage = menuAction.ResolveMenuPath(root, "/children/5")

        unitwind:expect(target).toBe(nil)
        unitwind:expect(errorMessage).toBe("menu_path points to a missing child.")
    end)

    -- Instance-level validation guards cross-field rules that inputSchema cannot express.
    local instance = menuAction.new({})

    local function HasErrorPath(result, path)
        for _, validationError in ipairs(result.errors) do
            if validationError.path == path then
                return true
            end
        end
        return false
    end

    unitwind:test("Validate rejects specifying more than one selector", function()
        local result = instance:Validate({
            name = "menu-action",
            arguments = {
                action = "mouseClick",
                menu_id = 1,
                menu_path = "/children/0",
            },
        })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "$")).toBe(true)
    end)

    unitwind:test("Validate rejects omitting every selector", function()
        local result = instance:Validate({
            name = "menu-action",
            arguments = {
                action = "mouseClick",
            },
        })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "$")).toBe(true)
    end)

    unitwind:test("Validate surfaces menu_path syntax errors", function()
        local result = instance:Validate({
            name = "menu-action",
            arguments = {
                action = "mouseClick",
                menu_path = "children/0",
            },
        })

        unitwind:expect(result.valid).toBe(false)
        unitwind:expect(HasErrorPath(result, "menu_path")).toBe(true)
    end)

    unitwind:test("Validate accepts a well-formed menu_path", function()
        local result = instance:Validate({
            name = "menu-action",
            arguments = {
                action = "mouseClick",
                menu_path = "/children/0",
            },
        })

        unitwind:expect(result.valid).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
