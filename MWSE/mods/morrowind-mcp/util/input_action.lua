local this = {}
local logger = require("morrowind-mcp.logger").Get({ moduleName = "input_action" })

local defaultMouseHammerIntervalSeconds = 0.2

--- Device IDs follow tes3inputConfig.device values from MWSE bindings.
---@enum MCP.InputAction.DeviceId
local deviceId = {
    keyboard = 0,
    mouse = 1,
    joystick = 2,
    gamepad = 3,
}

---@enum MCP.InputAction.DeviceName
local deviceName = {
    [deviceId.keyboard] = "keyboard",
    [deviceId.mouse] = "mouse",
    [deviceId.joystick] = "joystick",
    [deviceId.gamepad] = "gamepad",
}

---@enum MCP.InputAction.MouseButtonState
local mouseButtonState = {
    up = 0,
    down = 128,
}

-- Active timed operations are tracked by mode+device+code to support replacement and cleanup.
---@type table<string, mwseTimer>
local activeTimedByKey = {}

---@class MCP.InputAction.MouseHammerState
---@field button number
---@field interval_seconds number?
---@field interval_frames integer?
---@field elapsed_seconds number
---@field elapsed_frames integer

---@class MCP.InputAction.MouseHammerOptions
---@field interval_seconds number?
---@field interval_frames integer?

---@type table<number, MCP.InputAction.MouseHammerState>
local activeMouseHammerByButton = {}

local function OnLoaded()
    -- MWSE cancels active timers before loaded, so clear stale registry entries here.
    activeTimedByKey = {}
    activeMouseHammerByButton = {}
end

---@param state MCP.InputAction.MouseHammerState
---@param delta number
local function StepMouseHammerSeconds(state, delta)
    local interval = state.interval_seconds
    if type(interval) ~= "number" or interval <= 0 then
        return
    end

    state.elapsed_seconds = state.elapsed_seconds + delta
    while state.elapsed_seconds >= interval do
        state.elapsed_seconds = state.elapsed_seconds - interval
        local tapOk = this.MouseTap(state.button)
        if not tapOk then
            logger:error("Mouse hammer tap failed: button=%d", state.button)
            return
        end
    end
end

---@param state MCP.InputAction.MouseHammerState
local function StepMouseHammerFrames(state)
    local interval = state.interval_frames
    if type(interval) ~= "number" or interval <= 0 then
        return
    end

    state.elapsed_frames = state.elapsed_frames + 1
    if state.elapsed_frames >= interval then
        state.elapsed_frames = 0
        local tapOk = this.MouseTap(state.button)
        if not tapOk then
            logger:error("Mouse hammer tap failed: button=%d", state.button)
        end
    end
end

---@param e simulateEventData?
local function OnSimulate(e)
    local delta = 0
    if e and type(e.delta) == "number" and e.delta > 0 then
        delta = e.delta
    end

    for _, state in pairs(activeMouseHammerByButton) do
        if state.interval_frames ~= nil then
            StepMouseHammerFrames(state)
        else
            StepMouseHammerSeconds(state, delta)
        end
    end
end

---@private
---@param e simulateEventData?
function this.ProcessMouseHammerSimulate(e)
    OnSimulate(e)
end

--- Build a stable registry key for timed operations.
---@param mode string
---@param device number
---@param code number
---@return string
local function BuildTimerKey(mode, device, code)
    return string.format("%s:%d:%d", mode, device, code)
end

--- Resolve the live input controller from worldController.
--- Returns nil when game state is not ready for synthetic input.
---@return tes3inputController?
local function GetInputController()
    local wc = tes3.worldController
    if wc == nil then
        logger:warn("Input controller is unavailable: worldController is nil")
        return nil
    end
    if wc.inputController == nil then
        logger:warn("Input controller is unavailable: wc.inputController is nil")
        return nil
    end
    return wc.inputController
end

--- Validate direct-input mouse button index.
--- MWSE direct mouse state exposes buttons in range 0..7.
---@param button number
---@return boolean
local function IsValidMouseButton(button)
    if type(button) ~= "number" then
        return false
    end
    if button < 0 or button > 7 then
        return false
    end
    return true
end

--- Cancel an existing timed operation for the same key, if present.
--- Errors are logged and swallowed so cleanup never interrupts callers.
---@param mode string
---@param device number
---@param code number
local function CancelExistingTimer(mode, device, code)
    local key = BuildTimerKey(mode, device, code)
    local existing = activeTimedByKey[key]
    if existing then
        local ok, err = pcall(function()
            existing:cancel()
        end)
        if not ok then
            logger:error("Failed to cancel timer: %s", tostring(err))
        end
        activeTimedByKey[key] = nil
    end
