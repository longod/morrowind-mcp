local cellutil = require("morrowind-mcp.tes3.cell")
local parameters = require("morrowind-mcp.navigation.terrain.parameters")

--- Runtime terrain and collision access used by terrain navigation builders.
--- The probe keeps experimental MWSE collision APIs behind protected calls so unsupported access is reported cleanly.
local this = {}

local exteriorCellSize = cellutil.exteriorCellSize

-- Morrowind land records store a fixed 65x65 height grid per exterior cell.
local landGridWidth = 65
local landQuadWidth = landGridWidth - 1
local landInterval = exteriorCellSize / landQuadWidth
-- Alignment and shared-height tolerances guard against float noise without accepting genuinely irregular meshes.
local landAlignmentTolerance = 0.01
local landHeightTolerance = 0.01

--- Quad corners are ordered as (0,0), (1,0), (0,1), (1,1) relative to the quad's lower-left grid point.
local mainDiagonal = 1
local antiDiagonal = 2
-- Verification samples are bounded: construction checks the leading triangles of every patch, and the probe
-- reports only the leading violations, because full per-triangle reporting would defeat the point of the rule.
local quadVerifyTrianglesPerNode = 2
local quadRuleMismatchSampleLimit = 16
this.mainDiagonal = mainDiagonal
this.antiDiagonal = antiDiagonal

--- Diagonal split of one land quad, derived from its checkerboard position.
--- Sampler construction verifies this rule against real mesh triangles before trusting it.
---@param quadColumn integer
---@param quadRow integer
---@return integer
function this.QuadDiagonalForPosition(quadColumn, quadRow)
    return (quadColumn + quadRow) % 2 == 0 and mainDiagonal or antiDiagonal
end

---@class MCP.TerrainSceneRootInspection
---@field available boolean
---@field node_count integer
---@field tri_shape_count integer
---@field vertex_count integer
---@field triangle_count integer
---@field root_type string?

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
---@field firstWeightX number
---@field firstWeightY number
---@field firstWeightOffset number
---@field secondWeightX number
---@field secondWeightY number
---@field secondWeightOffset number
---@field heightX number
---@field heightY number
---@field heightOffset number
---@field inverseDenominator number Zero marks a degenerate triangle.
---@field normalZSquared number Squared absolute upward component of the unit face normal.

---@class MCP.TerrainSampleTriangleStore
---@field firstWeightX number[]
---@field firstWeightY number[]
---@field firstWeightOffset number[]
---@field secondWeightX number[]
---@field secondWeightY number[]
---@field secondWeightOffset number[]
---@field heightX number[]
---@field heightY number[]
---@field heightOffset number[]
---@field inverseDenominator number[]
---@field normalZSquared number[]

---@class MCP.TerrainHeightSampler
---@field Sample fun(self: MCP.TerrainHeightSampler, x: number, y: number): number?, number? Returns height and squared upward unit-normal component.

---@class MCP.TerrainSamplerMetrics
---@field mode "mesh"|"ray"|"heightfield" Terrain sampling implementation selected at construction.
---@field triangle_storage_mode "aos"|"soa" Shared representation used for temporary vertices and completed terrain triangles.
---@field bucket_size number? Spatial bucket width used by mesh sampling.
---@field bucket_count integer? Number of buckets per cell axis for mesh sampling.
---@field land_interval number? Height grid spacing used by heightfield sampling.
---@field land_grid_width integer? Height grid points per cell axis for heightfield sampling.
---@field verified_triangle_count integer? Triangles checked against the checkerboard diagonal rule.
---@field heightfield_fallback_reason string? Why heightfield sampling was rejected for this cell.
---@field transformed_vertex_count integer Number of source vertices transformed into world space.
---@field triangle_count integer Number of usable land triangles stored by the sampler.
---@field bucket_registration_count integer Number of triangle-to-bucket registrations.
---@field bucket_occupancy_mean number Mean registrations per spatial bucket.
---@field bucket_occupancy_max integer Largest number of triangle registrations in one bucket.
---@field identity_transform_node_count integer Nodes whose world transform reduced to a translation-only fast path.
---@field construction_elapsed_milliseconds number Wall-clock duration of sampler construction.
---@field construction_memory_delta_kilobytes number Lua heap delta observed during sampler construction.

---@class MCP.TerrainSampler: MCP.TerrainHeightSampler
---@field mode "mesh"|"ray"|"heightfield"
---@field root niNode?
---@field rayOriginZ number?
---@field rayMaxDistance number?
---@field direction tes3vector3?
---@field originX number?
---@field originY number?
---@field bucketSize number?
---@field bucketCount integer?
---@field heights number[]? Row-major land elevations used by heightfield sampling.
---@field landInterval number?
---@field landWidth integer?
---@field quadWidth integer?
---@field triangles MCP.TerrainSampleTriangle[]?
---@field triangleStore MCP.TerrainSampleTriangleStore?
---@field triangleStorageMode "aos"|"soa"
---@field buckets table<integer, integer[]>?
---@field metrics MCP.TerrainSamplerMetrics Construction diagnostics retained after Release.
---@field errorCount integer
---@field Sample fun(self: MCP.TerrainSampler, x: number, y: number): number?, number?
---@field Release fun(self: MCP.TerrainSampler)

---@class MCP.TerrainWorldTransform
---@field r00 number
---@field r01 number
---@field r02 number
---@field r10 number
---@field r11 number
---@field r12 number
---@field r20 number
---@field r21 number
---@field r22 number
---@field tx number
---@field ty number
---@field tz number
---@field scale number
---@field isIdentity boolean True when the rotation is the identity matrix and the scale is one.

--- Flatten one scene node's world transform into scalars so vertex loops avoid per-vertex vector allocation.
--- `tes3matrix33` exposes rows through `x`, `y`, and `z`, so each row is read once and applied as a row-vector product.
--- Identity is detected at runtime instead of assumed, keeping rotated or scaled land patches correct.
---@param node niAVObject
---@return MCP.TerrainWorldTransform
function this.ResolveWorldTransformScalars(node)
    local transform = node.worldTransform
    local rotation = transform.rotation
    local translation = transform.translation
    local scale = transform.scale
    local firstRow, secondRow, thirdRow = rotation.x, rotation.y, rotation.z
    local r00, r01, r02 = firstRow.x, firstRow.y, firstRow.z
    local r10, r11, r12 = secondRow.x, secondRow.y, secondRow.z
    local r20, r21, r22 = thirdRow.x, thirdRow.y, thirdRow.z
    return {
        r00 = r00, r01 = r01, r02 = r02,
        r10 = r10, r11 = r11, r12 = r12,
        r20 = r20, r21 = r21, r22 = r22,
        tx = translation.x, ty = translation.y, tz = translation.z,
        scale = scale,
        isIdentity = scale == 1
            and r00 == 1 and r01 == 0 and r02 == 0
            and r10 == 0 and r11 == 1 and r12 == 0
            and r20 == 0 and r21 == 0 and r22 == 1,
    }
end

