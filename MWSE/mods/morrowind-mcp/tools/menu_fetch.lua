local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local ui = require("morrowind-mcp.tes3.ui")

local minMenuNameLength = 1
local maxMenuNameLength = 255

---@class MCP.Tools.MenuFetch: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.MenuFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.MenuFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "menu_fetch" })

    instance.definition = jsonrpc.Tool({
        name = "menu-fetch",
        description =
        "Fetch current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. some menus have `widget` or `executableEvent` properties to indicate what kind of action can be performed on this menu.",
        inputSchema = jsonrpc.InputSchema(
            {
                menu_id = jsonrpc.NumberSchema(
                    "Menu ID",
                    "Fetch a non-root hierarchy of menu by ID (key name is `id`). If not specified, all menus will be returned. One of `menu_id` or `menu_name` should be specified."
                ),
                menu_name = jsonrpc.StringSchema(
                    "Menu Name",
                    "Fetch a non-root hierarchy of menu by name (key name is `name`). If not specified, all menus will be returned. One of `menu_id` or `menu_name` should be specified.",
                    minMenuNameLength,
                    maxMenuNameLength
                ),
                -- filter?
                -- contain help layer?
                -- depth
                -- show invisible? disabled?
                -- top-most menu
                -- get cursor
                -- get cursor tile
                -- focus element
            }
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                menu = jsonrpc.JsonObjectSchema(),
                help = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
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

    local arguments = params.arguments or {}
    if arguments["menu_id"] ~= nil and arguments["menu_name"] ~= nil then
        table.insert(result.errors, {
            path = "$",
            message = "Only one of menu_id or menu_name should be specified.",
        })
        result.valid = false
    end
    return result
end

function this:Execute(params, context)
    local arguments = params.arguments or {}
    local menu_id = arguments["menu_id"]
    local menu_name = arguments["menu_name"]

    local menu = tes3.worldController.menuController.mainRoot
    local help = tes3.worldController.menuController.helpRoot

    -- better distinguish between fineMenu and findChild, but arguments too complex, so just use findChild.

    if menu_id ~= nil then
        self.logger:debug("Searching for menu with ID: %d", menu_id)

        menu = menu:findChild(menu_id)
        help = help:findChild(menu_id)
    elseif menu_name ~= nil then
        self.logger:debug("Searching for menu with Name: %s", menu_name)

        menu = menu:findChild(menu_name)
        help = help:findChild(menu_name)
    else
        self.logger:debug("No menu_id or menu_name specified. Returning all menus.")
    end

    -- TODO only tes3.getTopMenu() or tes3ui.getMenuOnTop()

    local structuredContent = jsonrpc.object({ menu = ui.tes3uiElement(menu), help = ui.tes3uiElement(help) })
    return jsonrpc.CallToolResult(nil, structuredContent)
end

return this