end

--- Start a non-persistent fail-safe timer and register it in the active table.
--- If a previous timer exists for the same operation key, it is canceled first.
---@param mode string
---@param device number
---@param code number
---@param timeout_seconds number
---@param callback fun()
---@return boolean?
local function StartFailSafeTimer(mode, device, code, timeout_seconds, callback)
    if type(timeout_seconds) ~= "number" or timeout_seconds <= 0 then
        logger:warn("Failed to start fail-safe timer: timeout_seconds must be a positive number")
        return nil
    end
    if timer == nil or type(timer.start) ~= "function" then
        logger:warn("Failed to start fail-safe timer: timer.start is unavailable")
        return nil
    end

    CancelExistingTimer(mode, device, code)

    local key = BuildTimerKey(mode, device, code)
    local ok, timerInstanceOrError = pcall(function()
        return timer.start({
            type = timer.real,
            duration = timeout_seconds,
            persist = false,
            callback = function()
                activeTimedByKey[key] = nil
                local callbackOk, callbackErr = pcall(callback)
                if not callbackOk then
                    logger:error("Timed cleanup callback failed: %s", tostring(callbackErr))
                end
            end,
        })
    end)

    if not ok then
        logger:error("Failed to start fail-safe timer: %s", tostring(timerInstanceOrError))
        return nil
    end

    activeTimedByKey[key] = timerInstanceOrError
    return true
end

--- Press a mouse button via direct input state.
---@param button number
---@return boolean?
function this.MousePush(button)
    if not IsValidMouseButton(button) then
        logger:warn("MousePush rejected: button must be in range 0..7")
        return nil
    end

    local inputController = GetInputController()
    if not inputController then
        return nil
    end

    inputController.mouseState.buttons[button] = mouseButtonState.down
    return true
end

--- Release a mouse button via direct input state.
---@param button number
---@return boolean?
function this.MouseRelease(button)
    if not IsValidMouseButton(button) then
        logger:warn("MouseRelease rejected: button must be in range 0..7")
        return nil
    end

    local inputController = GetInputController()
    if not inputController then
        return nil
    end

    inputController.mouseState.buttons[button] = mouseButtonState.up
    return true
end

--- Perform a single mouse click by push+release.
---@param button number
---@return boolean?
function this.MouseTap(button)
    local ok = this.MousePush(button)
    if not ok then
        return nil
    end
    return this.MouseRelease(button)
end

--- Alias for a sustained mouse press to mirror keyboard naming.
---@param button number
---@return boolean?
function this.MouseHold(button)
    return this.MousePush(button)
end

--- Start mouse auto-repeat (hammer) using simulate updates.
--- interval_frames has priority when both interval values are provided.
--- When interval_frames = N, one tap is emitted every N simulate frames.
---@param button number
---@param options MCP.InputAction.MouseHammerOptions?
---@return boolean?
function this.MouseHammer(button, options)
    if not IsValidMouseButton(button) then
        logger:warn("MouseHammer rejected: button must be in range 0..7")
        return nil
    end

    local intervalSeconds = defaultMouseHammerIntervalSeconds
    local intervalFrames = nil

    if options ~= nil then
        if type(options) ~= "table" then
            logger:warn("MouseHammer rejected: options must be a table")
            return nil
        end
        if options.interval_seconds ~= nil then
            if type(options.interval_seconds) ~= "number" or options.interval_seconds <= 0 then
                logger:warn("MouseHammer rejected: interval_seconds must be a positive number")
                return nil
            end
            intervalSeconds = options.interval_seconds
        end
        if options.interval_frames ~= nil then
            if type(options.interval_frames) ~= "number" or options.interval_frames <= 0 then
                logger:warn("MouseHammer rejected: interval_frames must be a positive integer")
                return nil
            end
            intervalFrames = math.floor(options.interval_frames)
        end
    end

    activeMouseHammerByButton[button] = {
        button = button,
        interval_seconds = intervalFrames and nil or intervalSeconds,
        interval_frames = intervalFrames,
        elapsed_seconds = 0,
        elapsed_frames = 0,
    }
    return true
end

--- Stop mouse auto-repeat (hammer) for a button.
---@param button number
---@return boolean?
function this.MouseUnhammer(button)
    if not IsValidMouseButton(button) then
        logger:warn("MouseUnhammer rejected: button must be in range 0..7")
        return nil
    end

    activeMouseHammerByButton[button] = nil
    local _ = this.MouseRelease(button)
    return true
end