--- Fill three parallel world-space arrays from one node's model-space vertices.
--- Components are read as numbers so no intermediate `tes3vector3` is allocated per vertex.
---@param vertices tes3vector3[]
---@param transform MCP.TerrainWorldTransform
---@param outX number[]
---@param outY number[]
---@param outZ number[]
---@return integer transformedCount
local function TransformVerticesToArrays(vertices, transform, outX, outY, outZ)
    local transformedCount = 0
    local tx, ty, tz = transform.tx, transform.ty, transform.tz
    if transform.isIdentity then
        for index, vertex in ipairs(vertices) do
            outX[index], outY[index], outZ[index] = vertex.x + tx, vertex.y + ty, vertex.z + tz
            transformedCount = index
        end
        return transformedCount
    end
    local scale = transform.scale
    local r00, r01, r02 = transform.r00, transform.r01, transform.r02
    local r10, r11, r12 = transform.r10, transform.r11, transform.r12
    local r20, r21, r22 = transform.r20, transform.r21, transform.r22
    for index, vertex in ipairs(vertices) do
        local vx, vy, vz = vertex.x, vertex.y, vertex.z
        outX[index] = (r00 * vx + r01 * vy + r02 * vz) * scale + tx
        outY[index] = (r10 * vx + r11 * vy + r12 * vz) * scale + ty
        outZ[index] = (r20 * vx + r21 * vy + r22 * vz) * scale + tz
        transformedCount = index
    end
    return transformedCount
end

--- Fill an array of world-space vertex tables from one node's model-space vertices.
--- The array-of-structures layout is retained here because benchmark cases compare it against the parallel arrays.
---@param vertices tes3vector3[]
---@param transform MCP.TerrainWorldTransform
---@param out MCP.PathfindingPosition[]
---@return integer transformedCount
local function TransformVerticesToTables(vertices, transform, out)
    local transformedCount = 0
    local tx, ty, tz = transform.tx, transform.ty, transform.tz
    if transform.isIdentity then
        for index, vertex in ipairs(vertices) do
            out[index] = { x = vertex.x + tx, y = vertex.y + ty, z = vertex.z + tz }
            transformedCount = index
        end
        return transformedCount
    end
    local scale = transform.scale
    local r00, r01, r02 = transform.r00, transform.r01, transform.r02
    local r10, r11, r12 = transform.r10, transform.r11, transform.r12
    local r20, r21, r22 = transform.r20, transform.r21, transform.r22
    for index, vertex in ipairs(vertices) do
        local vx, vy, vz = vertex.x, vertex.y, vertex.z
        out[index] = {
            x = (r00 * vx + r01 * vy + r02 * vz) * scale + tx,
            y = (r10 * vx + r11 * vy + r12 * vz) * scale + ty,
            z = (r20 * vx + r21 * vy + r22 * vz) * scale + tz,
        }
        transformedCount = index
    end
    return transformedCount
end

--- Derive reusable barycentric and height-plane coefficients from one world-space triangle.
--- Coefficients are returned individually so mesh construction fills either storage layout without a temporary table.
---@param firstX number
---@param firstY number
---@param firstZ number
---@param secondX number
---@param secondY number
---@param secondZ number
---@param thirdX number
---@param thirdY number
---@param thirdZ number
---@return number firstWeightX
---@return number firstWeightY
---@return number firstWeightOffset
---@return number secondWeightX
---@return number secondWeightY
---@return number secondWeightOffset
---@return number heightX
---@return number heightY
---@return number heightOffset
---@return number inverseDenominator Zero marks a degenerate triangle.
function this.CalculateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
    local denominator = (secondY - thirdY) * (firstX - thirdX) + (thirdX - secondX) * (firstY - thirdY)
    local inverseDenominator = math.abs(denominator) > 0.000001 and 1 / denominator or 0
    local firstWeightX = (secondY - thirdY) * inverseDenominator
    local firstWeightY = (thirdX - secondX) * inverseDenominator
    local firstWeightOffset = -firstWeightX * thirdX - firstWeightY * thirdY
    local secondWeightX = (thirdY - firstY) * inverseDenominator
    local secondWeightY = (firstX - thirdX) * inverseDenominator
    local secondWeightOffset = -secondWeightX * thirdX - secondWeightY * thirdY
    local heightX = (firstZ - thirdZ) * firstWeightX + (secondZ - thirdZ) * secondWeightX
    local heightY = (firstZ - thirdZ) * firstWeightY + (secondZ - thirdZ) * secondWeightY
    local heightOffset = thirdZ + (firstZ - thirdZ) * firstWeightOffset + (secondZ - thirdZ) * secondWeightOffset
    return firstWeightX, firstWeightY, firstWeightOffset,
        secondWeightX, secondWeightY, secondWeightOffset,
        heightX, heightY, heightOffset, inverseDenominator
end

--- Materialize triangle coefficients as one table for callers that keep an array-of-structures layout.
---@param firstX number
---@param firstY number
---@param firstZ number
---@param secondX number
---@param secondY number
---@param secondZ number
---@param thirdX number
---@param thirdY number
---@param thirdZ number
---@return MCP.TerrainSampleTriangle
function this.CreateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
    local firstWeightX, firstWeightY, firstWeightOffset,
    secondWeightX, secondWeightY, secondWeightOffset,
    heightX, heightY, heightOffset, inverseDenominator =
        this.CalculateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
    return {
        firstWeightX = firstWeightX, firstWeightY = firstWeightY, firstWeightOffset = firstWeightOffset,
        secondWeightX = secondWeightX, secondWeightY = secondWeightY, secondWeightOffset = secondWeightOffset,
        heightX = heightX, heightY = heightY, heightOffset = heightOffset,
        inverseDenominator = inverseDenominator,
        normalZSquared = 0,
    }
end

--- Sample one triangle using barycentric and height-plane coefficients prepared during mesh construction.
---@param triangle MCP.TerrainSampleTriangle
---@param x number
---@param y number
---@return number?
local function SampleTriangle(triangle, x, y)
    if triangle.inverseDenominator == 0 then
        return nil
    end
    local first = triangle.firstWeightX * x + triangle.firstWeightY * y + triangle.firstWeightOffset
    local second = triangle.secondWeightX * x + triangle.secondWeightY * y + triangle.secondWeightOffset
    local third = 1 - first - second
    if first < -0.0001 or second < -0.0001 or third < -0.0001 then
        return nil
    end
    return triangle.heightX * x + triangle.heightY * y + triangle.heightOffset
end

--- Sample one structure-of-arrays triangle using coefficients prepared during mesh construction.
---@param triangles MCP.TerrainSampleTriangleStore
---@param index integer
---@param x number
---@param y number
---@return number?
local function SampleTriangleStore(triangles, index, x, y)
    if triangles.inverseDenominator[index] == 0 then
        return nil
    end
    local first = triangles.firstWeightX[index] * x + triangles.firstWeightY[index] * y + triangles.firstWeightOffset[index]
    local second = triangles.secondWeightX[index] * x + triangles.secondWeightY[index] * y + triangles.secondWeightOffset[index]
    local third = 1 - first - second
    if first < -0.0001 or second < -0.0001 or third < -0.0001 then
        return nil
    end
    return triangles.heightX[index] * x + triangles.heightY[index] * y + triangles.heightOffset[index]
