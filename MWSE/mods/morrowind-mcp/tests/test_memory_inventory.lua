local this = {}
---@diagnostic disable: missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
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

    --- Add the validity API exposed by MWSE userdata to a plain-table fixture.
    ---@param value table
    ---@return table
    local function MakeValid(value)
        function value:isValid()
            return true
        end
        return value
    end

    --- Create an inventory with the MWSE contains API used by event guards.
    ---@param stacks tes3itemStack[]
    ---@return tes3inventory
    local function CreateInventory(stacks)
        local value = { items = stacks }
        function value:contains(item, itemData)
            for _, stack in ipairs(self.items) do
                if stack.object == item then
                    if itemData == nil then
                        return true
                    end
                    for _, variable in ipairs(stack.variables or {}) do
                        if variable == itemData then
                            return true
                        end
                    end
                end
            end
            return false
        end
        return value
    end

    --- Make an inventory stack compatible with the normalized iterator.
    ---@param item tes3item
    ---@param count integer
    ---@param variables tes3itemData[]?
    ---@return tes3itemStack
    local function Stack(item, count, variables)
        return { object = item, count = count, variables = variables }
    end

    --- Construct a lightweight published module and track resource publication calls.
    ---@return MCP.Resources.Memory.Inventory, table
    local function CreateModule()
        local resource = { publishCount = 0 }
        function resource:PublishResource(entry)
            self.publishCount = self.publishCount + 1
            return entry.descriptor.uri
        end
        function resource:UnpublishResource(uri)
            return true
        end
        local memory = {
            GetScope = function(self) return document.Scope(1) end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        local module = inventory.new({ resource = resource, manager = memory })
        module:Publish()
        return module, resource
    end

    --- Read the live entry and return its authoritative cached Memory document.
    ---@param module MCP.Resources.Memory.Inventory
    ---@return MCP.MemoryDocument
    local function ReadDocument(module)
        module.inventoryEntry.handler(module.inventoryEntry.descriptor)
        return module.inventoryEntry.cache.cached_document
    end

    --- Prepare a clean cache before testing an event invalidator.
    ---@param module MCP.Resources.Memory.Inventory
    local function MakeCacheClean(module)
        ReadDocument(module)
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
    end

    unitwind:test("Inventory Memory reads current player inventory and reuses the live cache", function()
        local gold = MakeValid({ id = "Gold_001", name = "Gold", canCarry = true, isGold = true, objectType = tes3.objectType.miscItem, stolenList = {} })
        local potion = MakeValid({ id = "p_restore_health_q", name = "Restore Health", canCarry = true, objectType = tes3.objectType.alchemy, effects = {}, stolenList = {} })
        local customPotion = { count = 2, script = { id = "inventory_script" }, soul = { id = "ancestor_ghost" } }
        local playerInventory = CreateInventory({ Stack(gold, 12), Stack(potion, 3, { customPotion }) })
        local playerReference = {}

        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "mobilePlayer", { inventory = playerInventory })
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()
        local firstDocument = ReadDocument(module)
        unitwind:expect(firstDocument.data_type).toBe("inventory_items")
        unitwind:expect(firstDocument.data.gold).toBe(12)
        unitwind:expect(firstDocument.data.item_count).toBe(2)
        unitwind:expect(firstDocument.data.items[1].item.id).toBe(potion.id)
        unitwind:expect(firstDocument.data.items[1].itemData.scriptId).toBe("inventory_script")
        unitwind:expect(firstDocument.data.items[2].count).toBe(1)

        playerInventory.items = { Stack(gold, 18) }
        local cachedDocument = ReadDocument(module)
        unitwind:expect(cachedDocument).toBe(firstDocument)
        unitwind:expect(cachedDocument.data.gold).toBe(12)
        unitwind:expect(resource.publishCount).toBe(1)

        module:OnItemDropped({})
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)
        unitwind:expect(resource.publishCount).toBe(2)
        local refreshedDocument = ReadDocument(module)
        unitwind:expect(refreshedDocument).toBeType("table")
        unitwind:expect(refreshedDocument.data.gold).toBe(18)
        unitwind:expect(refreshedDocument.data.item_count).toBe(0)
    end)

    unitwind:test("Inventory Memory invalidates only guarded player item mutations", function()
        local lockpick = MakeValid({ id = "lockpick", objectType = tes3.objectType.lockpick, stolenList = {} })
        local probe = MakeValid({ id = "probe", objectType = tes3.objectType.probe, stolenList = {} })
        local repairTool = MakeValid({ id = "repair_tool", objectType = tes3.objectType.repairItem, stolenList = {} })
        local armor = MakeValid({ id = "armor", objectType = tes3.objectType.armor, enchantCapacity = 0, stolenList = {} })
        local enchantedWeapon = MakeValid({ id = "enchanted_weapon", objectType = tes3.objectType.weapon, enchantCapacity = 0, stolenList = {} })
        local lockpickData = { count = 1 }
        local probeData = { count = 1 }
        local repairToolData = { count = 1 }
        local armorData = { count = 1 }
        local weaponData = { count = 1 }
        local playerReference = {}
        local playerMobile = {
            inventory = CreateInventory({
                Stack(lockpick, 1, { lockpickData }),
                Stack(probe, 1, { probeData }),
                Stack(repairTool, 1, { repairToolData }),
                Stack(armor, 1, { armorData }),
                Stack(enchantedWeapon, 1, { weaponData }),
            }),
        }

        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "mobilePlayer", playerMobile)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()

        MakeCacheClean(module)
        module:OnActivate({ activator = {} })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnActivate({ activator = playerReference })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)

        MakeCacheClean(module)
        module:OnEnchantChargeUse({ isCast = false, caster = playerReference, item = enchantedWeapon, itemData = weaponData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnEnchantChargeUse({ isCast = true, caster = {}, item = enchantedWeapon, itemData = weaponData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnEnchantChargeUse({ isCast = true, caster = playerReference, item = enchantedWeapon, itemData = weaponData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)

        MakeCacheClean(module)
        module:OnLockPick({ picker = playerMobile, tool = { objectType = tes3.objectType.apparatus }, toolItemData = lockpickData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnLockPick({ picker = playerMobile, tool = lockpick, toolItemData = lockpickData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)

        MakeCacheClean(module)
        module:OnTrapDisarm({ disarmer = playerMobile, tool = lockpick, toolItemData = lockpickData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnTrapDisarm({ disarmer = playerMobile, tool = probe, toolItemData = probeData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)

        MakeCacheClean(module)
        module:OnRepair({ repairer = playerMobile, roll = 50, chance = 50, item = armor, itemData = armorData, tool = repairTool, toolData = repairToolData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnRepair({ repairer = playerMobile, roll = 49, chance = 50, item = armor, itemData = armorData, tool = repairTool, toolData = repairToolData })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)

        MakeCacheClean(module)
        module:OnEnchantedItemCreated({ enchanterReference = {} })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)
        module:OnEnchantedItemCreated({ enchanterReference = playerReference })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)
        unitwind:expect(resource.publishCount > 1).toBe(true)
    end)

    unitwind:test("Inventory Memory coalesces completion events and ignores rejected barter or open pickpocket", function()
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "mobilePlayer", { inventory = CreateInventory({}) })
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()
        MakeCacheClean(module)
        module:OnBarterOffer({ success = false })
        module:OnPickpocket({ item = {} })
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(false)

        module:OnPotionBrewed({})
        unitwind:expect(module.inventoryEntry.cache.dirty).toBe(true)
        local publishCount = resource.publishCount
        module:OnPotionBrewed({})
        module:OnPickpocket({ item = nil })
        module:OnBarterOffer({ success = true })
        unitwind:expect(resource.publishCount).toBe(publishCount)
    end)

    unitwind:test("Inventory Memory skips invalid MWSE object handles", function()
        local invalidObject = {
            isValid = function()
                return false
            end,
        }

        unitwind:expect(inventory.tes3item(invalidObject)).toBe(nil)
        unitwind:expect(inventory.tes3enchantment(invalidObject)).toBe(nil)
        unitwind:expect(inventory.tes3skill(invalidObject)).toBe(nil)
    end)

    unitwind:test("Inventory Memory registers the live invalidation event set", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback)
            registered[eventId] = true
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            unregistered[eventId] = true
        end)

        local module = CreateModule()
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.barterOffer]).toBe(true)
        unitwind:expect(registered[tes3.event.menuEnter]).toBe(true)
        unitwind:expect(registered[tes3.event.activate]).toBe(true)
        unitwind:expect(registered[tes3.event.enchantChargeUse]).toBe(true)
        unitwind:expect(registered[tes3.event.enchantedItemCreateFailed]).toBe(true)
        unitwind:expect(registered[tes3.event.enchantedItemCreated]).toBe(true)
        unitwind:expect(registered[tes3.event.itemDropped]).toBe(true)
        unitwind:expect(registered[tes3.event.pickpocket]).toBe(true)
        unitwind:expect(registered[tes3.event.potionBrewFailed]).toBe(true)
        unitwind:expect(registered[tes3.event.potionBrewed]).toBe(true)
        unitwind:expect(registered[tes3.event.lockPick]).toBe(true)
        unitwind:expect(registered[tes3.event.repair]).toBe(true)
        unitwind:expect(registered[tes3.event.trapDisarm]).toBe(true)
        unitwind:expect(registered[tes3.event.uiActivated] == true).toBe(false)
        unitwind:expect(registered[tes3.event.menuExit] == true).toBe(false)
        unitwind:expect(registered[tes3.event.containerClosed] == true).toBe(false)
        unitwind:expect(unregistered[tes3.event.itemDropped]).toBe(true)
        unitwind:expect(unregistered[tes3.event.trapDisarm]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
