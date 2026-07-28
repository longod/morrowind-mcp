local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = false, -- FIXME mock break tes3ui menu when test fails.
        highlight = false,
    })
    -- Restore function spies before mocks so UnitWind does not reapply a mocked function.
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local inventory = require("morrowind-mcp.resources.memory.inventory")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")


    unitwind:start("morrowind-mcp.resources.memory.inventory")

    --- Create a lightweight Memory module with a stable scope and no-op resource publication.
    ---@return MCP.Resources.Memory.Inventory
    local function createModule()
        local resource = {
            PublishResource = function(self, entry) return entry.descriptor.uri end,
            UnpublishResource = function(self, uri) return true end,
        }
        local memory = {
            GetScope = function(self) return document.Scope(1) end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        return inventory.new({ resource = resource, manager = memory })
    end

    --- Make an inventory stack compatible with the normalized iterator.
    ---@param item tes3item
    ---@param count integer
    ---@param variables tes3itemData[]?
    ---@return table
    local function stack(item, count, variables)
        return { object = item, count = count, variables = variables }
    end

    unitwind:test("Inventory Memory captures player stacks and serializes custom data", function()
        local gold = { id = "Gold_001", name = "Gold", canCarry = true }
        local potion = { id = "p_restore_health_q", name = "Restore Health", canCarry = true, mesh = "potion.nif", weight = 0.5 }
        local customPotion = {
            count = 2,
            charge = 17,
            condition = 19,
            timeLeft = 11,
            script = { id = "inventory_script" },
            soul = { id = "ancestor_ghost" },
            data = { unrelated = "mod data" },
        }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        ---@diagnostic disable-next-line: missing-fields
        tes3.mobilePlayer = { inventory = { stack(gold, 12), stack(potion, 3, { customPotion }) } }
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module = createModule()
        module:RefreshSnapshot()
        local memoryDocument = module:BuildInventoryDocument()

        unitwind:expect(memoryDocument.data_type).toBe("inventory_items")
        unitwind:expect(memoryDocument.data.available).toBe(true)
        unitwind:expect(memoryDocument.data.is_current).toBe(true)
        unitwind:expect(memoryDocument.data.gold).toBe(12)
        unitwind:expect(memoryDocument.data.item_count).toBe(2)
        unitwind:expect(memoryDocument.data.items[1].itemData ~= nil).toBe(true)
        unitwind:expect(memoryDocument.data.items[1].count).toBe(2)
        unitwind:expect(memoryDocument.data.items[1].item.id).toBe(potion.id)
        unitwind:expect(memoryDocument.data.items[1].item.name).toBe(potion.name)
        unitwind:expect(memoryDocument.data.items[1].item.mesh == nil).toBe(true)
        unitwind:expect(memoryDocument.data.items[1].itemData.scriptId).toBe("inventory_script")
        unitwind:expect(memoryDocument.data.items[1].itemData.soulId).toBe("ancestor_ghost")
        unitwind:expect(memoryDocument.data.items[1].itemData.data == nil).toBe(true)
        unitwind:expect(memoryDocument.data.items[2].itemData == nil).toBe(true)
        unitwind:expect(memoryDocument.data.items[2].count).toBe(1)
        unitwind:expect(module.snapshot[1].item == potion).toBe(false)
        unitwind:expect(module.snapshot[1].itemData == customPotion).toBe(false)
        tes3.mobilePlayer = nil
    end)

    unitwind:test("Inventory Memory applies successful barter and rejects incomplete sales", function()
        local gold = { id = "Gold_001", name = "Gold", canCarry = true }
        local bread = { id = "ingred_bread_01", name = "Bread", canCarry = true }
        local wine = { id = "potion_comberry_wine_01", name = "Wine", canCarry = true }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        ---@diagnostic disable-next-line: missing-fields
        tes3.mobilePlayer = { inventory = { stack(gold, 10), stack(bread, 4) } }

        local module = createModule()
        module:RefreshSnapshot()
        ---@diagnostic disable-next-line: missing-fields
        module:OnBarterOffer({ success = true, buying = { { item = wine, count = 2 } }, selling = { { item = bread, count = 3 } }, value = -5 })

        unitwind:expect(module.snapshotCurrent).toBe(true)
        unitwind:expect(module.gold).toBe(5)
        unitwind:expect(module.snapshot[1].count).toBe(1)
        unitwind:expect(module.snapshot[2].count).toBe(2)

        ---@diagnostic disable-next-line: missing-fields
        module:OnBarterOffer({ success = false, buying = {}, selling = {}, value = 0 })
        unitwind:expect(module.snapshotCurrent).toBe(true)
        ---@diagnostic disable-next-line: missing-fields
        module:OnBarterOffer({ success = true, buying = {}, selling = { { item = bread, count = 2 } }, value = 0 })
        unitwind:expect(module.snapshotCurrent).toBe(false)
        tes3.mobilePlayer = nil
    end)

    unitwind:test("Inventory Memory indexes serialized standard and custom stacks", function()
        local potion = { id = "p_restore_health_q", name = "Restore Health", canCarry = true }
        local customPotion = { count = 2 }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        ---@diagnostic disable-next-line: missing-fields
        tes3.mobilePlayer = { inventory = { stack(potion, 5, { customPotion }) } }

        local module = createModule()
        module:RefreshSnapshot()
        unitwind:expect(module.snapshotByItemId[potion.id] ~= nil).toBe(true)
        unitwind:expect(table.size(module.snapshotByItemId[potion.id])).toBe(2)
        unitwind:expect(module.snapshot[1].count).toBe(1)
        unitwind:expect(module.snapshot[2].count).toBe(5)
        unitwind:expect(table.size(module.snapshot)).toBe(1)
        unitwind:expect(table.size(module.snapshotByItemId[potion.id])).toBe(1)
        unitwind:expect(module.snapshot[1].itemData == nil).toBe(true)
        unitwind:expect(module.snapshot[1].snapshotIndex).toBe(1)
        tes3.mobilePlayer = nil
    end)

    unitwind:test("Inventory Memory refreshes only at visible inventory UI boundaries", function()
        local gold = { id = "Gold_001", name = "Gold", canCarry = true }
        local menuVisible = true
        local inventoryMenuId = tes3ui.registerID("MenuInventory")
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3ui, "findMenu", function(id)
            if id == inventoryMenuId and menuVisible then
                return { visible = true }
            end
            return nil
        end)
        ---@diagnostic disable-next-line: missing-fields
        tes3.mobilePlayer = { inventory = { stack(gold, 10) } }

        local module = createModule()
    ---@diagnostic disable-next-line: missing-fields
        module:OnInventoryUiActivated({ element = { id = inventoryMenuId } })
        unitwind:expect(module.snapshotAvailable).toBe(true)
        unitwind:expect(module.inventoryMenuWasVisible).toBe(true)

        tes3.mobilePlayer.inventory = { stack(gold, 12) }
        ---@diagnostic disable-next-line: missing-fields
        module:OnMenuEnter({})
        unitwind:expect(module.gold).toBe(12)

        menuVisible = false
        tes3.mobilePlayer.inventory = { stack(gold, 15) }
        ---@diagnostic disable-next-line: missing-fields
        module:OnMenuExit({})
        unitwind:expect(module.gold).toBe(15)
        unitwind:expect(module.inventoryMenuWasVisible).toBe(false)
        tes3.mobilePlayer = nil
    end)

    unitwind:test("Inventory Memory resets stale menu visibility on load", function()
        local gold = { id = "Gold_001", name = "Gold", canCarry = true }
        local inventoryMenuId = tes3ui.registerID("MenuInventory")
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3ui, "findMenu", function(id) return nil end)
        ---@diagnostic disable-next-line: missing-fields
        tes3.mobilePlayer = { inventory = { stack(gold, 10) } }

        local module = createModule()
        local refreshCount = 0
        local refreshSnapshot = module.RefreshSnapshot
        function module:RefreshSnapshot()
            refreshCount = refreshCount + 1
            return refreshSnapshot(self)
        end
        module.inventoryMenuWasVisible = true

        ---@diagnostic disable-next-line: missing-fields
        module:OnLoaded({ newGame = false })
        unitwind:expect(module.inventoryMenuWasVisible).toBe(false)
        unitwind:expect(refreshCount).toBe(1)

        ---@diagnostic disable-next-line: missing-fields
        module:OnMenuExit({})
        unitwind:expect(refreshCount).toBe(1)
        tes3.mobilePlayer = nil
    end)

    unitwind:test("Inventory Memory registers only loaded, barter, and menu boundary handlers", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback)
            registered[eventId] = true
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            unregistered[eventId] = true
        end)

        local module = createModule()
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.barterOffer]).toBe(true)
        unitwind:expect(registered[tes3.event.uiActivated]).toBe(true)
        unitwind:expect(registered[tes3.event.menuEnter]).toBe(true)
        unitwind:expect(registered[tes3.event.menuExit]).toBe(true)
        unitwind:expect(registered[tes3.event.itemTileUpdated] == true).toBe(false)
        unitwind:expect(registered[tes3.event.containerClosed] == true).toBe(false)
        unitwind:expect(unregistered[tes3.event.barterOffer]).toBe(true)
        unitwind:expect(unregistered[tes3.event.menuExit]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