end

--- Sample terrain height and squared upward normal from the selected source implementation.
--- Heightfield mode interpolates the land height grid; mesh mode uses spatial buckets; ray mode is a
--- compatibility fallback restricted to the cell landscape root.
---@param x number
---@param y number
---@return number? height
---@return number? normalZSquared
function this:Sample(x, y)
    if self.mode == "heightfield" then
        local interval = self.landInterval
        local quadWidth = self.quadWidth
        local columnValue = (x - self.originX) / interval
        local rowValue = (y - self.originY) / interval
        if columnValue < 0 or rowValue < 0 or columnValue > quadWidth or rowValue > quadWidth then
            return nil, nil
        end
        local quadColumn = math.min(quadWidth - 1, math.floor(columnValue))
        local quadRow = math.min(quadWidth - 1, math.floor(rowValue))
        local width = self.landWidth
        local heights = self.heights
        local baseIndex = quadRow * width + quadColumn + 1
        local z00 = heights[baseIndex]
        local z10 = heights[baseIndex + 1]
        local z01 = heights[baseIndex + width]
        local z11 = heights[baseIndex + width + 1]
        if not (z00 and z10 and z01 and z11) then
            return nil, nil
        end
        local fx = columnValue - quadColumn
        local fy = rowValue - quadRow
        -- Each quad is split by one diagonal, so the containing triangle defines both the height plane and the face normal.
        local height, slopeX, slopeY
        if this.QuadDiagonalForPosition(quadColumn, quadRow) == mainDiagonal then
            if fy <= fx then
                height = z00 + fx * (z10 - z00) + fy * (z11 - z10)
                slopeX, slopeY = (z10 - z00) / interval, (z11 - z10) / interval
            else
                height = z00 + fy * (z01 - z00) + fx * (z11 - z01)
                slopeX, slopeY = (z11 - z01) / interval, (z01 - z00) / interval
            end
        elseif fx + fy <= 1 then
            height = z00 + fx * (z10 - z00) + fy * (z01 - z00)
            slopeX, slopeY = (z10 - z00) / interval, (z01 - z00) / interval
        else
            height = z11 + (1 - fx) * (z01 - z11) + (1 - fy) * (z10 - z11)
            slopeX, slopeY = (z11 - z01) / interval, (z11 - z10) / interval
        end
        return height, 1 / (1 + slopeX * slopeX + slopeY * slopeY)
    end
    if self.mode == "mesh" then
        local bucketSize, bucketCount = self.bucketSize, self.bucketCount
        local maxBucketIndex = bucketCount - 1
        local column = math.max(0, math.min(maxBucketIndex, math.floor((x - self.originX) / bucketSize)))
        local row = math.max(0, math.min(maxBucketIndex, math.floor((y - self.originY) / bucketSize)))
        local bucket = self.buckets[row * bucketCount + column + 1]
        if not bucket then
            return nil, nil
        end
        local bestHeight, bestNormalZSquared = nil, nil
        -- The storage layout is invariant for one sampler, so the branch is hoisted out of the triangle loop.
        if self.triangleStorageMode == "soa" then
            local triangles = self.triangleStore
            for index = 1, #bucket do
                local triangleIndex = bucket[index]
                local height = SampleTriangleStore(triangles, triangleIndex, x, y)
                if height and (bestHeight == nil or height > bestHeight) then
                    bestHeight = height
                    bestNormalZSquared = triangles.normalZSquared[triangleIndex]
                end
            end
        else
            local triangles = self.triangles
            for index = 1, #bucket do
                local triangle = triangles[bucket[index]]
                local height = SampleTriangle(triangle, x, y)
                if height and (bestHeight == nil or height > bestHeight) then
                    bestHeight = height
                    bestNormalZSquared = triangle.normalZSquared
                end
            end
        end
        return bestHeight, bestNormalZSquared
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
    return hit.intersection.z, hit.normal.z * hit.normal.z
end

--- Drop scene and mesh references once the builder has copied all required samples.
function this:Release()
    self.root = nil
    self.direction = nil
    self.triangles = nil
    self.triangleStore = nil
    self.buckets = nil
    self.heights = nil
end

--- Build a sampler backed by the land record's regular height grid.
--- Every vertex must land on the height grid and the checkerboard quad split must hold; otherwise nil is
--- returned with a reason so the caller falls back to triangle sampling and non-vanilla landscapes stay correct.
---@param cell tes3cell
---@param triangleStorageMode "aos"|"soa"
---@param constructionStartedAt number
---@param constructionMemoryBefore number
---@return MCP.TerrainSampler?
---@return string?
local function CreateHeightfieldSampler(cell, triangleStorageMode, constructionStartedAt, constructionMemoryBefore)
    local originX = cell.gridX * exteriorCellSize
    local originY = cell.gridY * exteriorCellSize
    local heights = table.new(landGridWidth * landGridWidth, 0)
    local coveredCount = 0
    local transformedVertexCount = 0
    local identityTransformNodeCount = 0
    local verifiedTriangleCount = 0
    for node in cell.landscape.sceneNode:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        local data = node.data
        if data and data.vertexCount > 0 then
            local transform = this.ResolveWorldTransformScalars(node)
            local isIdentity = transform.isIdentity
            if isIdentity then
                identityTransformNodeCount = identityTransformNodeCount + 1
            end
            local scale = transform.scale
            local r00, r01, r02 = transform.r00, transform.r01, transform.r02
            local r10, r11, r12 = transform.r10, transform.r11, transform.r12
            local r20, r21, r22 = transform.r20, transform.r21, transform.r22
            local tx, ty, tz = transform.tx, transform.ty, transform.tz
            local vertexColumn = table.new(data.vertexCount, 0)
            local vertexRow = table.new(data.vertexCount, 0)
            for vertexIndex, vertex in ipairs(data.vertices) do
                local vx, vy, vz = vertex.x, vertex.y, vertex.z
                local wx, wy, wz
                if isIdentity then
                    wx, wy, wz = vx + tx, vy + ty, vz + tz
                else
                    wx = (r00 * vx + r01 * vy + r02 * vz) * scale + tx
                    wy = (r10 * vx + r11 * vy + r12 * vz) * scale + ty
                    wz = (r20 * vx + r21 * vy + r22 * vz) * scale + tz
                end
                local columnValue = (wx - originX) / landInterval
                local rowValue = (wy - originY) / landInterval
                local column = math.floor(columnValue + 0.5)
                local row = math.floor(rowValue + 0.5)
                if math.abs(columnValue - column) > landAlignmentTolerance
                    or math.abs(rowValue - row) > landAlignmentTolerance
                    or column < 0 or row < 0 or column >= landGridWidth or row >= landGridWidth then
                    return nil, "Landscape vertices are not aligned to the land height grid."
                end
                vertexColumn[vertexIndex], vertexRow[vertexIndex] = column, row
                local index = row * landGridWidth + column + 1
                local existing = heights[index]
                if existing == nil then
                    heights[index] = wz
                    coveredCount = coveredCount + 1
                elseif math.abs(existing - wz) > landHeightTolerance then
                    return nil, "Landscape patches disagree on a shared grid height."
                end
                transformedVertexCount = transformedVertexCount + 1
            end

            -- Only a bounded per-node sample is verified; a full scan would reintroduce the cost this path removes.
            for triangleIndex = 1, math.min(quadVerifyTrianglesPerNode, data.activeTriangleCount) do
                local sourceTriangle = data.triangles[triangleIndex]
                local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                local firstIndex = indices and indices[1] ~= nil and indices[1] + 1 or nil
                local secondIndex = indices and indices[2] ~= nil and indices[2] + 1 or nil
                local thirdIndex = indices and indices[3] ~= nil and indices[3] + 1 or nil
                if not (firstIndex and secondIndex and thirdIndex) then
                    return nil, "Landscape triangle indices are unavailable."
                end
                local diagonal, quadColumn, quadRow = this.ClassifyQuadDiagonal(
                    vertexColumn[firstIndex], vertexRow[firstIndex],
                    vertexColumn[secondIndex], vertexRow[secondIndex],
                    vertexColumn[thirdIndex], vertexRow[thirdIndex])
                if not diagonal or diagonal ~= this.QuadDiagonalForPosition(quadColumn, quadRow) then
                    return nil, "Landscape quads do not follow the checkerboard diagonal split."
                end
                verifiedTriangleCount = verifiedTriangleCount + 1
            end
        end
    end
    if coveredCount ~= landGridWidth * landGridWidth then
        return nil, "Landscape height grid is incomplete."
    end
    if verifiedTriangleCount == 0 then
        return nil, "No landscape triangle was available to verify the quad diagonal rule."
    end

    local sampler = {
        mode = "heightfield",
        originX = originX,
        originY = originY,
        heights = heights,
        landInterval = landInterval,
        landWidth = landGridWidth,
        quadWidth = landQuadWidth,
        triangleStorageMode = triangleStorageMode,
        metrics = {
            mode = "heightfield",
            triangle_storage_mode = triangleStorageMode,
            land_interval = landInterval,
            land_grid_width = landGridWidth,
            verified_triangle_count = verifiedTriangleCount,
            transformed_vertex_count = transformedVertexCount,
            triangle_count = 0,
            bucket_registration_count = 0,
            bucket_occupancy_mean = 0,
            bucket_occupancy_max = 0,
            identity_transform_node_count = identityTransformNodeCount,
            construction_elapsed_milliseconds = (os.clock() - constructionStartedAt) * 1000,
            construction_memory_delta_kilobytes = collectgarbage("count") - constructionMemoryBefore,
        },
        errorCount = 0,
    }
    setmetatable(sampler, { __index = this })
    return sampler
