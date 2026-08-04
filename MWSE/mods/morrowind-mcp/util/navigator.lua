local playerController = require("morrowind-mcp.util.player_controller")

local waypointReachedDistance = 96
local edgeRecoveryDistance = 192
local obstaclePadding = 32
local cancelKeyCode = tes3.scanCode.escape

---@class MCP.NavigatorWaypoint
---@field position MCP.PathfindingPosition
---@field edge MCP.PathfindingEdge?

---@class MCP.NavigatorResult
---@field status "completed"|"cancelled"|"failed"
---@field message string

---@class MCP.NavigatorStartResult
---@field routeNodeCount integer
---@field waypointCount integer

---@class MCP.Navigator
---@field logger mwseLogger
---@field pathfinding MCP.Pathfinding
---@field controller MCP.PlayerController
---@field waypoints MCP.NavigatorWaypoint[]
---@field waypointIndex integer
---@field isActive boolean
---@field result MCP.NavigatorResult?
---@field simulateCallback fun(e: simulateEventData)?
---@field keyDownCallback fun(e: keyDownEventData)?
local this = {}

--- Copy a position so navigation remains valid if the graph is refreshed during movement.
---@param position MCP.PathfindingPosition
---@return MCP.PathfindingPosition
local function CopyPosition(position)
    return { x = position.x, y = position.y, z = position.z }
end

--- Return horizontal distance without allocating temporary vectors.
---@param first MCP.PathfindingPosition|tes3vector3
---@param second MCP.PathfindingPosition|tes3vector3
---@return number
local function HorizontalDistance(first, second)
    local dx = first.x - second.x
    local dy = first.y - second.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Project a point onto an edge segment for the lightweight obstacle recovery target.
---@param point MCP.PathfindingPosition|tes3vector3
---@param first MCP.PathfindingPosition
---@param second MCP.PathfindingPosition
---@return MCP.PathfindingPosition
local function ProjectOntoSegment(point, first, second)
    local dx = second.x - first.x
    local dy = second.y - first.y
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared <= 0.000001 then
        return CopyPosition(first)
    end
    local scale = ((point.x - first.x) * dx + (point.y - first.y) * dy) / lengthSquared
    scale = math.clamp(scale, 0, 1)
    return { x = first.x + dx * scale, y = first.y + dy * scale, z = first.z + (second.z - first.z) * scale }
end

