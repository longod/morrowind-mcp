local input_action = require("morrowind-mcp.util.input_action")

local minPitchDegrees = -89
local maxPitchDegrees = 89

--- Normalize an absolute compass heading so the player-facing API receives its supported range.
---@param yawDegrees number
---@return number
local function NormalizeYawDegrees(yawDegrees)
    return (yawDegrees + 180) % 360 - 180
end

---@class MCP.PlayerController
---@field logger mwseLogger
---@field forwardBinding tes3inputConfig?
---@field isForwarding boolean
local this = {}

--- Create a controller that owns only the synthetic input it starts.
---@return MCP.PlayerController
function this.new()
    local instance = {
        logger = require("morrowind-mcp.logger").Get({ moduleName = "player_controller" }),
        forwardBinding = nil,
        isForwarding = false,
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Point the player's body horizontally at a world-space destination without changing pitch.
---@param destination MCP.PathfindingPosition|tes3vector3
---@return boolean
function this:LookAtHorizontal(destination)
    local player = tes3.player
    if not player or not destination then
        return false
    end

    local dx = destination.x - player.position.x
    local dy = destination.y - player.position.y
    if dx * dx + dy * dy <= 0.000001 then
        return true
    end

    player.facing = math.atan2(dx, dy)
    local mobilePlayer = tes3.mobilePlayer
    local animationController = mobilePlayer and mobilePlayer.animationController or nil
    if animationController then
        -- Pathgrid nodes are ground-level, so keep navigation from pitching the camera down at them.
        local verticalRotation = tes3matrix33.new()
        verticalRotation:toRotationX(0)
        animationController.verticalRotation = verticalRotation
    end
    return true
end

--- Set the player's absolute world-space view angles in degrees.
--- Positive pitch looks upward, while MWSE's vertical rotation stores upward pitch as a negative X rotation.
---@param yawDegrees number
---@param pitchDegrees number
---@return boolean
---@return number? yawDegrees
---@return number? pitchDegrees
function this:SetLookAngles(yawDegrees, pitchDegrees)
    local player = tes3.player
    local mobilePlayer = tes3.mobilePlayer
    local animationController = mobilePlayer and mobilePlayer.animationController or nil
    if not player or not animationController then
        return false, nil, nil
    end

    local normalizedYaw = NormalizeYawDegrees(yawDegrees)
    local clampedPitch = math.clamp(pitchDegrees, minPitchDegrees, maxPitchDegrees)
    player.facing = math.rad(normalizedYaw)

    local verticalRotation = tes3matrix33.new()
    verticalRotation:toRotationX(-math.rad(clampedPitch))
    animationController.verticalRotation = verticalRotation
    return true, normalizedYaw, clampedPitch
end

--- Turn the player toward a world-space point using the player's current eye position as the origin.
---@param destination MCP.PathfindingPosition|tes3vector3
---@return boolean
---@return number? yawDegrees
---@return number? pitchDegrees
function this:LookAtPoint(destination)
    local player = tes3.player
    if not player or not destination then
        return false, nil, nil
    end

    local eyePosition = tes3.getPlayerEyePosition()
    if not eyePosition then
        return false, nil, nil
    end
    local dx = destination.x - eyePosition.x
    local dy = destination.y - eyePosition.y
    local dz = destination.z - eyePosition.z
    local horizontalDistance = math.sqrt(dx * dx + dy * dy)
    if horizontalDistance <= 0.000001 and math.abs(dz) <= 0.000001 then
        return false, nil, nil
    end

    local yawDegrees = math.deg(math.atan2(dx, dy))
    local pitchDegrees = math.deg(math.atan2(dz, horizontalDistance))
    return self:SetLookAngles(yawDegrees, pitchDegrees)
end

--- Begin holding the configured forward action and retain its binding for deterministic cleanup.
---@return boolean
function this:StartForward()
    if self.isForwarding then
        return true
    end

    local binding = tes3.getInputBinding(tes3.keybind.forward)
    if not binding then
        self.logger:warn("Cannot start navigation because the forward action has no binding")
        return false
    end

    local started = nil
    if binding.device == 0 then
        started = input_action.KeyboardPush(binding.code)
    elseif binding.device == 1 then
        started = input_action.MousePush(binding.code)
    else
        self.logger:warn("Cannot start navigation with unsupported forward binding device: %s",
            input_action.GetDeviceName(binding.device))
        return false
    end
    if not started then
        return false
    end

    self.forwardBinding = binding
    self.isForwarding = true
    return true
end

--- Release only the forward action previously held by this controller.
function this:StopForward()
    if not self.isForwarding or not self.forwardBinding then
        self.isForwarding = false
        self.forwardBinding = nil
        return
    end

    local binding = self.forwardBinding ---@cast binding tes3inputConfig
    if binding.device == 0 then
        input_action.KeyboardRelease(binding.code)
    elseif binding.device == 1 then
        input_action.MouseRelease(binding.code)
    end
    self.isForwarding = false
    self.forwardBinding = nil
end

--- Release all synthetic input owned by this controller.
function this:Release()
    self:StopForward()
end

return this
