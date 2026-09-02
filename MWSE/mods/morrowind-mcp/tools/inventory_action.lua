local base = require("morrowind-mcp.core.itool")
local availability = require("morrowind-mcp.util.tes3_availability")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local config = require("morrowind-mcp.config")
local ui = require("morrowind-mcp.tes3.ui")
local uiAction = require("morrowind-mcp.util.ui_action")
local inputAction = require("morrowind-mcp.util.input_action")

local sceneInputMinimumSize = 64
local quantityMenuName = "MenuQuantity"

---@class MCP.Tools.InventoryAction: MCP.ITool
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.Tools.InventoryAction
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Tools.InventoryAction
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "inventory_action" })
    instance.definition = jsonrpc.Tool({
        name = "inventory-action",
        description = "Run one diagnostic inventory click-to-place probe. This tool is available only in development debug mode.",
        inputSchema = jsonrpc.InputSchema(
            {
                action = jsonrpc.UntitledSingleSelectEnumSchema(
                    {
                        "select",
                        "equip",
                        "unequip",
                        "transfer",
                        "transfer_all",
                        "offer",
                        "drop",
                    },
                    "Action",
                    "The single inventory operation to attempt through the displayed inventory menus.",
                    nil
                ),
                -- TODO It would be better to include operations that specify an item ID, since `inventory-fetch` does not resolve menu paths. Alternatively, if it can be resolved within the `fetch` method, do so.
                source_menu_path = jsonrpc.StringSchema(
                    "Source Menu Path",
                    "Path of an inventory tile returned by mw-menu-fetch. Required except for transfer_all and offer.",
                    1,
                    1024
                ),
            },
            jsonrpc.array({ "action" })
        ),
        annotations = jsonrpc.ToolAnnotations(nil, false, true)
    })
    return instance
end

function this:GetCapabilityConditions()
    return "Required inventory menus must be displayed. Each attempt performs at most one source click and one destination click without recovery or retry."
end

