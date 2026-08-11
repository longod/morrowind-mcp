local cellutil = require("morrowind-mcp.tes3.cell")

--- Runtime terrain and collision access used by terrain navigation builders.
--- The probe keeps experimental MWSE collision APIs behind protected calls so unsupported access is reported cleanly.
local this = {}

local exteriorCellSize = cellutil.exteriorCellSize

---@class MCP.TerrainSceneRootInspection
---@field available boolean
---@field node_count integer
---@field tri_shape_count integer
---@field vertex_count integer
---@field triangle_count integer
---@field root_type string?

---@class MCP.TerrainIndexValueInspection
---@field value_type string Lua runtime type of the inspected value.
---@field [string] number|string? Numeric index values keyed by their diagnostic string index.

---@class MCP.TerrainTriangleAccessInspection
---@field available boolean
---@field triangle_type string?
---@field documented_property_ok boolean?
---@field corrected_property_ok boolean?
---@field verticies MCP.TerrainIndexValueInspection?
---@field vertices MCP.TerrainIndexValueInspection?
---@field direct MCP.TerrainIndexValueInspection?

---@class MCP.TerrainCollisionRecordsInspection
---@field available boolean
---@field record_count integer
---@field tri_shape_record_count integer
---@field referenced_record_count integer
---@field types table<string, integer> Record counts keyed by NetImmerse runtime type name.

---@class MCP.TerrainRayProbe
---@field name string
---@field root_available boolean
---@field attempted boolean
---@field hit boolean
---@field error string?
---@field distance number?
---@field object_type string?
---@field parent_type string?
---@field reference_id string?
---@field triangle_index integer?
---@field intersection MCP.PathfindingPosition?
---@field normal MCP.PathfindingPosition?

---@class MCP.TerrainRuntimeCollisionInspection
---@field available boolean? False only when collision-group access raises an error.
---@field error string?
---@field collidees MCP.TerrainCollisionRecordsInspection?
---@field colliders MCP.TerrainCollisionRecordsInspection?

---@class MCP.TerrainPlayerBounds
---@field x number
---@field y number
---@field height number

---@class MCP.TerrainRuntimeAccessProbe
---@field cell_id MCP.CellIdentityKey?
---@field is_exterior boolean
---@field active_cell_count integer
---@field player_bounds MCP.TerrainPlayerBounds?
---@field landscape MCP.TerrainSceneRootInspection
---@field triangle_access MCP.TerrainTriangleAccessInspection
---@field world_landscape MCP.TerrainSceneRootInspection
---@field collision MCP.TerrainRuntimeCollisionInspection
---@field rays table<string, MCP.TerrainRayProbe>
---@field elapsed_milliseconds number
---@field memory_delta_kilobytes number

--- Return a stable diagnostic name for a NetImmerse object without retaining its RTTI object.
---@param node niAVObject?
---@return string?
local function GetNodeTypeName(node)
    return node and node.RTTI and node.RTTI.name or nil
end

--- Count geometry exposed below a scene root for runtime feasibility diagnostics.
--- Counts describe render-scene data and do not assert equivalence with movement collision.
---@param root niNode?
---@return MCP.TerrainSceneRootInspection
local function InspectSceneRoot(root)
    local result = {
        available = root ~= nil,
        node_count = 0,
        tri_shape_count = 0,
        vertex_count = 0,
        triangle_count = 0,
        root_type = GetNodeTypeName(root),
    }
    if not root then
        return result
    end

    for node in root:traverse() do
        result.node_count = result.node_count + 1
        if node:isOfType(ni.type.NiTriShape) then
            ---@cast node niTriShape
            result.tri_shape_count = result.tri_shape_count + 1
            if node.data then
                result.vertex_count = result.vertex_count + (node.data.vertexCount or 0)
                result.triangle_count = result.triangle_count + (node.data.activeTriangleCount or 0)
            end
        end
    end
    return result
end

--- Inspect userdata as a possible index array while isolating unsupported accesses with pcall.
---@param value any
---@return MCP.TerrainIndexValueInspection
local function InspectIndexValue(value)
    local result = { value_type = type(value) }
    if value == nil then
        return result
    end
    for index = 0, 3 do
        local ok, item = pcall(function() return value[index] end)
        result[tostring(index)] = ok and item or nil
    end
    return result
end