end

--- Build a cell-local terrain sampler from the land height grid, or from transformed land triangles.
--- Current MWSE exposes triangle indices through `vertices`; a cell-root ray sampler is returned only as fallback.
---@param cell tes3cell
---@param bucketSize number? Spatial bucket width in world units.
---@param triangleStorageMode "aos"|"soa"? Shared temporary-vertex and completed-triangle representation; the production default is SoA.
---@param samplerMode "heightfield"|"mesh"? Omitted selects heightfield sampling with an automatic mesh fallback.
---@return MCP.TerrainSampler?
---@return string?
function this.CreateCellSampler(cell, bucketSize, triangleStorageMode, samplerMode)
    local constructionStartedAt = os.clock()
    local constructionMemoryBefore = collectgarbage("count")
    if not cell or cell.isInterior or not cell.landscape or not cell.landscape.sceneNode then
        return nil, "Active exterior landscape scene graph is unavailable."
    end
    bucketSize = bucketSize or 128
    triangleStorageMode = triangleStorageMode or "soa"
    local heightfieldFallbackReason = nil
    if samplerMode ~= "mesh" then
        local heightfieldSampler, reason =
            CreateHeightfieldSampler(cell, triangleStorageMode, constructionStartedAt, constructionMemoryBefore)
        if heightfieldSampler then
            return heightfieldSampler
        end
        heightfieldFallbackReason = reason
    end
    local originX = cell.gridX * exteriorCellSize
    local originY = cell.gridY * exteriorCellSize
    local bucketCount = math.ceil(exteriorCellSize / bucketSize)
    ---@type MCP.TerrainSampleTriangle[]
    local triangles = {}
    ---@type MCP.TerrainSampleTriangleStore
    local triangleStore = {
        firstWeightX = {}, firstWeightY = {}, firstWeightOffset = {},
        secondWeightX = {}, secondWeightY = {}, secondWeightOffset = {},
        heightX = {}, heightY = {}, heightOffset = {}, inverseDenominator = {}, normalZSquared = {},
    }
    local triangleCount = 0
    ---@type table<integer, integer[]>
    local buckets = table.new(bucketCount * bucketCount, 0)
    -- Occupancy is tracked separately so the registration loop never re-evaluates a table length.
    local bucketCounts = table.new(bucketCount * bucketCount, 0)
    local maxBucketIndex = bucketCount - 1
    local transformedVertexCount = 0
    local bucketRegistrationCount = 0
    local bucketOccupancyMax = 0
    local identityTransformNodeCount = 0
    for node in cell.landscape.sceneNode:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        local data = node.data
        if data and data.vertexCount > 0 then
            local transform = this.ResolveWorldTransformScalars(node)
            if transform.isIdentity then
                identityTransformNodeCount = identityTransformNodeCount + 1
            end
            -- The layout is invariant for one sampler, so keep its hot loops branch-free.
            if triangleStorageMode == "soa" then
                local vertices = {
                    x = table.new(data.vertexCount, 0),
                    y = table.new(data.vertexCount, 0),
                    z = table.new(data.vertexCount, 0),
                }
                transformedVertexCount = transformedVertexCount
                    + TransformVerticesToArrays(data.vertices, transform, vertices.x, vertices.y, vertices.z)
                local vertexX, vertexY, vertexZ = vertices.x, vertices.y, vertices.z
                for triangleIndex = 1, data.activeTriangleCount do
                    local sourceTriangle = data.triangles[triangleIndex]
                    local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                    local firstIndex = indices and indices[1] ~= nil and indices[1] + 1 or nil
                    local secondIndex = indices and indices[2] ~= nil and indices[2] + 1 or nil
                    local thirdIndex = indices and indices[3] ~= nil and indices[3] + 1 or nil
                    if firstIndex and secondIndex and thirdIndex
                        and vertexX[firstIndex] ~= nil and vertexX[secondIndex] ~= nil and vertexX[thirdIndex] ~= nil then
                        local firstX, firstY, firstZ = vertexX[firstIndex], vertexY[firstIndex], vertexZ[firstIndex]
                        local secondX, secondY, secondZ = vertexX[secondIndex], vertexY[secondIndex], vertexZ[secondIndex]
                        local thirdX, thirdY, thirdZ = vertexX[thirdIndex], vertexY[thirdIndex], vertexZ[thirdIndex]
                        local abx, aby, abz = secondX - firstX, secondY - firstY, secondZ - firstZ
                        local acx, acy, acz = thirdX - firstX, thirdY - firstY, thirdZ - firstZ
                        local nx = aby * acz - abz * acy
                        local ny = abz * acx - abx * acz
                        local nz = abx * acy - aby * acx
                        local normalLengthSquared = nx * nx + ny * ny + nz * nz
                        local firstWeightX, firstWeightY, firstWeightOffset,
                        secondWeightX, secondWeightY, secondWeightOffset,
                        heightX, heightY, heightOffset, inverseDenominator =
                            this.CalculateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
                        triangleCount = triangleCount + 1
                        local storedIndex = triangleCount
                        triangleStore.firstWeightX[storedIndex], triangleStore.firstWeightY[storedIndex], triangleStore.firstWeightOffset[storedIndex] = firstWeightX, firstWeightY, firstWeightOffset
                        triangleStore.secondWeightX[storedIndex], triangleStore.secondWeightY[storedIndex], triangleStore.secondWeightOffset[storedIndex] = secondWeightX, secondWeightY, secondWeightOffset
                        triangleStore.heightX[storedIndex], triangleStore.heightY[storedIndex], triangleStore.heightOffset[storedIndex] = heightX, heightY, heightOffset
                        triangleStore.inverseDenominator[storedIndex] = inverseDenominator
                        triangleStore.normalZSquared[storedIndex] = normalLengthSquared > 0 and (nz * nz) / normalLengthSquared or 0
                        local minColumn = math.max(0, math.min(maxBucketIndex, math.floor((math.min(firstX, secondX, thirdX) - originX) / bucketSize)))
                        local maxColumn = math.max(0, math.min(maxBucketIndex, math.floor((math.max(firstX, secondX, thirdX) - originX) / bucketSize)))
                        local minRow = math.max(0, math.min(maxBucketIndex, math.floor((math.min(firstY, secondY, thirdY) - originY) / bucketSize)))
                        local maxRow = math.max(0, math.min(maxBucketIndex, math.floor((math.max(firstY, secondY, thirdY) - originY) / bucketSize)))
                        for row = minRow, maxRow do
                            local rowOffset = row * bucketCount + 1
                            for column = minColumn, maxColumn do
                                local bucketIndex = rowOffset + column
                                local bucket = buckets[bucketIndex]
                                if not bucket then
                                    bucket = {}
                                    buckets[bucketIndex] = bucket
                                end
                                local occupancy = (bucketCounts[bucketIndex] or 0) + 1
                                bucket[occupancy] = storedIndex
                                bucketCounts[bucketIndex] = occupancy
                                if occupancy > bucketOccupancyMax then
                                    bucketOccupancyMax = occupancy
                                end
                            end
                        end
                        bucketRegistrationCount = bucketRegistrationCount + (maxRow - minRow + 1) * (maxColumn - minColumn + 1)
                    end
                end
            else
                local vertices = table.new(data.vertexCount, 0)
                transformedVertexCount = transformedVertexCount + TransformVerticesToTables(data.vertices, transform, vertices)
                for triangleIndex = 1, data.activeTriangleCount do
                    local sourceTriangle = data.triangles[triangleIndex]
                    local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                    local first = indices and indices[1] ~= nil and vertices[indices[1] + 1] or nil
                    local second = indices and indices[2] ~= nil and vertices[indices[2] + 1] or nil
                    local third = indices and indices[3] ~= nil and vertices[indices[3] + 1] or nil
                    if first and second and third then
                        local firstX, firstY, firstZ = first.x, first.y, first.z
                        local secondX, secondY, secondZ = second.x, second.y, second.z
                        local thirdX, thirdY, thirdZ = third.x, third.y, third.z
                        local abx, aby, abz = secondX - firstX, secondY - firstY, secondZ - firstZ
                        local acx, acy, acz = thirdX - firstX, thirdY - firstY, thirdZ - firstZ
                        local nx = aby * acz - abz * acy
                        local ny = abz * acx - abx * acz
                        local nz = abx * acy - aby * acx
                        local normalLengthSquared = nx * nx + ny * ny + nz * nz
                        local firstWeightX, firstWeightY, firstWeightOffset,
                        secondWeightX, secondWeightY, secondWeightOffset,
                        heightX, heightY, heightOffset, inverseDenominator =
                            this.CalculateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
                        triangleCount = triangleCount + 1
                        local storedIndex = triangleCount
                        triangles[storedIndex] = {
                            firstWeightX = firstWeightX, firstWeightY = firstWeightY, firstWeightOffset = firstWeightOffset,
                            secondWeightX = secondWeightX, secondWeightY = secondWeightY, secondWeightOffset = secondWeightOffset,
                            heightX = heightX, heightY = heightY, heightOffset = heightOffset,
                            inverseDenominator = inverseDenominator,
                            normalZSquared = normalLengthSquared > 0 and (nz * nz) / normalLengthSquared or 0,
                        }
                        local minColumn = math.max(0, math.min(maxBucketIndex, math.floor((math.min(firstX, secondX, thirdX) - originX) / bucketSize)))
                        local maxColumn = math.max(0, math.min(maxBucketIndex, math.floor((math.max(firstX, secondX, thirdX) - originX) / bucketSize)))
                        local minRow = math.max(0, math.min(maxBucketIndex, math.floor((math.min(firstY, secondY, thirdY) - originY) / bucketSize)))
                        local maxRow = math.max(0, math.min(maxBucketIndex, math.floor((math.max(firstY, secondY, thirdY) - originY) / bucketSize)))
                        for row = minRow, maxRow do
                            local rowOffset = row * bucketCount + 1
                            for column = minColumn, maxColumn do
                                local bucketIndex = rowOffset + column
                                local bucket = buckets[bucketIndex]
                                if not bucket then
                                    bucket = {}
                                    buckets[bucketIndex] = bucket
                                end
                                local occupancy = (bucketCounts[bucketIndex] or 0) + 1
                                bucket[occupancy] = storedIndex
                                bucketCounts[bucketIndex] = occupancy
                                if occupancy > bucketOccupancyMax then
                                    bucketOccupancyMax = occupancy
                                end
                            end
                        end
                        bucketRegistrationCount = bucketRegistrationCount + (maxRow - minRow + 1) * (maxColumn - minColumn + 1)
                    end
                end
            end
        end
    end
    if triangleCount > 0 then
        local sampler = {
            mode = "mesh",
            originX = originX,
            originY = originY,
            bucketSize = bucketSize,
            bucketCount = bucketCount,
            triangles = triangles,
            triangleStore = triangleStore,
            triangleStorageMode = triangleStorageMode,
            buckets = buckets,
            metrics = {
                mode = "mesh",
                triangle_storage_mode = triangleStorageMode,
                bucket_size = bucketSize,
                bucket_count = bucketCount,
                transformed_vertex_count = transformedVertexCount,
                triangle_count = triangleCount,
                bucket_registration_count = bucketRegistrationCount,
                bucket_occupancy_mean = bucketRegistrationCount / (bucketCount * bucketCount),
                bucket_occupancy_max = bucketOccupancyMax,
                identity_transform_node_count = identityTransformNodeCount,
                heightfield_fallback_reason = heightfieldFallbackReason,
                construction_elapsed_milliseconds = (os.clock() - constructionStartedAt) * 1000,
                construction_memory_delta_kilobytes = collectgarbage("count") - constructionMemoryBefore,
            },
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
        triangleStorageMode = triangleStorageMode,
        metrics = {
            mode = "ray",
            triangle_storage_mode = triangleStorageMode,
            transformed_vertex_count = transformedVertexCount,
            triangle_count = 0,
            bucket_registration_count = 0,
            bucket_occupancy_mean = 0,
            bucket_occupancy_max = 0,
            identity_transform_node_count = identityTransformNodeCount,
            heightfield_fallback_reason = heightfieldFallbackReason,
            construction_elapsed_milliseconds = (os.clock() - constructionStartedAt) * 1000,
            construction_memory_delta_kilobytes = collectgarbage("count") - constructionMemoryBefore,
        },
        errorCount = 0,
    }
    setmetatable(sampler, { __index = this })
    return sampler