--- Start mouse hammer and schedule an automatic stop timer.
---@param button number
---@param timeout_seconds number
---@param options MCP.InputAction.MouseHammerOptions?
---@return boolean?
function this.MouseHammerTimed(button, timeout_seconds, options)
    local hammerOk = this.MouseHammer(button, options)
    if not hammerOk then
        return nil
    end

    local timerOk = StartFailSafeTimer("hammer", deviceId.mouse, button, timeout_seconds, function()
        local unhammerOk = this.MouseUnhammer(button)
        if not unhammerOk then
            -- Timer callback must not raise; log and continue.
            logger:error("Timed mouse unhammer failed")
        end
    end)

    if not timerOk then
        local _ = this.MouseUnhammer(button)
        return nil
    end

    return true
end

--- Press a keyboard key by scan code.
---@param scan_code number
---@return boolean?
function this.KeyboardPush(scan_code)
    if type(scan_code) ~= "number" then
        logger:warn("KeyboardPush rejected: scan_code must be a number")
        return nil
    end
    tes3.pushKey(scan_code)
    return true
end

--- Release a keyboard key by scan code.
---@param scan_code number
---@return boolean?
function this.KeyboardRelease(scan_code)
    if type(scan_code) ~= "number" then
        logger:warn("KeyboardRelease rejected: scan_code must be a number")
        return nil
    end
    tes3.releaseKey(scan_code)
    return true
end

--- Perform a single keyboard tap by scan code.
---@param scan_code number
---@return boolean?
function this.KeyboardTap(scan_code)
    if type(scan_code) ~= "number" then
        logger:warn("KeyboardTap rejected: scan_code must be a number")
        return nil
    end
    tes3.tapKey(scan_code)
    return true
end

--- Start key repeat behavior for a keyboard key.
--- In MGE-XE this is frame/poll-driven and not user-configurable.
--- Effective cadence is one press every 2 input polling updates (roughly every other frame when polling runs once per frame).
---@param scan_code number
---@return boolean?
function this.KeyboardHammer(scan_code)
    if type(scan_code) ~= "number" then
        logger:warn("KeyboardHammer rejected: scan_code must be a number")
        return nil
    end
    tes3.hammerKey(scan_code)
    return true
end

--- Stop key repeat behavior for a keyboard key.
---@param scan_code number
---@return boolean?
function this.KeyboardUnhammer(scan_code)
    if type(scan_code) ~= "number" then
        logger:warn("KeyboardUnhammer rejected: scan_code must be a number")
        return nil
    end
    tes3.unhammerKey(scan_code)
    return true
end

---@param device number
---@return string
function this.GetDeviceName(device)
    return deviceName[device] or "unknown"
end


--- Push a keyboard scan code and schedule an automatic release timer.
---@param scan_code number
---@param timeout_seconds number
---@return boolean?
function this.KeyboardPushTimed(scan_code, timeout_seconds)
    local pushOk = this.KeyboardPush(scan_code)
    if not pushOk then
        return nil
    end

    local timerOk = StartFailSafeTimer("push", deviceId.keyboard, scan_code, timeout_seconds, function()
        local releaseOk = this.KeyboardRelease(scan_code)
        if not releaseOk then
            -- Release failure should be visible in logs but not throw from timer callback.
            logger:error("Timed keyboard release failed")
        end
    end)

    if not timerOk then
        -- Best-effort rollback for the just-started press state.
        local _ = this.KeyboardRelease(scan_code)
        return nil
    end

    return true
end

--- Push a mouse button and schedule an automatic release timer.
---@param button number
---@param timeout_seconds number
---@return boolean?
function this.MousePushTimed(button, timeout_seconds)
    local pushOk = this.MousePush(button)
    if not pushOk then
        return nil
    end

    local timerOk = StartFailSafeTimer("push", deviceId.mouse, button, timeout_seconds, function()
        local releaseOk = this.MouseRelease(button)
        if not releaseOk then
            -- Release failure should be visible in logs but not throw from timer callback.
            logger:error("Timed mouse release failed")
        end
    end)

    if not timerOk then
        -- Best-effort rollback for the just-started press state.
        local _ = this.MouseRelease(button)
        return nil
    end

    return true
end

--- Start keyboard hammer state and schedule an automatic unhammer timer.
---@param scan_code number
---@param timeout_seconds number
---@return boolean?
function this.KeyboardHammerTimed(scan_code, timeout_seconds)
    local hammerOk = this.KeyboardHammer(scan_code)
    if not hammerOk then
        return nil
    end

    local timerOk = StartFailSafeTimer("hammer", deviceId.keyboard, scan_code, timeout_seconds, function()
        local unhammerOk = this.KeyboardUnhammer(scan_code)
        if not unhammerOk then
            -- Timer callback must not raise; log and continue.
            logger:error("Timed keyboard unhammer failed")
        end
    end)

    if not timerOk then
        local _ = this.KeyboardUnhammer(scan_code)
        return nil
    end

    return true