---@return boolean
---@return MCP.ToolAvailability?
local function MenuInventoryAvailable()
    local menu = tes3ui.findMenu(tes3ui.registerID("MenuInventory"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return false,
            availability.Unavailable(
                availability.reason.menu_unavailable,
                "This is available only when the inventory menu open and is not currently bartering.")
    end
    -- disallow in barter
    menu = tes3ui.findMenu(tes3ui.registerID("MenuBarter"))
    if menu and menu:isValid() and not menu.disabled and menu.visible then
        return false,
            availability.Unavailable(
                availability.reason.menu_unavailable,
                "This is available only when the inventory menu open and is not currently bartering.")
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
local function MenuBarterAvailable()
    local menu = tes3ui.findMenu(tes3ui.registerID("MenuBarter"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return false,
            availability.Unavailable(
                availability.reason.menu_unavailable,
                "This is available only when the barter menu open.")
    end
    return true
end

---@return boolean
---@return MCP.ToolAvailability?
local function MenuContentsAvailable()
    local menu = tes3ui.findMenu(tes3ui.registerID("MenuContents"))
    if not menu or not menu:isValid() or menu.disabled or not menu.visible then
        return false,
            availability.Unavailable(
                availability.reason.menu_unavailable,
                "This is available only when the container menu open.")
    end
    return true
end

--- Selection is observational, so it accepts any pane that can own a live inventory tile.
---@return boolean
---@return MCP.ToolAvailability?
local function AnyInventoryPaneAvailable()
    for _, menuName in ipairs({ "MenuInventory", "MenuContents", "MenuBarter" }) do
        local menu = tes3ui.findMenu(tes3ui.registerID(menuName))
        if menu and menu:isValid() and not menu.disabled and menu.visible then
            return true
        end
    end
    return false,
        availability.Unavailable(
            availability.reason.menu_unavailable,
            "This is available only when an inventory, container, or barter pane is displayed.")
end

---@type table<string, (fun(): boolean, MCP.ToolAvailability?)?>
local testActionHandler = {
    ["select"] = AnyInventoryPaneAvailable,
    ["equip"] = MenuInventoryAvailable,
    ["unequip"] = MenuInventoryAvailable,
    ["transfer"] = MenuContentsAvailable,
    ["transfer_all"] = MenuContentsAvailable,
    ["offer"] = MenuBarterAvailable,
    ["drop"] = MenuInventoryAvailable,
}

--- Requires the live player inventory menu so a probe cannot target a container or barter tile.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return boolean
---@return MCP.ToolAvailability?
function this:CanExecute(arguments, context)
    local ok, reason = availability.PausedInMenuMode()
    if not ok then
        return false, reason
    end
    local action = arguments["action"]
    local handler = testActionHandler[action]
    if handler then
        return handler()
    else
        self.logger:warn("No availability handler for action %s", action)
    end

    return true
end

--- Validates action-dependent path requirements that JSON Schema cannot express.
function this:Validate(params)
    local result = base.Validate(self, params)
    if not result.valid then
        return result
    end

    local arguments = params.arguments or {}
    local sourcePath = arguments["source_menu_path"]
    local action = arguments["action"]
    if action ~= "transfer_all" and action ~= "offer" and sourcePath == nil then
        table.insert(result.errors, {
            path = "source_menu_path",
            message = "source_menu_path is required by the selected action.",
        })
        result.valid = false
        return result
    end

    local validPath, pathError = sourcePath and ui.ValidatePath(sourcePath) or true, nil
    if not validPath then
        table.insert(result.errors, {
            path = "source_menu_path",
            message = pathError,
        })
        result.valid = false
    end
    return result
end

--- Collects curated destinations whose effect states the requested click-to-place operation.
---@param root tes3uiElement
---@param effectName string
---@return tes3uiElement[] destinations
local function FindDestinations(root, effectName)
    local destinations = {}

    local function Visit(element)
        if not element or not element:isValid() then
            return
        end
        for _, effect in ipairs(uiAction.GetActionEffects(element) or {}) do
            if effect.does == effectName then
                table.insert(destinations, element)
                break
            end
        end
        for _, child in ipairs(element.children or {}) do
            Visit(child)
        end
    end

    if not root or not root:isValid() then
        return destinations
    end
    Visit(root)
    return destinations
end

--- Captures one UI element identity before its event handler can rebuild the live UI tree.
---@param element tes3uiElement?
---@return MCP.AnyMap
local function DescribeElement(element)
    return jsonrpc.object({
        path = element and ui.FindPath(tes3.worldController.menuController.mainRoot, element) or nil,
        name = element and element.name or nil,
        id = element and element.id or nil,
        valid = element and element:isValid() or false,
    })
end

--- Runs the vanilla MenuContents Take All handler without selecting an individual source tile.
---@param root tes3uiElement
---@return MCP.CallToolResult
local function ExecuteTransferAll(root)
    local cursorBefore = ui.GetCursorTile(root)
    if cursorBefore then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Transfer all requires an empty cursor."), nil, true)
    end

    local destinations = FindDestinations(root, "transfer_all_from_container")
    if #destinations ~= 1 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("A unique MenuContents Take All button was not available."), jsonrpc.object({
            action = "transfer_all",
            destination_count = #destinations,
            requires_follow_up = true,
        }), true)
    end

    local destination = destinations[1]
    local menu = destination:getTopLevelMenu()
    if destination.disabled or not destination.visible or not menu or menu.name ~= "MenuContents" then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The Take All button must be visible, enabled, and owned by MenuContents."), nil, true)
    end

    local destinationDescription = DescribeElement(destination)
    destination:triggerEvent(tes3.uiEvent.mouseClick)
    return jsonrpc.CallToolResult(jsonrpc.TextContent("Inventory Take All attempt completed; verify later player inventory and menu snapshots."), jsonrpc.object({
        action = "transfer_all",
        cursor_before = cursorBefore,
        destination = destinationDescription,
        cursor_after = ui.GetCursorTile(root),
        expected_postcondition = "menu_contents_closed_and_player_inventory_increased",
        requires_follow_up = true,
    }), false)
end

--- Invokes the vanilla Offer handler once; trade acceptance or refusal is observed in later UI snapshots.
---@param root tes3uiElement
---@return MCP.CallToolResult
local function ExecuteOffer(root)
    local cursorBefore = ui.GetCursorTile(root)
    if cursorBefore then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Offer requires an empty cursor."), nil, true)
    end

    local destinations = FindDestinations(root, "offer_barter")
    if #destinations ~= 1 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("A unique enabled MenuBarter Offer button was not available."), nil, true)
    end

    local offerButton = destinations[1]
    local menu = offerButton:getTopLevelMenu()
    if offerButton.disabled or not offerButton.visible or not menu or menu.name ~= "MenuBarter" then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The Offer button must be visible, enabled, and owned by MenuBarter."), nil, true)
    end

    local offerDescription = DescribeElement(offerButton)
    offerButton:triggerEvent(tes3.uiEvent.mouseClick)
    return jsonrpc.CallToolResult(jsonrpc.TextContent("Barter Offer attempt completed; verify later barter and dialogue snapshots."), jsonrpc.object({
        action = "offer",
        cursor_before = cursorBefore,
        destination = offerDescription,
        expected_postcondition = "vanilla_barter_offer_processed",
        requires_follow_up = true,
    }), false)
end

--- Attempts one same-call scene drop at the center of the largest live UI-free rectangle.
--- The engine consumes direct mouse state after this request returns, so callers must verify later snapshots.
---@param root tes3uiElement
---@param source tes3uiElement
---@param sourceTile tes3inventoryTile
---@return MCP.CallToolResult
local function ExecuteDrop(root, source, sourceTile)
    local cursorBefore = ui.GetCursorTile(root)
    if cursorBefore then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Drop requires an empty cursor."), nil, true)
    end

    local scenePoint, sceneBand = ui.FindSceneInputPoint(root, sceneInputMinimumSize, sceneInputMinimumSize, "bottom")
    if not scenePoint then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("No UI-free scene point large enough for a drop attempt was available."), nil, true)
    end

    local sourceDescription = DescribeElement(source)
    source:triggerEvent(tes3.uiEvent.mouseClick)

    local movement = inputAction.MoveMouseToViewportPosition(scenePoint.x, scenePoint.y)
    -- MouseTap releases on a timer after the engine observes the press.
    if not movement or not inputAction.MouseTap(0) then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("The direct mouse input required for the drop attempt was unavailable."), jsonrpc.object({
            action = "drop",
            source = sourceDescription,
            requires_follow_up = true,
        }), true)
    end

    return jsonrpc.CallToolResult(jsonrpc.TextContent("Inventory scene drop tap initiated; verify later cursor, inventory, and nearby reference snapshots."), jsonrpc.object({
        action = "drop",
        source = sourceDescription,
        source_count = sourceTile.count,
        cursor_before = cursorBefore,
        scene_point = scenePoint,
        scene_band = sceneBand,
        target = jsonrpc.object(movement.target_viewport),
        target_ui = jsonrpc.object(movement.target_ui),
        cursor_input_before = jsonrpc.object(movement.cursor_before),
        mouse_delta = jsonrpc.object(movement.mouse_delta),
        expected_postcondition = "cursor_empty_player_inventory_decreased_by_source_count_and_world_reference_created",
        requires_follow_up = true,
    }), false)
