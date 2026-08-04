local input_action = require("morrowind-mcp.util.input_action")

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
