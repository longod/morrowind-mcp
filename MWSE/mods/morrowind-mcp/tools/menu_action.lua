local base = require("morrowind-mcp.core.itool")
local inputvalidator = require("morrowind-mcp.core.inputvalidator")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local ui = require("morrowind-mcp.tes3.ui")

local minMenuNameLength = 1
local maxMenuNameLength = 255
local minMenuPathLength = 1
local maxMenuPathLength = 1024

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
                    "(One selector required) Action to perform on the non-root menu by ID (key name is `id`). Specify exactly one of `menu_id`, `menu_name`, or `menu_path`."
                ),
                menu_name = jsonrpc.StringSchema(
                    "Menu Name",
                    "(One selector required) Action to perform on the non-root menu by name (key name is `name`). Specify exactly one of `menu_id`, `menu_name`, or `menu_path`.",
                    minMenuNameLength,
                    maxMenuNameLength
                ),
                menu_path = jsonrpc.StringSchema(
                    "Menu Path",
                    "(One selector required) Action to perform using a `path` returned by mw-menu-fetch; paths use raw MWSE child indexes, not serialized array positions. Specify exactly one of `menu_id`, `menu_name`, or `menu_path`.",
                    minMenuPathLength,
                    maxMenuPathLength
                ),
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        -- empty is inspect how to use this menu element?
                        tes3.uiEvent.mouseClick,
                        "textInput",
                    },
                    "Action",
                    "Action to perform on the menu."
                ),
                text = jsonrpc.StringSchema(
                    "Text",
                    "(Optional) Text to input if action is `textInput`.",
                    0,
                    1024
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

function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    -- The input schema cannot express these cross-field requirements.
    -- Text input reaches a live UI element, so validate UI-specific reserved characters before Execute mutates it.
    local arguments = params.arguments or {}
    local menu_id = arguments["menu_id"]
    local menu_name = arguments["menu_name"]
    local menu_path = arguments["menu_path"]
    local action = arguments["action"]
    local text = arguments["text"]
    local targetCount = (menu_id ~= nil and 1 or 0) + (menu_name ~= nil and 1 or 0) + (menu_path ~= nil and 1 or 0)
    if targetCount > 1 then
        table.insert(result.errors, {
            path = "$",
            message = "Only one of menu_id, menu_name, or menu_path should be specified.",
        })
        result.valid = false
    elseif targetCount == 0 then
        table.insert(result.errors, {
            path = "$",
            message = "One of menu_id, menu_name, or menu_path should be specified.",
        })
        result.valid = false
    end
    if menu_path ~= nil then
        local validPath, pathError = ui.ValidatePath(menu_path)
        if not validPath then
            table.insert(result.errors, {
                path = "menu_path",
                message = pathError,
            })
            result.valid = false
        end
    end
    if action == "textInput" and text == nil then
        table.insert(result.errors, {
            path = "text",
            message = "Text is required when action is textInput.",
        })
        result.valid = false
    end
    if text ~= nil then
        local textResult = inputvalidator.ValidateSingleLineUiText(text, "text")
        for _, validationError in ipairs(textResult.errors) do
            table.insert(result.errors, validationError)
        end
        result.valid = result.valid and textResult.valid
    end
    return result
end

function this:Execute(arguments, context)
    -- Argument validation already covered schema, cross-field, and text-sink checks; this function handles live UI state.
    local menu_id = arguments["menu_id"]
    local menu_name = arguments["menu_name"]
    local menu_path = arguments["menu_path"]
    local action = arguments["action"]

    local menu = tes3.worldController.menuController.mainRoot
    local target = nil

    -- better distinguish between fineMenu and findChild, but arguments too complex, so just use findChild.

    if menu_id ~= nil then
        self.logger:debug("Searching for menu with ID: %d", menu_id)

        target = menu:findChild(menu_id)
    elseif menu_name ~= nil then
        self.logger:debug("Searching for menu with Name: %s", menu_name)

        target = menu:findChild(menu_name)
    elseif menu_path ~= nil then
        self.logger:debug("Searching for menu with path: %s", menu_path)

        local pathError = nil
        target, pathError = ui.ResolvePath(menu, menu_path)
        if not target then
            local errorContent = jsonrpc.TextContent(pathError or "Menu path could not be resolved.")
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end
    end

    -- Target availability can only be checked against the current UI tree at execution time.
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

    -- possible destory menu after action, so store name and id before action.
    local target_name = target.name
    local target_id = target.id
    self.logger:debug("Performing action %s to menu %s (ID: %d)", action, target_name, target_id)
    -- currently, do triggerEvent then transit to movie mode immediately, morrowind completely stops processing lua scripts until movie mode ends.
    -- TODO use notifications/processing, sent responsse before triggerEvent, patch runtime code or skipping movie mod.
    if action == "textInput" then
        local text = arguments["text"]
        if target.type ~= "textInput" then
            local errorContent = jsonrpc.TextContent("Menu is not a text input.")
            return jsonrpc.CallToolResult(errorContent, nil, true)
        end
        local topLevelMenu = target:getTopLevelMenu()
        target.text = text
        target:triggerEvent(tes3.uiEvent.textUpdated)
        if topLevelMenu and topLevelMenu:isValid() then
            topLevelMenu:updateLayout()
        end
    else
        -- mouseClick
        target:triggerEvent(action)
    end

    return jsonrpc.CallToolResult(
        jsonrpc.TextContent(string.format("Action %s performed to menu %s (ID: %d) successfully.", action, target_name,
            target_id)), nil, false)
end

return this

-- https://mwse.github.io/MWSE/types/tes3uiMenuController/
-- https://mwse.github.io/MWSE/types/tes3uiMenuInputController/
-- nameFormat.text = strings.defaultPotionName