--- Compare documented and runtime triangle-index properties on the first available land triangle.
--- This probe records the MWSE metadata typo without making grid generation depend on diagnostics.
---@param root niNode?
---@return MCP.TerrainTriangleAccessInspection
local function InspectTriangleAccess(root)
    local result = { available = false }
    if not root then
        return result
    end
    for node in root:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        if node.data and node.data.activeTriangleCount > 0 then
            local triangle = node.data.triangles[1]
            result.available = triangle ~= nil
            result.triangle_type = type(triangle)
            if triangle then
                local documentedOk, documented = pcall(function() return triangle.verticies end)
                local correctedOk, corrected = pcall(function() return triangle.vertices end) ---@diagnostic disable-line: undefined-field
                result.documented_property_ok = documentedOk
                result.corrected_property_ok = correctedOk
                result.verticies = InspectIndexValue(documentedOk and documented or nil)
                result.vertices = InspectIndexValue(correctedOk and corrected or nil)
                result.direct = InspectIndexValue(triangle)
            end
            return result
        end
    end
    return result
end

--- Summarize the experimental collision-group array without trusting its collider/collidee naming semantics.
---@param records niCollisionGroupRecord[]?
---@return MCP.TerrainCollisionRecordsInspection
local function InspectCollisionRecords(records)
    local result = {
        available = records ~= nil,
        record_count = 0,
        tri_shape_record_count = 0,
        referenced_record_count = 0,
        types = {},
    }
    for _, record in ipairs(records or {}) do
        -- Experimental collision arrays may expose sparse nil slots through MWSE iteration.
        if record then
            result.record_count = result.record_count + 1
            local object = record.object
            local typeName = GetNodeTypeName(object) or "unknown"
            result.types[typeName] = (result.types[typeName] or 0) + 1
            if object and object:isOfType(ni.type.NiTriShape) then
                result.tri_shape_record_count = result.tri_shape_record_count + 1
            end
            if object and object:getGameReference(true) then
                result.referenced_record_count = result.referenced_record_count + 1
            end
        end
    end
    return result
end

--- Cast one bounded diagnostic ray against a specific scene root and serialize only stable primitive hit data.
---@param name string
---@param root niNode?
---@param position tes3vector3
---@param direction tes3vector3
---@param maxDistance number
---@return MCP.TerrainRayProbe
local function ProbeRay(name, root, position, direction, maxDistance)
    local result = {
        name = name,
        root_available = root ~= nil,
        attempted = false,
        hit = false,
    }
    if not root then
        return result
    end

    result.attempted = true
    local ok, hitOrError = pcall(tes3.rayTest, {
        root = root,
        position = position,
        direction = direction,
        maxDistance = maxDistance,
        returnNormal = true,
    })
    if not ok then
        result.error = tostring(hitOrError)
        return result
    end

    local hit = hitOrError ---@type niPickRecord?
    if hit then
        result.hit = true
        result.distance = hit.distance
        result.object_type = GetNodeTypeName(hit.object)
        result.parent_type = GetNodeTypeName(hit.parent)
        result.reference_id = hit.reference and hit.reference.id or nil
        result.triangle_index = hit.triangleIndex
        if hit.intersection then
            result.intersection = { x = hit.intersection.x, y = hit.intersection.y, z = hit.intersection.z }
        end
        if hit.normal then
            result.normal = { x = hit.normal.x, y = hit.normal.y, z = hit.normal.z }
        end
    end
    return result
end

--- Inspect whether the current outdoor runtime exposes enough terrain, collision, and ray-pick data.
---@return MCP.TerrainRuntimeAccessProbe result
function this.ProbeRuntimeAccess()
    local startedAt = os.clock()
    local memoryBefore = collectgarbage("count")
    local player = tes3.player
    local cell = player and player.cell or nil
    local mobilePlayer = tes3.mobilePlayer
    local playerBounds = mobilePlayer and mobilePlayer.boundSize2D or nil
    local result = {
        cell_id = cell and cellutil.GetIdentityKey(cell) or nil,
        is_exterior = cell ~= nil and not cell.isInterior or false,
        active_cell_count = table.size(tes3.getActiveCells()),
        -- Some menu and transition states expose mobilePlayer before its collision bounds are initialized.
        player_bounds = playerBounds and {
            x = playerBounds.x,
            y = playerBounds.y,
            height = mobilePlayer.height,
        } or nil,
    }

    local landscapeRoot = cell and cell.landscape and cell.landscape.sceneNode or nil
    result.landscape = InspectSceneRoot(landscapeRoot)
    result.triangle_access = InspectTriangleAccess(landscapeRoot)
    result.world_landscape = InspectSceneRoot(tes3.game.worldLandscapeRoot)

    local collisionOk, collisionOrError = pcall(function()
        local group = tes3.worldController.mobManager.mobCollisionGroup
        return {
            collidees = InspectCollisionRecords(group.collidees),
            colliders = InspectCollisionRecords(group.colliders),
        }
    end)
    if collisionOk then
        result.collision = collisionOrError
    else
        result.collision = { available = false, error = tostring(collisionOrError) }
    end

    if player then
        local origin = tes3vector3.new(player.position.x, player.position.y, player.position.z + 4096)
        local direction = tes3vector3.new(0, 0, -1)
        result.rays = {
            landscape = ProbeRay("landscape", tes3.game.worldLandscapeRoot, origin, direction, exteriorCellSize),
            static = ProbeRay("static", tes3.game.worldObjectRoot, origin, direction, exteriorCellSize),
            pick = ProbeRay("pick", tes3.game.worldPickRoot, origin, direction, exteriorCellSize),
        }
    else
        result.rays = {}
    end

    result.elapsed_milliseconds = (os.clock() - startedAt) * 1000
    result.memory_delta_kilobytes = collectgarbage("count") - memoryBefore
    return result
