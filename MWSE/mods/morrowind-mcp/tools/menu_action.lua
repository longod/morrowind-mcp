local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.Tools.MenuAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.MenuAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.MenuAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "menu_action" })
    instance.definition = jsonrpc.Tool({
        name = "menu-action",
        description =
        "Action to a non-root menu.",
        inputSchema = jsonrpc.InputSchema(
            {
                menu_id = jsonrpc.NumberSchema(
                    "Menu ID",
                    "(Required) Action to perform on the non-root menu by ID (key name is `id`). One of `menu_id` or `menu_name` should be specified."
                ),
                menu_name = jsonrpc.StringSchema(
                    "Menu Name",
                    "(Required) Action to perform on the non-root menu by name (key name is `name`). One of `menu_id` or `menu_name` should be specified.",
                    minMenuNameLength,
                    maxMenuNameLength
                ),
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        -- empty is inspect how to use this menu element?
                        tes3.uiEvent.mouseClick,
                        tes3.uiEvent.mouseDoubleClick,
                    },
                    "Action",
                    "Action to perform on the menu."
                ),
            },
            jsonrpc.array({ "action" }) -- TODO one of id or name. but specification is not exist.
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, false)
    })
    return instance
end

function this:CanExecute(params)
    if not tes3.worldController or not tes3.worldController.menuController then
        return false
    end
    return true
end

function this:Execute(params, context)
    -- TODO validation for injection
    local arguments = params.arguments or {}
    local menu_id = arguments["menu_id"]
    local menu_name = arguments["menu_name"]
    local action = arguments["action"]
    if menu_id ~= nil and menu_name ~= nil then
        local errorContent = jsonrpc.TextContent("Only one of menu_id or menu_name should be specified.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    if type(action) ~= "string" then
        local errorContent = jsonrpc.TextContent("action should be a string.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local menu = tes3.worldController.menuController.mainRoot
    local target = nil

    -- better distinguish between fineMenu and findChild, but arguments too complex, so just use findChild.

    if menu_id ~= nil then
        if type(menu_id) ~= "number" then
            local errorContent = jsonrpc.TextContent("menu_id should be a number.")
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end

        self.logger:debug("Searching for menu with ID: %d", menu_id)

        target = menu:findChild(menu_id)
    elseif menu_name ~= nil then
        if type(menu_name) ~= "string" or #menu_name < minMenuNameLength or #menu_name > maxMenuNameLength then
            local errorContent = jsonrpc.TextContent(string.format(
                "menu_name should be a string with length between %d and %d.", minMenuNameLength, maxMenuNameLength))
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end

        self.logger:debug("Searching for menu with Name: %s", menu_name)

        target = menu:findChild(menu_name)
    else
        return jsonrpc.CallToolResult(jsonrpc.TextContent("One of menu_id or menu_name should be specified."), nil, true)
    end

    -- TODO check if target is valid and can be clicked. (disabled, visible, etc.)
    if not target then
        local errorContent = jsonrpc.TextContent("Menu not found.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    if target.disabled then
        local errorContent = jsonrpc.TextContent("Menu is disabled.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end
    if not target.visible then
        local errorContent = jsonrpc.TextContent("Menu is not visible.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    if not target.consumeMouseEvents then
        local errorContent = jsonrpc.TextContent("Menu does not consume mouse events.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    -- possible destory menu after action, so store name and id before action.
    local target_name = target.name
    local target_id = target.id
    self.logger:debug("Performing action %s to menu %s (ID: %d)", action, target_name, target_id)
    -- FIXME currently, do triggerEvent then transit to movie mode immediately, morrowind completely stops processing lua scripts until movie mode ends.
    -- use notifications/processing, sent responsse before triggerEvent, patch runtime code or skipping movie mod.
    target:triggerEvent(action)

    return jsonrpc.CallToolResult(
        jsonrpc.TextContent(string.format("Action %s performed to menu %s (ID: %d) successfully.", action, target_name,
            target_id)), nil, false)
end

return this

-- https://mwse.github.io/MWSE/types/tes3uiMenuController/
-- https://mwse.github.io/MWSE/types/tes3uiMenuInputController/
-- nameFormat.text = strings.defaultPotionName
