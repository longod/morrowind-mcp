local this = {}

---@diagnostic disable: need-check-nil, missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local serializerModule = require("morrowind-mcp.tes3.object_summary")
    local object = require("morrowind-mcp.tes3.object")

    unitwind:start("morrowind-mcp.tes3.object_summary")
    unitwind.afterEach = function()
        unitwind:clearSpies()
        unitwind:clearMocks()
    end

    unitwind:test("Exposes every registered TES3 serializer extension point", function()
        local serializer = serializerModule.new()
        for _, methodName in ipairs(serializerModule.supportedMethods) do
            unitwind:expect(type(serializer[methodName])).toBe("function")
        end
    end)

    unitwind:test("Tracks every public object serializer", function()
        local registered = {}
        for _, methodName in ipairs(serializerModule.supportedMethods) do
            registered[methodName] = true
            unitwind:expect(type(object[methodName])).toBe("function")
        end
        for methodName, method in pairs(object) do
            if type(method) == "function" and methodName:match("^tes3") then
                unitwind:expect(registered[methodName]).toBe(true)
            end
        end
    end)

    unitwind:test("Minimal reference identifies the placed base object", function()
        local cell = {
            id = "Balmora",
            objectType = tes3.objectType.cell,
            isValid = function() return true end,
            displayName = "Balmora",
            name = "Balmora",
            isInterior = false,
            gridX = -3,
            gridY = -2,
        }
        local door = {
            id = "BalmoraDoor",
            objectType = tes3.objectType.door,
            isValid = function() return true end,
            name = "Wooden Door",
        }
        local reference = {
            id = "BalmoraDoorRef",
            objectType = tes3.objectType.reference,
            isValid = function() return true end,
            baseObject = door,
            cell = cell,
            position = { x = 10, y = 20, z = 30 },
            supportsActivate = true,
            stackSize = 1,
        }

        local result = serializerModule.new({ detailLevel = "minimal" }):Reference(reference)

        unitwind:expect(result.type).toBe("door")
        unitwind:expect(result.name).toBe("Wooden Door")
        unitwind:expect(result.cell.id).toBe("Balmora")
        unitwind:expect(result.destination).toBe(nil)
    end)

    unitwind:test("Standard reference includes lock and destination state", function()
        local cell = {
            id = "Seyda Neen",
            objectType = tes3.objectType.cell,
            isValid = function() return true end,
            displayName = "Seyda Neen",
            name = "Seyda Neen",
            isInterior = false,
            gridX = 0,
            gridY = 0,
        }
        local door = {
            id = "Door",
            objectType = tes3.objectType.door,
            isValid = function() return true end,
            name = "Door",
        }
        local reference = {
            id = "DoorRef",
            objectType = tes3.objectType.reference,
            isValid = function() return true end,
            baseObject = door,
            cell = cell,
            position = { x = 0, y = 0, z = 0 },
            lockNode = { locked = true, level = 50 },
            destination = { cell = cell },
        }

        local result = serializerModule.new({ detailLevel = "standard" }):Reference(reference)

        unitwind:expect(result.lockNode.locked).toBe(true)
        unitwind:expect(result.lockNode.level).toBe(50)
        unitwind:expect(result.destination.cell.id).toBe("Seyda Neen")
    end)

    unitwind:test("Full object serializer includes reference item and lock state", function()
        local reference = {
            id = "DoorRef",
            objectType = tes3.objectType.reference,
            isValid = function() return true end,
            position = { x = 0, y = 0, z = 0 },
            lockNode = { locked = true, level = 50 },
            itemData = { count = 1 },
        }

        local result = object.tes3reference(reference)

        unitwind:expect(result.lockNode.locked).toBe(true)
        unitwind:expect(result.itemData.count).toBe(1)
    end)

    unitwind:test("Metadata advertises all selectable serialization levels", function()
        local metadata = serializerModule.new({ detailLevel = "standard" }):GetMetadata()

        unitwind:expect(metadata.detailLevel).toBe("standard")
        unitwind:expect(metadata.availableDetailLevels[1]).toBe("minimal")
        unitwind:expect(metadata.availableDetailLevels[3]).toBe("full")
    end)

    unitwind:test("Standard alchemy effects are JSON-safe summaries", function()
        local alchemy = {
            id = "p_restore_health_s",
            objectType = tes3.objectType.alchemy,
            isValid = function() return true end,
            name = "Restore Health",
            value = 25,
            weight = 0.5,
            effects = {
                { id = tes3.effect.restoreHealth, rangeType = tes3.effectRange.self, radius = 10, duration = 1, min = 1, max = 1 },
            },
        }

        local result = serializerModule.new({ detailLevel = "standard" }):tes3alchemy(alchemy)

        unitwind:expect(type(result.effects)).toBe("table")
        unitwind:expect(type(result.effects[1])).toBe("table")
        unitwind:expect(result.effects[1].radius).toBe(10)
        unitwind:expect(result.effects[1].duration).toBe(1)
    end)

    unitwind:test("Standard item summaries retain common value and weight", function()
        local function Item(objectType)
            return {
                id = "item",
                objectType = objectType,
                isValid = function() return true end,
                value = 10,
                weight = 2,
            }
        end
        local serializer = serializerModule.new({ detailLevel = "standard" })

        local weapon = serializer:tes3weapon(Item(tes3.objectType.weapon))
        local armor = serializer:tes3armor(Item(tes3.objectType.armor))
        local clothing = serializer:tes3clothing(Item(tes3.objectType.clothing))

        unitwind:expect(weapon.value).toBe(10)
        unitwind:expect(weapon.weight).toBe(2)
        unitwind:expect(armor.value).toBe(10)
        unitwind:expect(armor.weight).toBe(2)
        unitwind:expect(clothing.value).toBe(10)
        unitwind:expect(clothing.weight).toBe(2)
    end)

    unitwind:test("Standard object summaries include location marker state", function()
        local marker = {
            id = "TravelMarker",
            objectType = tes3.objectType.static,
            isValid = function() return true end,
            isLocationMarker = true,
        }
        local nonMarker = {
            id = "Rock",
            objectType = tes3.objectType.static,
            isValid = function() return true end,
            isLocationMarker = false,
        }

        local serializer = serializerModule.new({ detailLevel = "standard" })
        local result = serializer:ObjectSummary(marker)
        local nonMarkerResult = serializer:ObjectSummary(nonMarker)

        unitwind:expect(result.isLocationMarker).toBe(true)
        unitwind:expect(nonMarkerResult.isLocationMarker).toBe(nil)
    end)

    unitwind:test("Direct full serializers delegate to object.lua", function()
        local cell = { id = "Balmora" }
        local expected = { id = "full-cell" }
        unitwind:mock(object, "tes3cell", function(value)
            unitwind:expect(value.id).toBe("Balmora")
            return expected
        end)

        local result = serializerModule.new({ detailLevel = "full" }):tes3cell(cell)

        unitwind:expect(result).toBe(expected)
    unitwind:expect(object.tes3cell).toBeCalled()
    end)

    unitwind:test("Mobile serializers accept nil values", function()
        local serializer = serializerModule.new({ detailLevel = "minimal" })
        unitwind:expect(serializer:tes3mobileActor(nil)).toBe(nil)
        unitwind:expect(serializer:tes3mobileCreature(nil)).toBe(nil)
        unitwind:expect(serializer:tes3mobileNPC(nil)).toBe(nil)
        unitwind:expect(serializer:tes3mobilePlayer(nil)).toBe(nil)
        unitwind:expect(serializer:tes3mobileProjectile(nil)).toBe(nil)
        unitwind:expect(serializer:tes3mobileSpellProjectile(nil)).toBe(nil)
    end)

    unitwind:test("Mobile summaries retain vitals and add named standard statistics", function()
        local cell = {
            id = "Balmora",
            objectType = tes3.objectType.cell,
            isValid = function() return true end,
            isInterior = false,
            gridX = -3,
            gridY = -2,
        }
        local reference = {
            id = "FargothRef",
            isValid = function() return true end,
            baseObject = { id = "Fargoth", objectType = tes3.objectType.npc, isValid = function() return true end, name = "Fargoth" },
            cell = cell,
        }
        local mobile = {
            reference = reference,
            actorType = tes3.actorType.npc,
            health = { current = 25, base = 30 },
            magicka = { current = 15, base = 20 },
            fatigue = { current = 10, base = 40 },
            attributes = {
                { current = 40, base = 40 },
            },
            skills = {
                { current = 25, base = 20, type = tes3.skillType.major },
            },
            inCombat = true,
            isMovingForward = true,
            isRunning = true,
            alwaysRun = true,
        }
        unitwind:mock(tes3, "getAttributeName", function(id)
            unitwind:expect(id).toBe(0)
            return "strength"
        end)
        unitwind:mock(tes3, "getSkillName", function(id)
            unitwind:expect(id).toBe(0)
            return "Block"
        end)

        local minimal = serializerModule.new({ detailLevel = "minimal" }):tes3mobilePlayer(mobile)
        local standard = serializerModule.new({ detailLevel = "standard" }):tes3mobilePlayer(mobile)

        unitwind:expect(minimal.id).toBe("FargothRef")
        unitwind:expect(minimal.health.current).toBe(25)
        unitwind:expect(minimal.attributes).toBe(nil)
        unitwind:expect(standard.actorType).toBe("npc")
        unitwind:expect(standard.health.current).toBe(25)
        unitwind:expect(standard.attributes[1].id).toBe(0)
        unitwind:expect(standard.attributes[1].name).toBe("strength")
        unitwind:expect(standard.skills[1].id).toBe(0)
        unitwind:expect(standard.skills[1].name).toBe("Block")
        unitwind:expect(standard.skills[1].type).toBe("major")
        unitwind:expect(standard.inCombat).toBe(true)
        unitwind:expect(standard.isMoving).toBe(true)
        unitwind:expect(standard.alwaysRun).toBe(true)
    end)

    unitwind:test("Standard spell projectile adds projectile-specific state", function()
        local reference = {
            id = "SpellProjectileRef",
            isValid = function() return true end,
            baseObject = { id = "Projectile", objectType = tes3.objectType.static, isValid = function() return true end },
        }
        local projectile = {
            reference = reference,
            damage = 20,
            expire = 5,
            initialSpeed = 100,
            rotationSpeed = 2,
            spellInstanceSerial = 99,
        }

        local result = serializerModule.new({ detailLevel = "standard" }):tes3mobileSpellProjectile(projectile)

        unitwind:expect(result.damage).toBe(20)
        unitwind:expect(result.expire).toBe(5)
        unitwind:expect(result.initialSpeed).toBe(100)
        unitwind:expect(result.rotationSpeed).toBe(2)
        unitwind:expect(result.spellInstanceSerial).toBe(99)
    end)

    unitwind:test("Debug validation rejects circular JSON output", function()
        local output = {}
        output.self = output

        local ok, message = pcall(function()
            serializerModule.new():Finish("circular", output)
        end)

        unitwind:expect(ok).toBe(false)
        unitwind:expect(message:match("Circular JSON table")).NOT.toBe(nil)
    end)

    unitwind:test("Debug validation rejects unsupported userdata", function()
        local invalidUserdata = newproxy(true)

        local ok, message = pcall(function()
            serializerModule.new():Finish("userdata", { value = invalidUserdata })
        end)

        unitwind:expect(ok).toBe(false)
        unitwind:expect(message:match("Invalid JSON userdata")).NOT.toBe(nil)
    end)

    unitwind:test("References report distance from the serializer origin in game units and meters", function()
        local cell = {
            id = "Balmora",
            objectType = tes3.objectType.cell,
            isValid = function() return true end,
            displayName = "Balmora",
            name = "Balmora",
            isInterior = false,
            gridX = -3,
            gridY = -2,
        }
        local reference = {
            id = "RockRef",
            isValid = function() return true end,
            baseObject = {
                id = "Rock",
                objectType = tes3.objectType.static,
                isValid = function() return true end,
            },
            cell = cell,
            position = { x = 3, y = 4, z = 0 },
        }
        local origin = {
            distance = function(_, position)
                return position.x + position.y + position.z
            end,
        }

        local result = serializerModule.new({ detailLevel = "minimal", origin = origin }):Reference(reference)

        unitwind:expect(result.distance.units).toBe(7)
        unitwind:expect(math.abs(result.distance.meters - (7 * 0.3048 / 22.1)) < 1e-12).toBe(true)
    end)

    unitwind:test("References report an existing traversal cycle", function()
        local reference = { id = "CycleRef", isValid = function() return true end }
        local serializer = serializerModule.new({ detailLevel = "minimal" })
        serializer.stack[reference] = true

        local result = serializer:Reference(reference)

        unitwind:expect(result.circularReference).toBe(true)
        unitwind:expect(result.id).toBe("CycleRef")
    end)

    unitwind:test("Unknown object types fail explicitly", function()
        local ok, message = pcall(function()
            ---@diagnostic disable-next-line: param-type-mismatch
            serializerModule.new():AnyObject({ objectType = -1 })
        end)

        unitwind:expect(ok).toBe(false)
        unitwind:expect(message:match("Unknown TES3 object type")).NOT.toBe(nil)
    end)

    unitwind:test("Property read errors are not suppressed", function()
        local broken = setmetatable({
            id = "broken",
            objectType = tes3.objectType.misc,
            isValid = function() return true end,
        }, {
            __index = function(_, key)
                if key == "name" then
                    error("broken name")
                end
            end,
        })

        local ok, message = pcall(function()
            serializerModule.new():ObjectSummary(broken)
        end)

        unitwind:expect(ok).toBe(false)
        unitwind:expect(message:match("broken name")).NOT.toBe(nil)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
