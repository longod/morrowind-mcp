local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local availability = require("morrowind-mcp.util.tes3_availability")
local ui = require("morrowind-mcp.tes3.ui")

--- Selects the player's spell, power, or magic item through the vanilla magic menu.
---@class MCP.Tools.SpellSelect: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.SpellSelect
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.SpellSelect
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "spell_select" })
    instance.definition = jsonrpc.Tool({
        name = "spell-select",
        description = "Select a spell from the player's spells, powers or magic items in the magic menu.",
        inputSchema = jsonrpc.InputSchema({
            category = jsonrpc.UntitledSingleSelectEnumSchema({
                "spell",
                "power",
                "magic_item",
            }, "Category", "Category returned by mw-spell-fetch."),
            id = jsonrpc.StringSchema(
                "ID",
                "Exact ID returned by mw-spell-fetch.",
                1,
                255
            ),
            name = jsonrpc.StringSchema(
                "Name",
                "Exact name returned by mw-spell-fetch.",
                1,
                255
            ),
            menu_path = jsonrpc.StringSchema(
                "Menu Path",
                "Exact MenuMagic element path returned by mw-menu-fetch.",
                1,
                1024
            ),
        }, jsonrpc.array({ "category" })),
        outputSchema = jsonrpc.OutputSchema({
            selected = jsonrpc.JsonObjectSchema(),
        }),
        annotations = jsonrpc.ToolAnnotations(nil, false, false),
    })
    return instance
end


function this:GetCapabilityConditions()
    return "Available only in an active loaded game while in menu mode, when MenuMagic exists, is valid, visible, and enabled."
end

