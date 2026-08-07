local iterator = require("morrowind-mcp.tes3.iterator")

local minimumHeight = 0.000001

---@class MCP.PlayerLookTarget
---@field reference tes3reference
---@field point MCP.PathfindingPosition
---@field pointKind string
local this = {}

--- Copy a world-space point into an ordinary table so callers never mutate an MWSE-owned vector.
---@param point tes3vector3
---@return MCP.PathfindingPosition
local function CopyPoint(point)
    return { x = point.x, y = point.y, z = point.z }
end

--- Return the squared world distance used to make repeated base IDs deterministic.
---@param first tes3vector3
---@param second tes3vector3
---@return number
local function DistanceSquared(first, second)
    local dx = first.x - second.x
    local dy = first.y - second.y
    local dz = first.z - second.z
    return dx * dx + dy * dy + dz * dz
end

--- Find the nearest valid active-cell reference whose base object ID exactly matches the supplied ID.
---@param id string
---@return tes3reference?
function this.FindClosestActiveReference(id)
    local player = tes3.player
    local cells = tes3.getActiveCells()
    if not player or not cells then
        return nil
    end

    local closest = nil
    local closestDistanceSquared = nil
    for _, cell in ipairs(cells) do
        for _, referenceList in ipairs({ cell.activators, cell.actors, cell.statics }) do
            -- ForEachReferenceList expects a non-empty linked list, so skip empty categories before iterating.
            if referenceList and referenceList.size > 0 then
                for reference in iterator.ForEachReferenceList(referenceList) do
                    if reference:isValid() and reference.id == id then
                        local distanceSquared = DistanceSquared(player.position, reference.position)
                        if not closestDistanceSquared or distanceSquared < closestDistanceSquared then
                            closest = reference
                            closestDistanceSquared = distanceSquared
                        end
                    end
                end
            end
        end
    end
    return closest
end

--- Return whether a reference represents an NPC, rather than another actor type such as a creature.
---@param reference tes3reference
---@return boolean
local function IsNpc(reference)
    return reference.object and reference.object.objectType == tes3.objectType.npc
end

--- Return an NPC head-node position when the live animation graph exposes one.
---@param reference tes3reference
---@return MCP.PathfindingPosition?
local function GetNpcHeadNodePoint(reference)
    local animationData = reference.animationData
    local headNode = animationData and animationData.headNode or nil
    local transform = headNode and headNode.worldTransform or nil
    if transform and transform.translation then
        return CopyPoint(transform.translation)
    end

    local manager = reference.bodyPartManager
    local headAttach = manager and manager:getAttachNode(tes3.bodyPartAttachment.head) or nil
    local node = headAttach and headAttach.node or nil
    transform = node and node.worldTransform or nil
    if transform and transform.translation then
        return CopyPoint(transform.translation)
    end
    return nil
end

--- Estimate an NPC eye height from the current player's eye-to-height ratio when no head node is loaded.
---@param reference tes3reference
---@return MCP.PathfindingPosition?
local function GetNpcEstimatedEyePoint(reference)
    local player = tes3.player
    local mobilePlayer = tes3.mobilePlayer
    local targetMobile = reference.mobile
    local eyePosition = tes3.getPlayerEyePosition()
    if not player or not mobilePlayer or not targetMobile or not eyePosition then
        return nil
    end
    if mobilePlayer.height <= minimumHeight or targetMobile.height <= minimumHeight then
        return nil
    end

    local eyeHeightRatio = math.clamp((eyePosition.z - player.position.z) / mobilePlayer.height, 0, 1)
    return {
        x = reference.position.x,
        y = reference.position.y,
        z = reference.position.z + targetMobile.height * eyeHeightRatio,
    }
end

--- Build the best available world-space point for looking at a reference.
---@param reference tes3reference
---@return MCP.PathfindingPosition
---@return string
function this.GetReferenceLookPoint(reference)
    if IsNpc(reference) then
        local headPoint = GetNpcHeadNodePoint(reference)
        if headPoint then
            return headPoint, "npc_head"
        end
        local estimatedEyePoint = GetNpcEstimatedEyePoint(reference)
        if estimatedEyePoint then
            return estimatedEyePoint, "npc_estimated_eye"
        end
    end

    local sceneNode = reference.sceneNode
    if sceneNode and sceneNode.worldBoundOrigin then
        return CopyPoint(sceneNode.worldBoundOrigin), "bounding_box_center"
    end
    return CopyPoint(reference.position), "reference_position"
end

--- Resolve an active-cell reference by ID and calculate its look point.
---@param id string
---@return MCP.PlayerLookTarget?
function this.ResolveTarget(id)
    local reference = this.FindClosestActiveReference(id)
    if not reference then
        return nil
    end
    local point, pointKind = this.GetReferenceLookPoint(reference)
    return { reference = reference, point = point, pointKind = pointKind }
end

return this