end

--- Reports the live vanilla quantity menu together with the paths needed to drive it from a later call.
---@param root tes3uiElement
---@return MCP.AnyMap
local function DescribeQuantityMenu(root)
    local menu = tes3ui.findMenu(tes3ui.registerID(quantityMenuName))
    if not menu or not menu:isValid() then
        return jsonrpc.object({ present = false })
    end
    local menuPath = ui.FindPath(root, menu)
    return jsonrpc.object({
        present = true,
        visible = menu.visible,
        disabled = menu.disabled,
        path = menuPath,
        actions = ui.CollectActionable(menu, menuPath or ""),
    })
end

--- Clicks one source tile and observes the outcome inside the same call.
--- A later tool call runs in a different frame, so it cannot tell same-frame quantity-menu
--- creation apart from creation on a following frame.
---@param root tes3uiElement
---@param source tes3uiElement
---@param sourceTile tes3inventoryTile
---@return MCP.CallToolResult
local function ExecuteSelect(root, source, sourceTile)
    local sourceDescription = DescribeElement(source)
    local sourceCount = sourceTile.count
    local quantityMenuBefore = DescribeQuantityMenu(root)

    source:triggerEvent(tes3.uiEvent.mouseClick)

    return jsonrpc.CallToolResult(jsonrpc.TextContent("Inventory tile selection completed; the recorded observations describe the frame of the click."), jsonrpc.object({
        action = "select",
        source = sourceDescription,
        source_count = sourceCount,
        quantity_menu_before = quantityMenuBefore,
        cursor_after = ui.GetCursorTile(root),
        quantity_menu_after = DescribeQuantityMenu(root),
        expected_postcondition = "cursor_holds_the_whole_source_stack",
        requires_follow_up = true,
    }), false)