--- Requires a loaded game in menu mode with a live, usable vanilla magic menu.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    local ok, reason = availability.IsInGame()
    if not ok then
        return false, reason
    end

    ok, reason = availability.PausedInMenuMode()
    if not ok then
        return false, availability.WithRelatedTools(reason, {
            {
                name = "mw-spell-fetch",
                relationship = "reports the current player spellbook state.",
            },
            {
                name = "mw-menu-fetch",
                relationship = "reports the current MenuMagic UI state and menu paths.",
            },
        })
    end

    local menu = tes3ui.findMenu(tes3ui.registerID("MenuMagic"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return false, availability.Unavailable(
            availability.reason.menu_unavailable,
            {
                unavailableBecause = "MenuMagic is not visible, valid, and enabled in menu mode.",
                availableWhen = "MenuMagic is visible, valid, and enabled in menu mode.",
                relatedTools = {
                    {
                        name = "mw-spell-fetch",
                        relationship = "reports the current player spellbook state.",
                    },
                    {
                        name = "mw-menu-fetch",
                        relationship = "reports the current MenuMagic UI state and menu paths.",
                    },
                },
            }
        )
    end

    return true
end

--- Validates the identity union because JSON Schema cannot require one member of a set.
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    local arguments = params.arguments or {}
    if arguments["id"] == nil and arguments["name"] == nil and arguments["menu_path"] == nil then
        table.insert(result.errors, {
            path = "$",
            message = "One of id, name, or menu_path is required.",
        })
        result.valid = false
    end
    local menuPath = arguments["menu_path"]
    if menuPath ~= nil then
        local validPath, pathError = ui.ValidatePath(menuPath)
        if not validPath then
            table.insert(result.errors, {
                path = "menu_path",
                message = pathError,
            })
            result.valid = false
        end
    end
    return result
end

--- Reads a vanilla object property without letting a volatile UI element fail the request.
---@param element tes3uiElement
---@param property string
---@param typeCast string?
---@return any?
local function GetPropertyObject(element, property, typeCast)
    if not element or type(element.getPropertyObject) ~= "function" then
        return nil
    end
    local ok, value = pcall(function()
        return typeCast and element:getPropertyObject(property, typeCast) or element:getPropertyObject(property)
    end)
    return ok and value or nil
end

--- Describes a spell or enchanted item attached to a live MenuMagic element.
---@param element tes3uiElement
---@return MCP.AnyMap?
local function DescribeMagicElement(element)
    local spell = GetPropertyObject(element, "MagicMenu_Spell", "tes3spell")
    if spell then
        local category = spell.castType == tes3.spellType.power and "power" or "spell"
        return {
            category = category,
            id = spell.id,
            name = spell.name,
        }
    end

    local item = GetPropertyObject(element, "MagicMenu_object")
    if item and item.enchantment then
        return {
            category = "magic_item",
            id = item.id,
            name = item.name,
        }
    end
    return nil
end

--- Tests every supplied fetch identity against one current MenuMagic element.
---@param candidate MCP.AnyMap
---@param arguments MCP.AnyMap
---@return boolean
local function MatchesIdentity(candidate, arguments)
    return candidate.category == arguments["category"]
        and (arguments["id"] == nil or candidate.id == arguments["id"])
        and (arguments["name"] == nil or candidate.name == arguments["name"])
end

--- Returns whether an element advertises a mouse-click action through the shared action discovery rules.
---@param element tes3uiElement
---@return boolean
local function SupportsMouseClick(element)
    for _, action in ipairs(ui.GetActionProperties(element) or {}) do
        if action == tes3.uiEvent.mouseClick then
            return true
        end
    end
    return false
end

--- Finds the nearest executable row ancestor displaying the requested magic entry without escaping MenuMagic.
---@param element tes3uiElement
---@param menu tes3uiElement
---@param name string
---@return tes3uiElement?
local function FindClickTarget(element, menu, name)
    local current = element
    while current and current:isValid() do
        if SupportsMouseClick(current) and ui.ExtractVisibleText(current) == name then
            return current
        end
        if current == menu then
            break
        end
        current = current.parent
    end
    return nil
end

--- Collects property-bearing MenuMagic elements matching the supplied category and fetch identity.
---@param menu tes3uiElement
---@param arguments MCP.AnyMap
---@return MCP.AnyMap[]
local function FindMatches(menu, arguments)
    local matches = {}
    local root = tes3.worldController.menuController.mainRoot
    local requestedPath = arguments["menu_path"]
    if requestedPath ~= nil then
        local element = ui.ResolvePath(root, requestedPath)
        if element and element:getTopLevelMenu() == menu then
            -- Actionable labels can be children of the vanilla element that retains the magic property.
            local current = element
            while current and current:isValid() do
                local candidate = DescribeMagicElement(current)
                if candidate and MatchesIdentity(candidate, arguments) then
                    candidate.element = element
                    candidate.menu_path = requestedPath
                    table.insert(matches, candidate)
                    break
                end
                if current == menu then
                    break
                end
                current = current.parent
            end
        end
        return matches
    end

    local function Visit(element)
        if not element or not element:isValid() then
            return
        end
        local candidate = DescribeMagicElement(element)
        if candidate and MatchesIdentity(candidate, arguments) then
            candidate.element = element
            candidate.menu_path = ui.FindPath(root, element)
            table.insert(matches, candidate)
        end
        for _, child in ipairs(element.children or {}) do
            Visit(child)
        end
    end
    Visit(menu)
    return matches
end

---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local menu = tes3ui.findMenu(tes3ui.registerID("MenuMagic"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The magic menu is no longer open."), nil, true)
    end

    local propertyMatches = FindMatches(menu, arguments)
    if table.size(propertyMatches) == 0 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("No matching magic-menu entry was found."), nil, true)
    end

    local root = tes3.worldController.menuController.mainRoot
    local matches = {}
    local seenPaths = {}
    for _, candidate in ipairs(propertyMatches) do
        local target = FindClickTarget(candidate.element, menu, candidate.name)
        local targetPath = target and ui.FindPath(root, target)
        -- A vanilla row can expose its magic property on nested elements; it remains one click target.
        if target and targetPath and not seenPaths[targetPath] then
            candidate.target = target
            candidate.target_path = targetPath
            seenPaths[targetPath] = true
            table.insert(matches, candidate)
        end
    end
    if table.size(matches) == 0 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The matching magic-menu entry cannot be clicked."), nil, true)
    end
    if table.size(matches) > 1 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Multiple magic-menu entries matched. Specify menu_path."), nil, true)
    end

    local selected = matches[1]
    selected.target:triggerEvent(tes3.uiEvent.mouseClick)

    return jsonrpc.CallToolResult(nil, jsonrpc.object({
        selected = jsonrpc.object({
            category = selected.category,
            id = selected.id,
            name = selected.name,
            menu_path = selected.target_path,
            operation = "ui_click",
            requires_follow_up = true,
        }),
    }))
end

return this
