local this = {}

---@class MCP.Tests.TargetReference
---@field id string
---@field objectType integer
---@field valid boolean
---@field isValid fun(self: MCP.Tests.TargetReference): boolean

---@param id string
---@return MCP.Tests.TargetReference
local function NewReference(id)
    local reference = {
        id = id,
        objectType = tes3.objectType.reference,
        valid = true,
        isValid = function(self)
            return self.valid
        end,
    }
    return reference
end

---@param properties table<string, any>?
---@param name string?
---@param parent tes3uiElement?
---@return tes3uiElement
local function NewElement(properties, name, parent)
    local element = {
        name = name,
        parent = parent,
        properties = properties or {},
        isValid = function()
            return true
        end,
        getPropertyObject = function(self, property, typeCast)
            return self.properties[property]
        end,
        getPropertyInt = function(self, property)
            return self.properties[property]
        end,
    }
    return element --[[@as tes3uiElement]]
end

---Installs event, safe-handle, and input-controller fakes for target history tests.
---@param callback fun(callbacks: table, inputController: table, target: table)
local function WithTargetMocks(callback)
    local originalTarget = package.loaded["morrowind-mcp.util.target"]
    local originalEvent = event
    local originalMakeSafeObjectHandle = tes3.makeSafeObjectHandle
    local originalWorldController = tes3.worldController
    local callbacks = {}
    local inputController = {}

    event = {
        register = function(eventType, handler)
            callbacks[eventType] = handler
        end,
        unregister = function(eventType)
            callbacks[eventType] = nil
        end,
    }
    tes3.makeSafeObjectHandle = function(reference)
        return {
            valid = function()
                return reference.valid
            end,
            getObject = function()
                return reference
            end,
        }
    end
    ---@diagnostic disable: missing-fields, assign-type-mismatch
    tes3.worldController = {
        menuController = {
            inputController = inputController,
        },
    }
    ---@diagnostic enable: missing-fields, assign-type-mismatch
    package.loaded["morrowind-mcp.util.target"] = nil

    local ok, message = pcall(function()
        local target = require("morrowind-mcp.util.target")
        target.RegisterEvent()
        callback(callbacks, inputController, target)
        target.UnregisterEvent()
    end)

    package.loaded["morrowind-mcp.util.target"] = originalTarget
    event = originalEvent
    tes3.makeSafeObjectHandle = originalMakeSafeObjectHandle
    tes3.worldController = originalWorldController

    if not ok then
        error(message)
    end
end

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    unitwind:start("morrowind-mcp.util.target")

    unitwind:test("Crosshair history keeps distinct valid targets in FIFO order", function()
        WithTargetMocks(function(callbacks, inputController, target)
            local changed = callbacks[tes3.event.activationTargetChanged]
            for index = 1, 9 do
                changed({ current = NewReference("ref" .. tostring(index)) })
            end

            local history = target.GetCrosshairHistory()
            unitwind:expect(table.size(history)).toBe(8)
            unitwind:expect(history[1].referenceId).toBe("ref2")
            unitwind:expect(history[8].referenceId).toBe("ref9")
        end)
    end)

    unitwind:test("Crosshair history skips cleared and consecutive duplicate targets", function()
        WithTargetMocks(function(callbacks, inputController, target)
            local changed = callbacks[tes3.event.activationTargetChanged]
            local reference = NewReference("crate")
            changed({ current = reference })
            changed({ current = reference })
            changed({ current = nil })

            local history = target.GetCrosshairHistory()
            unitwind:expect(table.size(history)).toBe(1)
            unitwind:expect(target.TryGetLastCrosshairTarget()).toBe(reference)
        end)
    end)

    unitwind:test("Crosshair TryGet returns nil after a stored reference expires", function()
        WithTargetMocks(function(callbacks, inputController, target)
            local changed = callbacks[tes3.event.activationTargetChanged]
            local reference = NewReference("temporary")
            changed({ current = reference })
            reference.valid = false

            unitwind:expect(target.TryGetLastCrosshairTarget()).toBe(nil)
            unitwind:expect(target.GetCrosshairHistory()[1].referenceId).toBe("temporary")
        end)
    end)

    unitwind:test("Hover history ignores UI-only elements and deduplicates repeated game data", function()
        WithTargetMocks(function(callbacks, inputController, target)
            local frame = callbacks[tes3.event.enterFrame]
            inputController.pointerMoveEventSource = NewElement()
            frame({})

            local spell = { id = "fireball" }
            inputController.pointerMoveEventSource = NewElement({ MagicMenu_Spell = spell })
            frame({})
            frame({})

            local history = target.GetHoverHistory()
            unitwind:expect(table.size(history)).toBe(1)
            unitwind:expect(history[1].spellId).toBe(spell.id)
            unitwind:expect(history[1].spell).toBe(nil)
        end)
    end)

    unitwind:test("Hover history records a safe contents reference and clears on load", function()
        WithTargetMocks(function(callbacks, inputController, target)
            local frame = callbacks[tes3.event.enterFrame]
            local contentsRef = NewReference("chest")
            inputController.pointerMoveEventSource = NewElement({ MenuContents_ObjectRefr = contentsRef })
            frame({})

            unitwind:expect(target.TryGetLastHoverContentsRef()).toBe(contentsRef)
            contentsRef.valid = false
            unitwind:expect(target.TryGetLastHoverContentsRef()).toBe(nil)

            callbacks[tes3.event.loaded]({})
            unitwind:expect(table.size(target.GetHoverHistory())).toBe(0)
        end)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