end

--- Return number of currently tracked timed operations.
---@private
---@return integer
function this.GetActiveTimedCount()
    return table.size(activeTimedByKey)
end

--- Cancel and clear all tracked timed operations.
--- Used mainly by tests and shutdown/cleanup paths.
---@private
function this.ClearTimedRegistry()
    for _, timed in pairs(activeTimedByKey) do
        pcall(function()
            timed:cancel()
        end)
    end
    activeTimedByKey = {}
end

--- Register lifecycle handlers for timed input cleanup.
--- This is idempotent and safe to call multiple times.
function this.RegisterEventHandlers()
    event.register(tes3.event.loaded, OnLoaded)
    event.register(tes3.event.simulate, OnSimulate)
end

--- Execute a tap for a resolved input binding.
--- Only keyboard and mouse are supported at this layer.
---@param binding tes3inputConfig?
---@return boolean?
function this.Tap(binding)
    if binding == nil then
        logger:warn("Tap rejected: binding is nil")
        return nil
    end

    local code = binding.code
    local device = binding.device
    if type(code) ~= "number" or type(device) ~= "number" then
        logger:warn("Tap rejected: binding code/device is invalid")
        return nil
    end

    if device == deviceId.keyboard then
        return this.KeyboardTap(code)
    end
    if device == deviceId.mouse then
        return this.MouseTap(code)
    end
    logger:warn("Tap rejected: unsupported input device=%s", this.GetDeviceName(device))
    return nil
end

--- Push a binding and schedule an automatic release timer.
--- Timer is non-persistent and replaces any previous timer for the same binding.
--- This wrapper accepts tes3inputConfig and dispatches to device-specific timed APIs.
---@param binding tes3inputConfig?
---@param timeout_seconds number
---@return boolean?
function this.Push(binding, timeout_seconds)
    if binding == nil then
        logger:warn("Push rejected: binding is nil")
        return nil
    end

    local code = binding.code
    local device = binding.device
    if type(code) ~= "number" or type(device) ~= "number" then
        logger:warn("Push rejected: binding code/device is invalid")
        return nil
    end

    if device == deviceId.keyboard then
        return this.KeyboardPushTimed(code, timeout_seconds)
    end
    if device == deviceId.mouse then
        return this.MousePushTimed(code, timeout_seconds)
    end

    logger:warn("Push rejected: unsupported input device=%s", this.GetDeviceName(device))
    return nil
end

--- Start hammer state and schedule an automatic unhammer timer.
--- This wrapper accepts tes3inputConfig and dispatches to device-specific timed APIs.
---@param binding tes3inputConfig?
---@param timeout_seconds number
---@return boolean?
function this.Hammer(binding, timeout_seconds)
    if binding == nil then
        logger:warn("Hammer rejected: binding is nil")
        return nil
    end

    local code = binding.code
    local device = binding.device
    if type(code) ~= "number" or type(device) ~= "number" then
        logger:warn("Hammer rejected: binding code/device is invalid")
        return nil
    end

    if device == deviceId.keyboard then
        return this.KeyboardHammerTimed(code, timeout_seconds)
    end
    if device == deviceId.mouse then
        return this.MouseHammerTimed(code, timeout_seconds)
    end

    logger:warn("Hammer rejected: unsupported input device=%s", this.GetDeviceName(device))
    return nil
end

--- Cancel a tracked timed operation by mode and binding identity.
---@private
---@param mode string
---@param binding tes3inputConfig?
---@return boolean?
function this.CancelTimedBinding(mode, binding)
    if type(mode) ~= "string" or mode == "" then
        logger:warn("Cancel rejected: mode must be a non-empty string")
        return nil
    end
    if binding == nil then
        logger:warn("Cancel rejected: binding is nil")
        return nil
    end
    if type(binding.code) ~= "number" or type(binding.device) ~= "number" then
        logger:warn("Cancel rejected: binding code/device is invalid")
        return nil
    end

    CancelExistingTimer(mode, binding.device, binding.code)
    return true
end

--- Cancel a timed push operation for a binding.
---@param binding tes3inputConfig?
---@return boolean?
function this.CancelPush(binding)
    return this.CancelTimedBinding("push", binding)
end

--- Cancel a timed hammer operation for a binding.
---@param binding tes3inputConfig?
---@return boolean?
function this.CancelHammer(binding)
    return this.CancelTimedBinding("hammer", binding)
end

return this