end

--- Performs one validated source click followed immediately by one uniquely identified destination click.
--- Cursor observations are diagnostic only because the click-to-pick state may update after this Lua call.
---@param arguments MCP.AnyMap
---@param context MCP.ToolExecutionContext?
---@return MCP.CallToolResult
function this:Execute(arguments, context)
    local action = arguments["action"]
    local sourcePath = arguments["source_menu_path"]
    local root = tes3.worldController.menuController.mainRoot
    if action == "transfer_all" then
        return ExecuteTransferAll(root)
    end
    if action == "offer" then
        return ExecuteOffer(root)
    end
    local source, sourceError = ui.ResolvePath(root, sourcePath)
    if not source then
        return jsonrpc.CallToolResult(jsonrpc.TextContent(sourceError or "Source menu path could not be resolved."), nil, true)
    end
    if source.disabled or not source.visible then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Source menu tile must be visible and enabled."), nil, true)
    end
    local sourceTile = uiAction.GetInventoryTile(source)
    local sourceMenu = source:getTopLevelMenu()
    if not sourceTile or not sourceMenu then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Source must be a live inventory tile."), nil, true)
    end
    if ui.GetCursorTile(root) then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Inventory action requires an empty cursor."), nil, true)
    end
    if sourceTile.isBoundItem then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Bound inventory items are not supported."), nil, true)
    end
    if sourceTile.isBartered then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Bartered inventory items are not supported."), nil, true)
    end
    if action == "select" then
        return ExecuteSelect(root, source, sourceTile)
    end
    if action == "equip" and sourceTile.isEquipped then
        if sourceMenu.name ~= "MenuInventory" then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Equip requires a player inventory tile."), nil, true)
        end
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Equip requires a non-equipped source tile."), nil, true)
    end
    if action == "unequip" and not sourceTile.isEquipped then
        if sourceMenu.name ~= "MenuInventory" then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Unequip requires a player inventory tile."), nil, true)
        end
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Unequip requires an equipped source tile."), nil, true)
    end
    if action == "transfer" and sourceMenu.name ~= "MenuContents" then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("Transfer currently requires a MenuContents source tile."), nil, true)
    end

    if action == "drop" then
        if sourceMenu.name ~= "MenuInventory" then
            return jsonrpc.CallToolResult(jsonrpc.TextContent("Drop currently requires a player inventory tile."), nil, true)
        end
        return ExecuteDrop(root, source, sourceTile)
    end

    local sourceDescription = DescribeElement(source)
    local cursorBeforeSource = ui.GetCursorTile(root)
    source:triggerEvent(tes3.uiEvent.mouseClick)
    local cursorAfterSource = ui.GetCursorTile(root)

    -- Resolve after the source click because the native handler may reconstruct the menu tree synchronously.
    local destinationEffect = action == "equip" and "equip_cursor_item" or
        (action == "unequip" and "unequip_cursor_item_to_player_inventory" or "place_cursor_item_in_player_inventory")
    local destinations = FindDestinations(root, destinationEffect)
    if #destinations ~= 1 then
        return jsonrpc.CallToolResult(jsonrpc.TextContent("A unique destination was not available after the source click."), jsonrpc.object({
            action = action,
            source = sourceDescription,
            source_count = sourceTile.count,
            cursor_before_source = cursorBeforeSource,
            cursor_after_source = cursorAfterSource,
            destination_count = #destinations,
            requires_follow_up = true,
        }), true)
    end

    local destination = destinations[1]
    local destinationDescription = DescribeElement(destination)
    destination:triggerEvent(tes3.uiEvent.mouseClick)
    return jsonrpc.CallToolResult(jsonrpc.TextContent("Inventory click-to-place attempt completed; verify the later inventory and menu snapshots."), jsonrpc.object({
        action = action,
        source = sourceDescription,
        source_count = sourceTile.count,
        cursor_before_source = cursorBeforeSource,
        cursor_after_source = cursorAfterSource,
        destination = destinationDescription,
        cursor_after_destination = ui.GetCursorTile(root),
        expected_postcondition = action == "transfer" and "player_inventory_count_increased_by_source_count" or nil,
        requires_follow_up = true,
    }), false)
end

return this
