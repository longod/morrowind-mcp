local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local inputAction = require("morrowind-mcp.util.input_action")

    unitwind:start("morrowind-mcp.util.input_action")

    unitwind:test("MousePush and MouseRelease update direct mouse state", function()
        local mouseButtons = {}
        local inputController = {
            mouseState = {
                buttons = mouseButtons,
            },
        }

        local originalWorldController = tes3.worldController
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        tes3.worldController = {
            inputController = inputController,
        }

        local pushOk = inputAction.MousePush(0)
        local releaseOk = inputAction.MouseRelease(0)

        tes3.worldController = originalWorldController

        unitwind:expect(pushOk).toBe(true)
        unitwind:expect(mouseButtons[1]).toBe(0)
        unitwind:expect(releaseOk).toBe(true)
    end)

    unitwind:test("MousePush rejects out-of-range button", function()
        local ok = inputAction.MousePush(8)
        unitwind:expect(ok).toBe(nil)
    end)

    unitwind:test("MouseTap keeps button down until timed release callback", function()
        local mouseButtons = {}
        local inputController = {
            mouseState = {
                buttons = mouseButtons,
            },
        }
        local callbackRef = nil

        local originalWorldController = tes3.worldController
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        tes3.worldController = {
            inputController = inputController,
        }

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                callbackRef = params.callback
                return {
                    cancel = function()
                    end,
                }
            end,
        }

        inputAction.ClearTimedRegistry()
        local tapOk = inputAction.MouseTap(1)

        unitwind:expect(tapOk).toBe(true)
        unitwind:expect(mouseButtons[2]).toBe(128)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(1)

        if callbackRef then
            callbackRef({})
        end

        unitwind:expect(mouseButtons[2]).toBe(0)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(0)

        timer = originalTimer
        tes3.worldController = originalWorldController
    end)

    unitwind:test("Tap uses keyboard tap for keyboard device", function()
        local tappedCode = nil
        unitwind:mock(tes3, "tapKey", function(scanCode)
            tappedCode = scanCode
        end)

        local ok = inputAction.Tap({
            device = 0,
            code = 32,
        })

        unitwind:unmock(tes3, "tapKey")

        unitwind:expect(ok).toBe(true)
        unitwind:expect(tappedCode).toBe(32)
    end)

    unitwind:test("Push schedules non-persistent timer and releases on callback", function()
        local pushedCode = nil
        local releasedCode = nil
        local capturedPersist = nil
        local capturedDuration = nil
        local callbackRef = nil

        unitwind:mock(tes3, "pushKey", function(scanCode)
            pushedCode = scanCode
        end)
        unitwind:mock(tes3, "releaseKey", function(scanCode)
            releasedCode = scanCode
        end)

        local originalTimer = timer
        -- Replacing the global timer table avoids flaky behavior we observed with repeated timer.start field mocks.
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                capturedPersist = params.persist
                capturedDuration = params.duration
                callbackRef = params.callback
                return {
                    cancel = function()
                    end,
                }
            end,
        }

        inputAction.ClearTimedRegistry()
        local ok = inputAction.Push({
            device = 0,
            code = 17,
        }, 0.25)

        unitwind:expect(ok).toBe(true)
        unitwind:expect(pushedCode).toBe(17)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(1)
        unitwind:expect(capturedPersist).toBe(false)
        unitwind:expect(capturedDuration).toBe(0.25)

        if callbackRef then
            callbackRef({})
        end

        timer = originalTimer
        unitwind:unmock(tes3, "pushKey")
        unitwind:unmock(tes3, "releaseKey")

        unitwind:expect(releasedCode).toBe(17)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(0)
    end)

    unitwind:test("MousePushTimed schedules non-persistent timer and releases mouse state", function()
        local mouseButtons = {}
        local inputController = {
            mouseState = {
                buttons = mouseButtons,
            },
        }
        local callbackRef = nil

        local originalWorldController = tes3.worldController
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        tes3.worldController = {
            inputController = inputController,
        }

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                callbackRef = params.callback
                return {
                    cancel = function()
                    end,
                }
            end,
        }

        inputAction.ClearTimedRegistry()
        local ok = inputAction.MousePushTimed(1, 0.15)

        unitwind:expect(ok).toBe(true)
        unitwind:expect(mouseButtons[2]).toBe(128)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(1)

        if callbackRef then
            callbackRef({})
        end

        unitwind:expect(mouseButtons[2]).toBe(0)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(0)

        timer = originalTimer
        tes3.worldController = originalWorldController
    end)

    unitwind:test("Push rollbacks pressed state when timer start fails", function()
        local pushedCode = nil
        local releasedCode = nil

        unitwind:mock(tes3, "pushKey", function(scanCode)
            pushedCode = scanCode
        end)
        unitwind:mock(tes3, "releaseKey", function(scanCode)
            releasedCode = scanCode
        end)

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                error("timer failed")
            end,
        }

        inputAction.ClearTimedRegistry()
        local ok = inputAction.Push({
            device = 0,
            code = 18,
        }, 0.25)

        timer = originalTimer
        unitwind:unmock(tes3, "pushKey")
        unitwind:unmock(tes3, "releaseKey")

        unitwind:expect(ok).toBe(nil)
        unitwind:expect(pushedCode).toBe(18)
        unitwind:expect(releasedCode).toBe(18)
        unitwind:expect(inputAction.GetActiveTimedCount()).toBe(0)
    end)

    unitwind:test("Push cancels previous timer for same binding", function()
        local cancelCount = 0
        local timerStartCount = 0

        unitwind:mock(tes3, "pushKey", function(scanCode)
        end)
        unitwind:mock(tes3, "releaseKey", function(scanCode)
        end)

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                timerStartCount = timerStartCount + 1
                return {
                    cancel = function()
                        cancelCount = cancelCount + 1
                    end,
                }
            end,
        }

        inputAction.ClearTimedRegistry()
        local firstOk = inputAction.Push({ device = 0, code = 19 }, 0.2)
        local secondOk = inputAction.Push({ device = 0, code = 19 }, 0.2)

        timer = originalTimer
        unitwind:unmock(tes3, "pushKey")
        unitwind:unmock(tes3, "releaseKey")

        unitwind:expect(firstOk).toBe(true)
        unitwind:expect(secondOk).toBe(true)
        unitwind:expect(timerStartCount).toBe(2)
        unitwind:expect(cancelCount).toBe(1)

        inputAction.ClearTimedRegistry()
    end)

    unitwind:test("CancelPush cancels scheduled push timer", function()
        local cancelCount = 0

        unitwind:mock(tes3, "pushKey", function(scanCode)
        end)
        unitwind:mock(tes3, "releaseKey", function(scanCode)
        end)

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                return {
                    cancel = function()
                        cancelCount = cancelCount + 1
                    end,
                }
            end,
        }

        inputAction.ClearTimedRegistry()
        local pushOk = inputAction.Push({ device = 0, code = 20 }, 0.2)
        local cancelOk = inputAction.CancelPush({ device = 0, code = 20 })

        timer = originalTimer
        unitwind:unmock(tes3, "pushKey")
        unitwind:unmock(tes3, "releaseKey")

        unitwind:expect(pushOk).toBe(true)
        unitwind:expect(cancelOk).toBe(true)
        unitwind:expect(cancelCount).toBe(1)
    end)

    unitwind:test("MouseHammerTimed schedules timer and unhammer callback", function()
        local unhammerCount = 0
        local callbackRef = nil

        unitwind:mock(inputAction, "MouseHammer", function(button, options)
            return true
        end)
        unitwind:mock(inputAction, "MouseUnhammer", function(button)
            unhammerCount = unhammerCount + 1
            return true
        end)

        local originalTimer = timer
        ---@diagnostic disable-next-line: assign-type-mismatch
        timer = {
            real = 1,
            start = function(params)
                callbackRef = params.callback
                return {
                    cancel = function()
                    end,
                }
            end,
        }

        local ok = inputAction.MouseHammerTimed(0, 0.25)
        if callbackRef then
            callbackRef({})
        end

        timer = originalTimer
        unitwind:unmock(inputAction, "MouseHammer")
        unitwind:unmock(inputAction, "MouseUnhammer")

        unitwind:expect(ok).toBe(true)
        unitwind:expect(unhammerCount).toBe(1)
    end)

    unitwind:test("Hammer uses mouse timed hammer for mouse binding", function()
        local calledButton = nil
        local calledTimeout = nil

        unitwind:mock(inputAction, "MouseHammerTimed", function(button, timeoutSeconds)
            calledButton = button
            calledTimeout = timeoutSeconds
            return true
        end)

        local ok = inputAction.Hammer({
            device = 1,
            code = 2,
        }, 0.4)

        unitwind:unmock(inputAction, "MouseHammerTimed")

        unitwind:expect(ok).toBe(true)
        unitwind:expect(calledButton).toBe(2)
        unitwind:expect(calledTimeout).toBe(0.4)
    end)

    unitwind:test("MouseHammer with interval_seconds alternates push and release", function()
        local pushCount = 0
        local releaseCount = 0

        unitwind:mock(inputAction, "MousePush", function(button)
            pushCount = pushCount + 1
            return true
        end)
        unitwind:mock(inputAction, "MouseRelease", function(button)
            releaseCount = releaseCount + 1
            return true
        end)

        local hammerOk = inputAction.MouseHammer(0, { interval_seconds = 0.1 })
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        inputAction.ProcessMouseHammerSimulate({ delta = 0.09 })
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        inputAction.ProcessMouseHammerSimulate({ delta = 0.02 })
        local unhammerOk = inputAction.MouseUnhammer(0)

        unitwind:unmock(inputAction, "MousePush")
        unitwind:unmock(inputAction, "MouseRelease")

        unitwind:expect(hammerOk).toBe(true)
        unitwind:expect(unhammerOk).toBe(true)
        unitwind:expect(pushCount).toBe(1)
        unitwind:expect(releaseCount).toBe(1)
    end)

    unitwind:test("MouseHammer with interval_frames alternates state on frame cadence", function()
        local pushCount = 0
        local releaseCount = 0

        unitwind:mock(inputAction, "MousePush", function(button)
            pushCount = pushCount + 1
            return true
        end)
        unitwind:mock(inputAction, "MouseRelease", function(button)
            releaseCount = releaseCount + 1
            return true
        end)

        local hammerOk = inputAction.MouseHammer(1, { interval_frames = 2 })
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        inputAction.ProcessMouseHammerSimulate({ delta = 0.5 })
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        inputAction.ProcessMouseHammerSimulate({ delta = 0.5 })
        ---@diagnostic disable-next-line: missing-fields, assign-type-mismatch
        inputAction.ProcessMouseHammerSimulate({ delta = 0.5 })
        local unhammerOk = inputAction.MouseUnhammer(1)

        unitwind:unmock(inputAction, "MousePush")
        unitwind:unmock(inputAction, "MouseRelease")

        unitwind:expect(hammerOk).toBe(true)
        unitwind:expect(unhammerOk).toBe(true)
        unitwind:expect(pushCount).toBe(1)
        unitwind:expect(releaseCount).toBe(1)
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
