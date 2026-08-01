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

    local equipment = require("morrowind-mcp.resources.memory.equipment")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.equipment")

    --- Add the validity API exposed by MWSE userdata to a plain-table fixture.
    ---@param value table
    ---@return table
    local function MakeValid(value)
        function value:isValid()
            return true
        end
        return value
    end

    --- Construct a published equipment module and track resource publication calls.
    ---@return MCP.Resources.Memory.Equipment, table
    local function CreateModule()
        local resource = { publishCount = 0 }
        function resource:PublishResource(entry)
            self.publishCount = self.publishCount + 1
            return entry.descriptor.uri
        end
        function resource:UnpublishResource(uri)
            return true
        end
        local manager = {
            GetScope = function(self) return document.Scope(1) end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        local module = equipment.new({ resource = resource, manager = manager })
        module:Publish()
        return module, resource
    end

    --- Read the live entry and return its authoritative cached Memory document.
    ---@param module MCP.Resources.Memory.Equipment
    ---@return MCP.MemoryDocument
    local function ReadDocument(module)
        module.equipmentEntry.handler(module.equipmentEntry.descriptor)
        return module.equipmentEntry.cache.cached_document
    end

    unitwind:test("Equipment Memory reads equipped stacks and reuses the live cache", function()
        local armor = MakeValid({
            id = "iron_cuirass",
            name = "Iron Cuirass",
            objectType = tes3.objectType.armor,
            armorRating = 30,
            armorScalar = 1,
            enchantCapacity = 0,
            isUsableByBeasts = true,
            maxCondition = 800,
            slot = tes3.armorSlot.cuirass,
            slotName = "Cuirass",
            value = 100,
            weight = 30,
            weightClass = tes3.armorWeightClass.medium,
            stolenList = {},
        })
        local ammunition = MakeValid({
            id = "iron_arrow",
            name = "Iron Arrow",
            objectType = tes3.objectType.ammunition,
            enchantCapacity = 0,
            ignoresNormalWeaponResistance = false,
            isSilver = false,
            reach = 1,
            skillId = tes3.skill.marksman,
            slashMax = 0,
            slashMin = 0,
            speed = 1,
            thrustMax = 8,
            thrustMin = 5,
            type = tes3.weaponType.arrow,
            typeName = "Arrow",
            value = 1,
            weight = 0.1,
            stolenList = {},
        })
        local armorData = { condition = 600 }
        local armorStack = { object = armor, itemData = armorData }
        local ammunitionStack = { object = ammunition }
        local playerActor = { equipment = { armorStack, ammunitionStack } }
        local playerReference = { object = playerActor }
        local mobilePlayer = {
            firstPerson = { equipment = {} },
            readiedAmmo = ammunitionStack,
            readiedAmmoCount = 12,
        }

        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(tes3, "mobilePlayer", mobilePlayer)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()
        local firstDocument = ReadDocument(module)

        unitwind:expect(firstDocument.data_type).toBe("equipment_items")
        unitwind:expect(firstDocument.data.available).toBe(true)
        unitwind:expect(firstDocument.data.item_count).toBe(2)
        unitwind:expect(firstDocument.data.items[1].item.id).toBe("iron_cuirass")
        unitwind:expect(firstDocument.data.items[1].itemData.condition).toBe(600)
        unitwind:expect(firstDocument.data.items[1].count).toBe(1)
        unitwind:expect(firstDocument.data.items[2].item.id).toBe("iron_arrow")
        unitwind:expect(firstDocument.data.items[2].count).toBe(12)

        playerActor.equipment = { armorStack }
        local cachedDocument = ReadDocument(module)
        unitwind:expect(cachedDocument).toBe(firstDocument)
        unitwind:expect(cachedDocument.data.item_count).toBe(2)
        unitwind:expect(resource.publishCount).toBe(1)

        module:OnEquipmentChanged({ reference = playerReference })
        unitwind:expect(module.equipmentEntry.cache.dirty).toBe(true)
        unitwind:expect(resource.publishCount).toBe(2)
        local refreshedDocument = ReadDocument(module)
        unitwind:expect(refreshedDocument.data.item_count).toBe(1)
    end)

    unitwind:test("Equipment Memory invalidates only player equipment events and coalesces bursts", function()
        local playerReference = {}
        local mobilePlayer = { firstPerson = { equipment = {} } }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(tes3, "mobilePlayer", mobilePlayer)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()
        ReadDocument(module)
        module:OnEquipmentChanged({ reference = {} })
        module:OnEquipmentChanged({ mobile = {} })
        unitwind:expect(module.equipmentEntry.cache.dirty).toBe(false)

        module:OnEquipmentChanged({ mobile = mobilePlayer })
        unitwind:expect(module.equipmentEntry.cache.dirty).toBe(true)
        local publishCount = resource.publishCount
        module:OnEquipmentChanged({ reference = playerReference })
        unitwind:expect(resource.publishCount).toBe(publishCount)
    end)

    unitwind:test("Equipment Memory is linked under the player index and registers only post-mutation events", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback)
            registered[eventId] = true
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            unregistered[eventId] = true
        end)

        local module = CreateModule()
        local links = module:GetLinksForParent("morrowind://memory/player/index.json")
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(module.parentUri).toBe("morrowind://memory/player/index.json")
        unitwind:expect(links[1].rel).toBe("equipment")
        unitwind:expect(links[1].uri).toBe("morrowind://memory/player/equipment.json")
        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.equipped]).toBe(true)
        unitwind:expect(registered[tes3.event.unequipped]).toBe(true)
        unitwind:expect(registered[tes3.event.equipmentReevaluated] == true).toBe(false)
        unitwind:expect(registered[tes3.event.simulated] == true).toBe(false)
        unitwind:expect(unregistered[tes3.event.equipped]).toBe(true)
        unitwind:expect(unregistered[tes3.event.unequipped]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this