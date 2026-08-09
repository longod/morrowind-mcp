local this = {}

---@alias MCP.TerrainObstacleKind "actor"|"moving"|"static"|"unattributed"

---@class MCP.TerrainVolumeOffset
---@field lateral number Signed offset perpendicular to the route segment.
---@field vertical number Height above the sampled ground point.

---@class MCP.TerrainRaycastRoot
---@field name string Stable diagnostic label for the scene root.
---@field node niNode? Root limiting the scene-graph ray query.

---@class MCP.TerrainSegmentValidationParams
---@field boundSize2D tes3vector2|{ x: number, y: number }? Optional actor footprint override.
---@field height number? Optional actor height override.
---@field roots MCP.TerrainRaycastRoot[]? Optional roots used instead of world object and pick roots.
---@field ignore table<integer, niNode|tes3reference>? Scene objects excluded from every ray.

---@class MCP.TerrainSegmentValidationResult
---@field clear boolean Whether no persistent obstruction was found.
---@field rays integer Number of rays performed before completion.
---@field root string? Scene-root label that produced the blocking hit.
---@field classification MCP.TerrainObstacleKind? Classification of the blocking hit.
---@field distance number? Hit distance from its individual ray origin.
---@field reference tes3reference? Reference associated with the blocking hit.

--- Classify a scene-pick reference by whether it can be learned as a persistent static obstruction.
--- Hits without references remain unattributed and are conservatively treated as static geometry.
---@param reference tes3reference?
---@return MCP.TerrainObstacleKind
function this.ClassifyReference(reference)
    if not reference then
        return "unattributed"
    end
    local objectType = reference.object and reference.object.objectType or nil
    if objectType == tes3.objectType.npc or objectType == tes3.objectType.creature then
        return "actor"
    end
    if reference.mobile then
        return "moving"
    end
    return "static"
end

--- Approximate the player's collision volume with a three-by-three set of lateral and vertical ray origins.
--- The widest horizontal bound is used because the route direction can have any yaw.
---@param boundSize2D tes3vector2|{ x: number, y: number }
---@param height number
---@return MCP.TerrainVolumeOffset[]
function this.BuildVolumeOffsets(boundSize2D, height)
    local halfWidth = math.max(boundSize2D.x, boundSize2D.y) * 0.5
    local margin = math.min(8, height * 0.1)
    local offsets = table.new(9, 0)
    offsets[1] = { lateral = -halfWidth, vertical = margin }
    offsets[2] = { lateral = 0, vertical = margin }
    offsets[3] = { lateral = halfWidth, vertical = margin }
    offsets[4] = { lateral = -halfWidth, vertical = height * 0.5 }
    offsets[5] = { lateral = 0, vertical = height * 0.5 }
    offsets[6] = { lateral = halfWidth, vertical = height * 0.5 }
    offsets[7] = { lateral = -halfWidth, vertical = height - margin }
    offsets[8] = { lateral = 0, vertical = height - margin }
    offsets[9] = { lateral = halfWidth, vertical = height - margin }
    return offsets
end

--- Validate one horizontal route segment with bounded scene-graph rays that approximate a swept volume.
--- Actor and moving-reference hits are ignored; static and unattributed hits reject the segment.
---@param start MCP.PathfindingPosition
---@param destination MCP.PathfindingPosition
---@param params MCP.TerrainSegmentValidationParams?
---@return MCP.TerrainSegmentValidationResult
function this.ValidateSegment(start, destination, params)
    params = params or {}
    local dx = destination.x - start.x
    local dy = destination.y - start.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= 0.000001 then
        return { clear = true, rays = 0 }
    end
    -- A normalized perpendicular converts lateral actor offsets into world-space ray origins.
    local perpendicularX = -dy / distance
    local perpendicularY = dx / distance
    local mobile = tes3.mobilePlayer
    local bounds = params.boundSize2D or (mobile and mobile.boundSize2D) or { x = 58.56, y = 56.96 }
    local height = params.height or (mobile and mobile.height) or 133
    local offsets = this.BuildVolumeOffsets(bounds, height)
    -- Separate roots make static and interactable scene queries cheaper and identify the source of a hit.
    local roots = params.roots or {
        { name = "static", node = tes3.game.worldObjectRoot },
        { name = "pick", node = tes3.game.worldPickRoot },
    }
    local rayCount = 0
    for _, root in ipairs(roots) do
        if root.node then
            for _, offset in ipairs(offsets) do
                local origin = tes3vector3.new(
                    start.x + perpendicularX * offset.lateral,
                    start.y + perpendicularY * offset.lateral,
                    start.z + offset.vertical
                )
                local hit = tes3.rayTest({
                    root = root.node,
                    position = origin,
                    direction = tes3vector3.new(dx, dy, 0),
                    maxDistance = distance,
                    ignore = params.ignore,
                })
                rayCount = rayCount + 1
                if hit then
                    local classification = this.ClassifyReference(hit.reference)
                    if classification == "static" or classification == "unattributed" then
                        return {
                            clear = false,
                            rays = rayCount,
                            root = root.name,
                            classification = classification,
                            distance = hit.distance,
                            reference = hit.reference,
                        }
                    end
                end
            end
        end
    end
    return { clear = true, rays = rayCount }
end

return this