--- Create a navigator that uses a shared pathfinding graph but owns its controller and event handlers.
---@param params { pathfinding: MCP.Pathfinding }
---@return MCP.Navigator
function this.new(params)
    local instance = {
        logger = require("morrowind-mcp.logger").Get({ moduleName = "navigator" }),
        pathfinding = params.pathfinding,
        controller = playerController.new(),
        waypoints = {},
        waypointIndex = 1,
        isActive = false,
        result = nil,
        simulateCallback = nil,
        keyDownCallback = nil,
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Stop navigation and remove every event callback before returning a terminal result.
---@param status "completed"|"cancelled"|"failed"
---@param message string
function this:Finish(status, message)
    if self.simulateCallback then
        event.unregister(tes3.event.simulate, self.simulateCallback)
        self.simulateCallback = nil
    end
    if self.keyDownCallback then
        event.unregister(tes3.event.keyDown, self.keyDownCallback)
        self.keyDownCallback = nil
    end
    self.controller:Release()
    self.isActive = false
    self.result = { status = status, message = message }
    self.logger:info("Navigation %s: %s", status, message)
end

--- Cancel the active route because a caller or the player interrupted it.
---@param message string
function this:Cancel(message)
    if self.isActive then
        self:Finish("cancelled", message)
    end
end

--- Return true when the dedicated local cancel key should stop navigation.
---@param keyCode number
---@return boolean
function this:IsCancelKey(keyCode)
    return keyCode == cancelKeyCode
end

--- Build independent walk-only waypoints from the current graph path.
---@param destination MCP.PathfindingLocator
---@return boolean
---@return string?
---@return MCP.NavigatorStartResult?
function this:Start(destination)
    self:Cancel("replaced by a new navigation request")
    local player = tes3.player
    if not player or not player.cell then
        return false, "Player or current cell is unavailable."
    end

    local path = self.pathfinding:FindPath({ cell = player.cell, position = player.position }, destination)
    if not path then
        self.logger:warn("Navigation start rejected: no path from player position to destination")
        return false, "No pathgrid route is available for the requested destination."
    end

    local waypoints = {}
    for index, nodeId in ipairs(path.nodeIds) do
        local node = self.pathfinding.nodes[nodeId]
        local edge = index > 1 and self.pathfinding.edges[path.edgeIds[index - 1]] or nil
        if edge and edge.kind ~= self.pathfinding.edgeKind.walk then
            self.logger:warn("Navigation start rejected: edgeId=%s requires travel activation", tostring(edge.id))
            return false, "The path requires travel activation, which navigation does not support yet."
        end
        if node then
            table.insert(waypoints, { position = CopyPosition(node.position), edge = edge })
        end
    end
    table.insert(waypoints, { position = CopyPosition(destination.position) })
    if table.size(waypoints) == 0 then
        self.logger:warn("Navigation start rejected: path had no usable waypoints")
        return false, "The path did not contain usable waypoints."
    end

    self.waypoints = waypoints
    self.waypointIndex = 1
    self.result = nil
    self.isActive = true
    self.keyDownCallback = function(e)
        if self:IsCancelKey(e.keyCode) then
            self:Cancel("Cancelled by local Escape key.")
        end
    end
    self.simulateCallback = function(e)
        self:OnSimulate(e)
    end
    event.register(tes3.event.keyDown, self.keyDownCallback, { filter = cancelKeyCode })
    event.register(tes3.event.simulate, self.simulateCallback)
    if not self.controller:StartForward() then
        self:Finish("failed", "Unable to hold the configured forward action.")
        return false, "Unable to hold the configured forward action."
    end
    self.logger:info("Navigation started: startNodeId=%d destinationNodeId=%d waypoints=%d destination=(%.1f, %.1f, %.1f)",
        path.nodeIds[1], path.nodeIds[table.size(path.nodeIds)], table.size(waypoints), destination.position.x,
        destination.position.y, destination.position.z)
    return true, nil, { routeNodeCount = table.size(path.nodeIds), waypointCount = table.size(waypoints) }
end

--- Advance the active route, keeping a horizontal look target and performing one bounded obstacle test.
---@param e simulateEventData
function this:OnSimulate(e)
    if not self.isActive then
        return
    end
    local player = tes3.player
    local waypoint = self.waypoints[self.waypointIndex]
    if not player or not waypoint then
        self:Finish("failed", "Player or waypoint became unavailable.")
        return
    end

    if HorizontalDistance(player.position, waypoint.position) <= waypointReachedDistance then
        self.waypointIndex = self.waypointIndex + 1
        waypoint = self.waypoints[self.waypointIndex]
        if not waypoint then
            self:Finish("completed", "Reached the requested destination.")
            return
        end
    end

    local lookTarget = waypoint.position
    local distance = HorizontalDistance(player.position, waypoint.position)
    if distance > obstaclePadding then
        local rayOrigin = tes3vector3.new(player.position.x, player.position.y,
            (player.position.z + waypoint.position.z) * 0.5)
        local direction = tes3vector3.new(waypoint.position.x - rayOrigin.x, waypoint.position.y - rayOrigin.y, 0)
        local hit = tes3.rayTest({ position = rayOrigin, direction = direction, maxDistance = distance, ignore = { player } })
        if hit and hit.distance and hit.distance < distance - obstaclePadding and waypoint.edge and self.waypointIndex > 1 then
            local previous = self.waypoints[self.waypointIndex - 1]
            local recovery = ProjectOntoSegment(hit.intersection or waypoint.position, previous.position, waypoint.position)
            if HorizontalDistance(player.position, recovery) > edgeRecoveryDistance then
                lookTarget = recovery
            end
        end
    end
    self.controller:LookAtHorizontal(lookTarget)
end

--- Release callbacks and synthetic input when the server discards this navigator.
function this:Release()
    if self.isActive then
        self:Finish("cancelled", "Navigation owner was released.")
    else
        self.controller:Release()
    end
end

return this