end

---@class MCP.TerrainSampleTriangle
---@field ax number
---@field ay number
---@field az number
---@field bx number
---@field by number
---@field bz number
---@field cx number
---@field cy number
---@field cz number
---@field normalZ number Absolute upward component of the face normal.

---@class MCP.TerrainHeightSampler
---@field Sample fun(self: MCP.TerrainHeightSampler, x: number, y: number): number?, number?

---@class MCP.TerrainSampler: MCP.TerrainHeightSampler
---@field mode "mesh"|"ray"
---@field root niNode?
---@field rayOriginZ number?
---@field rayMaxDistance number?
---@field direction tes3vector3?
---@field originX number?
---@field originY number?
---@field bucketSize number?
---@field bucketCount integer?
---@field triangles MCP.TerrainSampleTriangle[]?
---@field buckets table<integer, integer[]>?
---@field errorCount integer
---@field Sample fun(self: MCP.TerrainSampler, x: number, y: number): number?, number?
---@field Release fun(self: MCP.TerrainSampler)

--- Clamp projected bucket coordinates to the cell-local spatial index.
---@param value number
---@param minimum number
---@param maximum number
---@return number
local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

--- Interpolate a world-space height inside one projected XY triangle using barycentric coordinates.
--- Degenerate triangles and points outside the triangle return nil.
---@param triangle MCP.TerrainSampleTriangle
---@param x number
---@param y number
---@return number?
local function SampleTriangle(triangle, x, y)
    local denominator = (triangle.by - triangle.cy) * (triangle.ax - triangle.cx)
        + (triangle.cx - triangle.bx) * (triangle.ay - triangle.cy)
    if math.abs(denominator) <= 0.000001 then
        return nil
    end
    local first = ((triangle.by - triangle.cy) * (x - triangle.cx)
        + (triangle.cx - triangle.bx) * (y - triangle.cy)) / denominator
    local second = ((triangle.cy - triangle.ay) * (x - triangle.cx)
        + (triangle.ax - triangle.cx) * (y - triangle.cy)) / denominator
    local third = 1 - first - second
    if first < -0.0001 or second < -0.0001 or third < -0.0001 then
        return nil
    end
    return triangle.az * first + triangle.bz * second + triangle.cz * third
end

--- Sample terrain height and upward normal from the selected source implementation.
--- Mesh mode uses spatial buckets; ray mode is a compatibility fallback restricted to the cell landscape root.
---@param x number
---@param y number
---@return number? height
---@return number? normalZ
function this:Sample(x, y)
    if self.mode == "mesh" then
        local column = Clamp(math.floor((x - self.originX) / self.bucketSize), 0, self.bucketCount - 1)
        local row = Clamp(math.floor((y - self.originY) / self.bucketSize), 0, self.bucketCount - 1)
        local bucket = self.buckets[row * self.bucketCount + column + 1]
        local bestHeight, bestNormalZ = nil, nil
        for _, triangleIndex in ipairs(bucket or {}) do
            local triangle = self.triangles[triangleIndex]
            local height = SampleTriangle(triangle, x, y)
            if height and (bestHeight == nil or height > bestHeight) then
                bestHeight = height
                bestNormalZ = triangle.normalZ
            end
        end
        return bestHeight, bestNormalZ
    end
    -- Protected access prevents one unsupported scene-pick call from terminating an incremental builder callback.
    local ok, hitOrError = pcall(tes3.rayTest, {
        root = self.root,
        position = tes3vector3.new(x, y, self.rayOriginZ),
        direction = self.direction,
        maxDistance = self.rayMaxDistance,
        returnNormal = true,
    })
    if not ok then
        self.errorCount = self.errorCount + 1
        return nil, nil
    end
    local hit = hitOrError ---@type niPickRecord?
    if not hit or not hit.intersection or not hit.normal then
        return nil, nil
    end
    return hit.intersection.z, math.abs(hit.normal.z)
end

