local this = {}

---@diagnostic disable: need-check-nil

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    local serializerModule = require("morrowind-mcp.tes3.object_summary")

    unitwind:start("morrowind-mcp.tes3.object_summary")

    unitwind:test("Exposes every registered TES3 serializer extension point", function()
        local serializer = serializerModule.new()
        for _, methodName in ipairs(serializerModule.supportedMethods) do
            unitwind:expect(type(serializer[methodName])).toBe("function")
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

        unitwind:expect(result.lock.locked).toBe(true)
        unitwind:expect(result.lock.level).toBe(50)
        unitwind:expect(result.destination.cell.id).toBe("Seyda Neen")
    end)

    unitwind:test("Metadata advertises all selectable serialization levels", function()
        local metadata = serializerModule.new({ detailLevel = "standard" }):GetMetadata()

        unitwind:expect(metadata.detailLevel).toBe("standard")
        unitwind:expect(metadata.availableDetailLevels[1]).toBe("minimal")
        unitwind:expect(metadata.availableDetailLevels[3]).toBe("full")
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