end

---@class MCP.TerrainLandGridProbe
---@field available boolean False when the landscape scene graph could not be inspected.
---@field error string?
---@field cell_id MCP.CellIdentityKey?
---@field grid_interval number Sampling interval the heightfield hypothesis is tested against.
---@field expected_grid_width integer Grid points per cell axis implied by `grid_interval`.
---@field tri_shape_count integer
---@field transformed_vertex_count integer
---@field triangle_count integer
---@field identity_transform_node_count integer Nodes whose world transform reduced to a translation.
---@field max_transform_difference number Largest world-unit gap between scalar and engine vector transforms.
---@field aligned_vertex_count integer Vertices landing on a cell-local grid point within tolerance.
---@field misaligned_vertex_count integer
---@field max_alignment_error number Largest world-unit distance from a vertex to its nearest grid point.
---@field covered_grid_point_count integer Distinct grid points reached by at least one vertex.
---@field missing_grid_point_count integer
---@field duplicate_grid_point_count integer Repeat vertices produced by patch-boundary sharing.
---@field max_duplicate_height_difference number Largest elevation disagreement between duplicate vertices.
---@field slope_sample_count integer Grid points where both mesh and finite-difference normals were available.
---@field slope_mismatch_count integer Grid points where the two normals disagree on walkability.
---@field slope_angle_bin_degrees number[] Inclusive upper bound of each slope histogram bin.
---@field slope_angle_histogram integer[] Slope samples per bin, using the mesh face-normal angle.
---@field slope_mismatch_histogram integer[] Finite-difference walkability mismatches per bin.
---@field quad_count integer Quads implied by the grid width.
---@field quad_covered_count integer Quads whose diagonal orientation was resolved from mesh triangles.
---@field quad_main_diagonal_count integer Quads split from the lower-left corner to the upper-right corner.
---@field quad_anti_diagonal_count integer Quads split from the lower-right corner to the upper-left corner.
---@field quad_diagonal_conflict_count integer Quads whose two mesh triangles implied different diagonals.
---@field quad_irregular_triangle_count integer Triangles that did not span exactly one grid quad.
---@field quad_diagonal_uniform boolean True when every resolved quad shares one diagonal orientation.
---@field quad_checkerboard_match_count integer Quads matching a `(column + row)` parity rule; the inverse count is `quad_covered_count` minus this.
---@field quad_rule_mismatch_columns integer[] Columns of the first quads breaking the checkerboard rule.
---@field quad_rule_mismatch_rows integer[] Rows paired with `quad_rule_mismatch_columns`.
---@field quad_row_parity_match_count integer Quads matching a row parity rule.
---@field quad_column_parity_match_count integer Quads matching a column parity rule.
---@field face_normal_sample_count integer Grid points with at least one reconstructable adjacent face.
---@field face_normal_match_count integer Grid points where a reconstructed face normal matched the mesh normal.
---@field face_normal_max_difference number Largest gap between the mesh normal and its closest reconstruction.
---@field max_height_difference number Largest elevation gap between mesh sampling and heightfield lookup.
---@field elapsed_milliseconds number
---@field memory_delta_kilobytes number