--- Drop scene and mesh references once the builder has copied all required samples.
function this:Release()
    self.root = nil
    self.direction = nil
    self.triangles = nil
    self.buckets = nil
end

--- Build a cell-local terrain sampler from transformed land triangles.
--- Current MWSE exposes triangle indices through `vertices`; a cell-root ray sampler is returned only as fallback.
---@param cell tes3cell
---@param bucketSize number? Spatial bucket width in world units.
---@return MCP.TerrainSampler?
---@return string?
function this.CreateCellSampler(cell, bucketSize)
    if not cell or cell.isInterior or not cell.landscape or not cell.landscape.sceneNode then
        return nil, "Active exterior landscape scene graph is unavailable."
    end
    bucketSize = bucketSize or 128
    local originX = cell.gridX * exteriorCellSize
    local originY = cell.gridY * exteriorCellSize
    local bucketCount = math.ceil(exteriorCellSize / bucketSize)
    ---@type MCP.TerrainSampleTriangle[]
    local triangles = {}
    ---@type table<integer, integer[]>
    local buckets = table.new(bucketCount * bucketCount, 0)
    for node in cell.landscape.sceneNode:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        local data = node.data
        if data and data.vertexCount > 0 then
            local vertices = table.new(data.vertexCount, 0)
            -- Copy and transform shared model vertices before the active cell can unload its scene graph.
            for index, vertex in ipairs(data.vertices) do
                local world = node.worldTransform * vertex:copy()
                vertices[index] = { x = world.x, y = world.y, z = world.z }
            end
            for triangleIndex = 1, data.activeTriangleCount do
                local sourceTriangle = data.triangles[triangleIndex]
                -- Current MWSE exposes this as `vertices`; generated metadata incorrectly says `verticies`.
                local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                local first = indices and indices[1] ~= nil and vertices[indices[1] + 1] or nil
                local second = indices and indices[2] ~= nil and vertices[indices[2] + 1] or nil
                local third = indices and indices[3] ~= nil and vertices[indices[3] + 1] or nil
                if first and second and third then
                    local abx, aby, abz = second.x - first.x, second.y - first.y, second.z - first.z
                    local acx, acy, acz = third.x - first.x, third.y - first.y, third.z - first.z
                    local nx = aby * acz - abz * acy
                    local ny = abz * acx - abx * acz
                    local nz = abx * acy - aby * acx
                    local normalLength = math.sqrt(nx * nx + ny * ny + nz * nz)
                    local triangle = {
                        ax = first.x, ay = first.y, az = first.z,
                        bx = second.x, by = second.y, bz = second.z,
                        cx = third.x, cy = third.y, cz = third.z,
                        normalZ = normalLength > 0 and math.abs(nz / normalLength) or 0,
                    }
                    table.insert(triangles, triangle)
                    local storedIndex = table.size(triangles)
                    local minColumn = Clamp(math.floor((math.min(first.x, second.x, third.x) - originX) / bucketSize), 0, bucketCount - 1)
                    local maxColumn = Clamp(math.floor((math.max(first.x, second.x, third.x) - originX) / bucketSize), 0, bucketCount - 1)
                    local minRow = Clamp(math.floor((math.min(first.y, second.y, third.y) - originY) / bucketSize), 0, bucketCount - 1)
                    local maxRow = Clamp(math.floor((math.max(first.y, second.y, third.y) - originY) / bucketSize), 0, bucketCount - 1)
                    -- Bucket by projected bounds so each grid sample tests only nearby land triangles.
                    for row = minRow, maxRow do
                        for column = minColumn, maxColumn do
                            local bucketIndex = row * bucketCount + column + 1
                            buckets[bucketIndex] = buckets[bucketIndex] or {}
                            table.insert(buckets[bucketIndex], storedIndex)
                        end
                    end
                end
            end
        end
    end
    if table.size(triangles) > 0 then
        local sampler = {
            mode = "mesh",
            originX = originX,
            originY = originY,
            bucketSize = bucketSize,
            bucketCount = bucketCount,
            triangles = triangles,
            buckets = buckets,
            errorCount = 0,
        }
        setmetatable(sampler, { __index = this })
        return sampler
    end

    -- Keep a supported scene-pick fallback for runtimes where triangle indices are unavailable.
    local minimumHeight = cell.landscape.minHeight or -4096
    local maximumHeight = cell.landscape.maxHeight or 4096
    local sampler = {
        mode = "ray",
        root = cell.landscape.sceneNode,
        rayOriginZ = maximumHeight + 1024,
        rayMaxDistance = math.max(4096, maximumHeight - minimumHeight + 2048),
        direction = tes3vector3.new(0, 0, -1),
        errorCount = 0,
    }
    setmetatable(sampler, { __index = this })
    return sampler
end

return this