local diagonalTriangles = {
    [mainDiagonal] = { { 1, 2, 4 }, { 1, 4, 3 } },
    [antiDiagonal] = { { 1, 2, 3 }, { 2, 4, 3 } },
}

--- Decide which diagonal splits the grid quad covered by one land triangle.
--- A land triangle occupies three corners of a single unit quad, so the two present opposite corners name the split.
--- Triangles that do not span exactly one quad return nil, which the caller reports as irregular geometry.
---@param firstColumn integer
---@param firstRow integer
---@param secondColumn integer
---@param secondRow integer
---@param thirdColumn integer
---@param thirdRow integer
---@return integer? diagonal `mainDiagonal` for a lower-left to upper-right split, `antiDiagonal` otherwise.
---@return integer? quadColumn
---@return integer? quadRow
function this.ClassifyQuadDiagonal(firstColumn, firstRow, secondColumn, secondRow, thirdColumn, thirdRow)
    local minColumn = math.min(firstColumn, secondColumn, thirdColumn)
    local minRow = math.min(firstRow, secondRow, thirdRow)
    if math.max(firstColumn, secondColumn, thirdColumn) - minColumn ~= 1
        or math.max(firstRow, secondRow, thirdRow) - minRow ~= 1 then
        return nil, nil, nil
    end
    local corners = { false, false, false, false }
    corners[(firstRow - minRow) * 2 + (firstColumn - minColumn) + 1] = true
    corners[(secondRow - minRow) * 2 + (secondColumn - minColumn) + 1] = true
    corners[(thirdRow - minRow) * 2 + (thirdColumn - minColumn) + 1] = true
    if corners[1] and corners[4] and not (corners[2] and corners[3]) then
        return mainDiagonal, minColumn, minRow
    end
    if corners[2] and corners[3] and not (corners[1] and corners[4]) then
        return antiDiagonal, minColumn, minRow
    end
    return nil, nil, nil
end

--- Resolve one quad corner into world coordinates and its heightfield elevation.
---@param heights number[]
---@param width integer
---@param originX number
---@param originY number
---@param interval number
---@param quadColumn integer
---@param quadRow integer
---@param cornerId integer
---@return number x
---@return number y
---@return number? z
local function QuadCorner(heights, width, originX, originY, interval, quadColumn, quadRow, cornerId)
    local column = quadColumn + (cornerId - 1) % 2
    local row = quadRow + math.floor((cornerId - 1) / 2)
    return originX + column * interval, originY + row * interval, heights[row * width + column + 1]
end

--- Compute the squared upward component of a triangle's unit face normal.
---@return number
local function FaceNormalZSquared(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
    local abx, aby, abz = secondX - firstX, secondY - firstY, secondZ - firstZ
    local acx, acy, acz = thirdX - firstX, thirdY - firstY, thirdZ - firstZ
    local nx = aby * acz - abz * acy
    local ny = abz * acx - abx * acz
    local nz = abx * acy - aby * acx
    local normalLengthSquared = nx * nx + ny * ny + nz * nz
    return normalLengthSquared > 0 and (nz * nz) / normalLengthSquared or 0
end

--- Estimate one axis gradient from neighbouring heightfield samples.
--- Border points fall back to a one-sided difference because no opposite neighbour exists.
---@param heights number[]
---@param index integer
---@param stride integer
---@param hasLower boolean
---@param hasUpper boolean
---@param interval number
---@return number?
local function HeightGradient(heights, index, stride, hasLower, hasUpper, interval)
    local lower = hasLower and heights[index - stride] or nil
    local upper = hasUpper and heights[index + stride] or nil
    if lower and upper then
        return (upper - lower) / (2 * interval)
    end
    local center = heights[index]
    if upper then
        return (upper - center) / interval
    end
    if lower then
        return (center - lower) / interval
    end
    return nil
end

--- Measure whether the active landscape mesh can be replaced by a direct heightfield lookup.
--- The probe answers the open questions for that redesign: transform-flattening correctness, grid alignment,
--- coverage, duplicate agreement, quad diagonal orientation, and how closely the two candidate normal
--- reconstructions (finite difference and exact face normal) reproduce mesh walkability.
---@param cell tes3cell?
---@return MCP.TerrainLandGridProbe
function this.ProbeLandGridAlignment(cell)
    local startedAt = os.clock()
    local memoryBefore = collectgarbage("count")
    local interval = parameters.interval
    local width = math.floor(exteriorCellSize / interval) + 1
    local quadWidth = width - 1
    -- Bins are dense around the walkable threshold because that is where a normal approximation can flip a decision.
    local slopeAngleBins = { 10, 20, 30, 40, 44, 46, 48, 52, 60, 90 }
    local slopeAngleHistogram = {}
    local slopeMismatchHistogram = {}
    for index = 1, table.size(slopeAngleBins) do
        slopeAngleHistogram[index] = 0
        slopeMismatchHistogram[index] = 0
    end
    local result = {
        available = false,
        cell_id = cell and cellutil.GetIdentityKey(cell) or nil,
        grid_interval = interval,
        expected_grid_width = width,
        tri_shape_count = 0,
        transformed_vertex_count = 0,
        triangle_count = 0,
        identity_transform_node_count = 0,
        max_transform_difference = 0,
        aligned_vertex_count = 0,
        misaligned_vertex_count = 0,
        max_alignment_error = 0,
        covered_grid_point_count = 0,
        missing_grid_point_count = width * width,
        duplicate_grid_point_count = 0,
        max_duplicate_height_difference = 0,
        slope_sample_count = 0,
        slope_mismatch_count = 0,
        slope_angle_bin_degrees = slopeAngleBins,
        slope_angle_histogram = slopeAngleHistogram,
        slope_mismatch_histogram = slopeMismatchHistogram,
        quad_count = quadWidth * quadWidth,
        quad_covered_count = 0,
        quad_main_diagonal_count = 0,
        quad_anti_diagonal_count = 0,
        quad_diagonal_conflict_count = 0,
        quad_irregular_triangle_count = 0,
        quad_diagonal_uniform = false,
        quad_checkerboard_match_count = 0,
        quad_rule_mismatch_columns = {},
        quad_rule_mismatch_rows = {},
        quad_row_parity_match_count = 0,
        quad_column_parity_match_count = 0,
        face_normal_sample_count = 0,
        face_normal_match_count = 0,
        face_normal_max_difference = 0,
        max_height_difference = 0,
        elapsed_milliseconds = 0,
        memory_delta_kilobytes = 0,
    }
    if not cell or cell.isInterior or not cell.landscape or not cell.landscape.sceneNode then
        result.error = "An active exterior landscape scene graph is required."
        result.elapsed_milliseconds = (os.clock() - startedAt) * 1000
        return result
    end

    local originX = cell.gridX * exteriorCellSize
    local originY = cell.gridY * exteriorCellSize
    local heights = table.new(width * width, 0)
    ---@type table<integer, integer>
    local diagonals = table.new(quadWidth * quadWidth, 0)
    -- Tolerance is expressed in world units so it stays meaningful for any sampling interval.
    local alignmentTolerance = interval * 0.01
    for node in cell.landscape.sceneNode:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        local data = node.data
        if data and data.vertexCount > 0 then
            result.tri_shape_count = result.tri_shape_count + 1
            result.triangle_count = result.triangle_count + data.activeTriangleCount
            local transform = this.ResolveWorldTransformScalars(node)
            if transform.isIdentity then
                result.identity_transform_node_count = result.identity_transform_node_count + 1
            end
            local worldTransform = node.worldTransform
            local scale = transform.scale
            local vertexColumn = table.new(data.vertexCount, 0)
            local vertexRow = table.new(data.vertexCount, 0)
            for vertexIndex, vertex in ipairs(data.vertices) do
                local vx, vy, vz = vertex.x, vertex.y, vertex.z
                local wx = (transform.r00 * vx + transform.r01 * vy + transform.r02 * vz) * scale + transform.tx
                local wy = (transform.r10 * vx + transform.r11 * vy + transform.r12 * vz) * scale + transform.ty
                local wz = (transform.r20 * vx + transform.r21 * vy + transform.r22 * vz) * scale + transform.tz
                -- Cross-check the flattened transform against the engine operator it replaces in construction.
                local reference = worldTransform * vertex
                local difference = math.max(math.abs(wx - reference.x), math.abs(wy - reference.y),
                    math.abs(wz - reference.z))
                if difference > result.max_transform_difference then
                    result.max_transform_difference = difference
                end
                result.transformed_vertex_count = result.transformed_vertex_count + 1

                local columnValue = (wx - originX) / interval
                local rowValue = (wy - originY) / interval
                local column = math.floor(columnValue + 0.5)
                local row = math.floor(rowValue + 0.5)
                local alignmentError = math.max(math.abs(columnValue - column), math.abs(rowValue - row)) * interval
                if alignmentError > result.max_alignment_error then
                    result.max_alignment_error = alignmentError
                end
                if alignmentError <= alignmentTolerance
                    and column >= 0 and row >= 0 and column < width and row < width then
                    result.aligned_vertex_count = result.aligned_vertex_count + 1
                    vertexColumn[vertexIndex], vertexRow[vertexIndex] = column, row
                    local index = row * width + column + 1
                    local existing = heights[index]
                    if existing == nil then
                        heights[index] = wz
                        result.covered_grid_point_count = result.covered_grid_point_count + 1
                    else
                        result.duplicate_grid_point_count = result.duplicate_grid_point_count + 1
                        local heightDifference = math.abs(existing - wz)
                        if heightDifference > result.max_duplicate_height_difference then
                            result.max_duplicate_height_difference = heightDifference
                        end
                    end
                else
                    result.misaligned_vertex_count = result.misaligned_vertex_count + 1
                end
            end

            -- Diagonal orientation decides whether a heightfield can rebuild the exact mesh faces.
            for triangleIndex = 1, data.activeTriangleCount do
                local sourceTriangle = data.triangles[triangleIndex]
                local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                local firstIndex = indices and indices[1] ~= nil and indices[1] + 1 or nil
                local secondIndex = indices and indices[2] ~= nil and indices[2] + 1 or nil
                local thirdIndex = indices and indices[3] ~= nil and indices[3] + 1 or nil
                local diagonal, quadColumn, quadRow = nil, nil, nil
                if firstIndex and secondIndex and thirdIndex
                    and vertexColumn[firstIndex] and vertexColumn[secondIndex] and vertexColumn[thirdIndex] then
                    diagonal, quadColumn, quadRow = this.ClassifyQuadDiagonal(
                        vertexColumn[firstIndex], vertexRow[firstIndex],
                        vertexColumn[secondIndex], vertexRow[secondIndex],
                        vertexColumn[thirdIndex], vertexRow[thirdIndex])
                end
                if diagonal and quadColumn and quadRow then
                    local quadIndex = quadRow * quadWidth + quadColumn + 1
                    local existing = diagonals[quadIndex]
                    if existing == nil then
                        diagonals[quadIndex] = diagonal
                        result.quad_covered_count = result.quad_covered_count + 1
                        if diagonal == mainDiagonal then
                            result.quad_main_diagonal_count = result.quad_main_diagonal_count + 1
                        else
                            result.quad_anti_diagonal_count = result.quad_anti_diagonal_count + 1
                        end
                    elseif existing ~= diagonal then
                        result.quad_diagonal_conflict_count = result.quad_diagonal_conflict_count + 1
                    end
                else
                    result.quad_irregular_triangle_count = result.quad_irregular_triangle_count + 1
                end
            end
        end
    end
    result.missing_grid_point_count = width * width - result.covered_grid_point_count
    result.quad_diagonal_uniform = result.quad_diagonal_conflict_count == 0
        and (result.quad_main_diagonal_count == 0 or result.quad_anti_diagonal_count == 0)

    -- A positional rule would let construction skip the triangle scan entirely, so candidate rules are counted.
    -- Only the first few violating quads are reported; the counts already state how widespread a break is.
    local ruleMismatchCount = 0
    for quadRow = 0, quadWidth - 1 do
        for quadColumn = 0, quadWidth - 1 do
            local diagonal = diagonals[quadRow * quadWidth + quadColumn + 1]
            if diagonal then
                local isMain = diagonal == mainDiagonal
                if isMain == ((quadColumn + quadRow) % 2 == 0) then
                    result.quad_checkerboard_match_count = result.quad_checkerboard_match_count + 1
                elseif ruleMismatchCount < quadRuleMismatchSampleLimit then
                    ruleMismatchCount = ruleMismatchCount + 1
                    result.quad_rule_mismatch_columns[ruleMismatchCount] = quadColumn
                    result.quad_rule_mismatch_rows[ruleMismatchCount] = quadRow
                end
                if isMain == (quadRow % 2 == 0) then
                    result.quad_row_parity_match_count = result.quad_row_parity_match_count + 1
                end
                if isMain == (quadColumn % 2 == 0) then
                    result.quad_column_parity_match_count = result.quad_column_parity_match_count + 1
                end
            end
        end
    end

    -- Both candidate normal reconstructions are compared against triangle mesh sampling, which is the reference the
    -- heightfield source must reproduce; the production default would otherwise return a heightfield and measure nothing.
    local sampler = this.CreateCellSampler(cell, nil, nil, "mesh")
    if sampler and sampler.mode == "mesh" then
        local walkableThreshold = math.cos(math.rad(parameters.maxSlopeDegrees)) ^ 2
        local binCount = table.size(slopeAngleBins)
        for row = 0, width - 1 do
            for column = 0, width - 1 do
                local index = row * width + column + 1
                if heights[index] then
                    local meshHeight, meshNormalZSquared =
                        sampler:Sample(originX + column * interval, originY + row * interval)
                    if meshHeight and meshNormalZSquared then
                        local heightDifference = math.abs(meshHeight - heights[index])
                        if heightDifference > result.max_height_difference then
                            result.max_height_difference = heightDifference
                        end
                        local meshAngle = math.deg(math.acos(math.min(1, math.sqrt(meshNormalZSquared))))
                        local bin = binCount
                        for binIndex = 1, binCount do
                            if meshAngle <= slopeAngleBins[binIndex] then
                                bin = binIndex
                                break
                            end
                        end

                        local gradientX = HeightGradient(heights, index, 1, column > 0, column < width - 1, interval)
                        local gradientY = HeightGradient(heights, index, width, row > 0, row < width - 1, interval)
                        if gradientX and gradientY then
                            result.slope_sample_count = result.slope_sample_count + 1
                            slopeAngleHistogram[bin] = slopeAngleHistogram[bin] + 1
                            local fieldNormalZSquared = 1 / (1 + gradientX * gradientX + gradientY * gradientY)
                            if (fieldNormalZSquared >= walkableThreshold) ~= (meshNormalZSquared >= walkableThreshold) then
                                result.slope_mismatch_count = result.slope_mismatch_count + 1
                                slopeMismatchHistogram[bin] = slopeMismatchHistogram[bin] + 1
                            end
                        end

                        -- Rebuilding the adjacent faces shows whether the exact mesh normal survives the redesign.
                        local closestDifference = nil
                        for quadRow = row - 1, row do
                            for quadColumn = column - 1, column do
                                if quadRow >= 0 and quadColumn >= 0 and quadRow < quadWidth and quadColumn < quadWidth then
                                    local diagonal = diagonals[quadRow * quadWidth + quadColumn + 1]
                                    if diagonal then
                                        local cornerId = (row - quadRow) * 2 + (column - quadColumn) + 1
                                        for _, triple in ipairs(diagonalTriangles[diagonal]) do
                                            if triple[1] == cornerId or triple[2] == cornerId or triple[3] == cornerId then
                                                local firstX, firstY, firstZ = QuadCorner(heights, width, originX, originY, interval, quadColumn, quadRow, triple[1])
                                                local secondX, secondY, secondZ = QuadCorner(heights, width, originX, originY, interval, quadColumn, quadRow, triple[2])
                                                local thirdX, thirdY, thirdZ = QuadCorner(heights, width, originX, originY, interval, quadColumn, quadRow, triple[3])
                                                if firstZ and secondZ and thirdZ then
                                                    local candidate = FaceNormalZSquared(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
                                                    local candidateDifference = math.abs(candidate - meshNormalZSquared)
                                                    if closestDifference == nil or candidateDifference < closestDifference then
                                                        closestDifference = candidateDifference
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if closestDifference then
                            result.face_normal_sample_count = result.face_normal_sample_count + 1
                            if closestDifference <= 0.000001 then
                                result.face_normal_match_count = result.face_normal_match_count + 1
                            end
                            if closestDifference > result.face_normal_max_difference then
                                result.face_normal_max_difference = closestDifference
                            end
                        end
                    end
                end
            end
        end
    end
    if sampler then
        sampler:Release()
    end

    result.available = true
    result.elapsed_milliseconds = (os.clock() - startedAt) * 1000
    result.memory_delta_kilobytes = collectgarbage("count") - memoryBefore
    return result
end

return this
