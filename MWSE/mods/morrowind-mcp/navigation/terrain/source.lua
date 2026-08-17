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
---@field mode "mesh"|"ray" Terrain sampling implementation selected at construction.
---@field triangle_storage_mode "aos"|"soa" Shared representation used for temporary vertices and completed terrain triangles.
---@field bucket_size number? Spatial bucket width used by mesh sampling.
---@field bucket_count integer? Number of buckets per cell axis for mesh sampling.
---@field transformed_vertex_count integer Number of source vertices transformed into world space.
---@field triangle_count integer Number of usable land triangles stored by the sampler.
---@field bucket_registration_count integer Number of triangle-to-bucket registrations.
---@field bucket_occupancy_mean number Mean registrations per spatial bucket.
---@field bucket_occupancy_max integer Largest number of triangle registrations in one bucket.
---@field construction_elapsed_milliseconds number Wall-clock duration of sampler construction.
---@field construction_memory_delta_kilobytes number Lua heap delta observed during sampler construction.

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
---@field triangleStore MCP.TerrainSampleTriangleStore?
---@field triangleStorageMode "aos"|"soa"
---@field buckets table<integer, integer[]>?
---@field metrics MCP.TerrainSamplerMetrics Construction diagnostics retained after Release.
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

--- Derive reusable barycentric and height-plane coefficients from one world-space triangle.
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
--- Mesh mode uses spatial buckets; ray mode is a compatibility fallback restricted to the cell landscape root.
---@param x number
---@param y number
---@return number? height
---@return number? normalZSquared
function this:Sample(x, y)
    if self.mode == "mesh" then
        local column = Clamp(math.floor((x - self.originX) / self.bucketSize), 0, self.bucketCount - 1)
        local row = Clamp(math.floor((y - self.originY) / self.bucketSize), 0, self.bucketCount - 1)
        local bucket = self.buckets[row * self.bucketCount + column + 1]
        local bestHeight, bestNormalZSquared = nil, nil
        for _, triangleIndex in ipairs(bucket or {}) do
            local height, normalZSquared
            if self.triangleStorageMode == "soa" then
                height = SampleTriangleStore(self.triangleStore, triangleIndex, x, y)
                normalZSquared = self.triangleStore.normalZSquared[triangleIndex]
            else
                local triangle = self.triangles[triangleIndex]
                height = SampleTriangle(triangle, x, y)
                normalZSquared = triangle.normalZSquared
            end
            if height and (bestHeight == nil or height > bestHeight) then
                bestHeight = height
                bestNormalZSquared = normalZSquared
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
end

--- Build a cell-local terrain sampler from transformed land triangles.
--- Current MWSE exposes triangle indices through `vertices`; a cell-root ray sampler is returned only as fallback.
---@param cell tes3cell
---@param bucketSize number? Spatial bucket width in world units.
---@param triangleStorageMode "aos"|"soa"? Shared temporary-vertex and completed-triangle representation; the production default is SoA.
---@return MCP.TerrainSampler?
---@return string?
function this.CreateCellSampler(cell, bucketSize, triangleStorageMode)
    local constructionStartedAt = os.clock()
    local constructionMemoryBefore = collectgarbage("count")
    if not cell or cell.isInterior or not cell.landscape or not cell.landscape.sceneNode then
        return nil, "Active exterior landscape scene graph is unavailable."
    end
    bucketSize = bucketSize or 128
    triangleStorageMode = triangleStorageMode or "soa"
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
    local transformedVertexCount = 0
    local bucketRegistrationCount = 0
    local bucketOccupancyMax = 0
    for node in cell.landscape.sceneNode:traverse({ type = ni.type.NiTriShape }) do
        ---@cast node niTriShape
        local data = node.data
        if data and data.vertexCount > 0 then
            -- The layout is invariant for one sampler, so keep its hot loops branch-free.
            if triangleStorageMode == "soa" then
                local vertices = {
                    x = table.new(data.vertexCount, 0),
                    y = table.new(data.vertexCount, 0),
                    z = table.new(data.vertexCount, 0),
                }
                for index, vertex in ipairs(data.vertices) do
                    local world = node.worldTransform * vertex:copy()
                    vertices.x[index], vertices.y[index], vertices.z[index] = world.x, world.y, world.z
                    transformedVertexCount = transformedVertexCount + 1
                end
                for triangleIndex = 1, data.activeTriangleCount do
                    local sourceTriangle = data.triangles[triangleIndex]
                    local indices = sourceTriangle and sourceTriangle.vertices or nil ---@diagnostic disable-line: undefined-field
                    local firstIndex = indices and indices[1] ~= nil and indices[1] + 1 or nil
                    local secondIndex = indices and indices[2] ~= nil and indices[2] + 1 or nil
                    local thirdIndex = indices and indices[3] ~= nil and indices[3] + 1 or nil
                    if firstIndex and secondIndex and thirdIndex
                        and vertices.x[firstIndex] ~= nil and vertices.x[secondIndex] ~= nil and vertices.x[thirdIndex] ~= nil then
                        local firstX, firstY, firstZ = vertices.x[firstIndex], vertices.y[firstIndex], vertices.z[firstIndex]
                        local secondX, secondY, secondZ = vertices.x[secondIndex], vertices.y[secondIndex], vertices.z[secondIndex]
                        local thirdX, thirdY, thirdZ = vertices.x[thirdIndex], vertices.y[thirdIndex], vertices.z[thirdIndex]
                        local abx, aby, abz = secondX - firstX, secondY - firstY, secondZ - firstZ
                        local acx, acy, acz = thirdX - firstX, thirdY - firstY, thirdZ - firstZ
                        local nx = aby * acz - abz * acy
                        local ny = abz * acx - abx * acz
                        local nz = abx * acy - aby * acx
                        local normalLengthSquared = nx * nx + ny * ny + nz * nz
                        local coefficients = this.CreateTriangleCoefficients(firstX, firstY, firstZ, secondX, secondY, secondZ, thirdX, thirdY, thirdZ)
                        triangleCount = triangleCount + 1
                        local storedIndex = triangleCount
                        triangleStore.firstWeightX[storedIndex], triangleStore.firstWeightY[storedIndex], triangleStore.firstWeightOffset[storedIndex] = coefficients.firstWeightX, coefficients.firstWeightY, coefficients.firstWeightOffset
                        triangleStore.secondWeightX[storedIndex], triangleStore.secondWeightY[storedIndex], triangleStore.secondWeightOffset[storedIndex] = coefficients.secondWeightX, coefficients.secondWeightY, coefficients.secondWeightOffset
                        triangleStore.heightX[storedIndex], triangleStore.heightY[storedIndex], triangleStore.heightOffset[storedIndex] = coefficients.heightX, coefficients.heightY, coefficients.heightOffset
                        triangleStore.inverseDenominator[storedIndex] = coefficients.inverseDenominator
                        triangleStore.normalZSquared[storedIndex] = normalLengthSquared > 0 and (nz * nz) / normalLengthSquared or 0
                        local minColumn = Clamp(math.floor((math.min(firstX, secondX, thirdX) - originX) / bucketSize), 0, bucketCount - 1)
                        local maxColumn = Clamp(math.floor((math.max(firstX, secondX, thirdX) - originX) / bucketSize), 0, bucketCount - 1)
                        local minRow = Clamp(math.floor((math.min(firstY, secondY, thirdY) - originY) / bucketSize), 0, bucketCount - 1)
                        local maxRow = Clamp(math.floor((math.max(firstY, secondY, thirdY) - originY) / bucketSize), 0, bucketCount - 1)
                        for row = minRow, maxRow do
                            for column = minColumn, maxColumn do
                                local bucketIndex = row * bucketCount + column + 1
                                buckets[bucketIndex] = buckets[bucketIndex] or {}
                                table.insert(buckets[bucketIndex], storedIndex)
                                bucketRegistrationCount = bucketRegistrationCount + 1
                                bucketOccupancyMax = math.max(bucketOccupancyMax, #buckets[bucketIndex])
                            end
                        end
                    end
                end
            else
                local vertices = table.new(data.vertexCount, 0)
                for index, vertex in ipairs(data.vertices) do
                    local world = node.worldTransform * vertex:copy()
                    vertices[index] = { x = world.x, y = world.y, z = world.z }
                    transformedVertexCount = transformedVertexCount + 1
                end
                for triangleIndex = 1, data.activeTriangleCount do
                    local sourceTriangle = data.triangles[triangleIndex]
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
                        local normalLengthSquared = nx * nx + ny * ny + nz * nz
                        local coefficients = this.CreateTriangleCoefficients(first.x, first.y, first.z, second.x, second.y, second.z, third.x, third.y, third.z)
                        triangleCount = triangleCount + 1
                        local storedIndex = triangleCount
                        triangles[storedIndex] = {
                            firstWeightX = coefficients.firstWeightX, firstWeightY = coefficients.firstWeightY, firstWeightOffset = coefficients.firstWeightOffset,
                            secondWeightX = coefficients.secondWeightX, secondWeightY = coefficients.secondWeightY, secondWeightOffset = coefficients.secondWeightOffset,
                            heightX = coefficients.heightX, heightY = coefficients.heightY, heightOffset = coefficients.heightOffset,
                            inverseDenominator = coefficients.inverseDenominator,
                            normalZSquared = normalLengthSquared > 0 and (nz * nz) / normalLengthSquared or 0,
                        }
                        local minColumn = Clamp(math.floor((math.min(first.x, second.x, third.x) - originX) / bucketSize), 0, bucketCount - 1)
                        local maxColumn = Clamp(math.floor((math.max(first.x, second.x, third.x) - originX) / bucketSize), 0, bucketCount - 1)
                        local minRow = Clamp(math.floor((math.min(first.y, second.y, third.y) - originY) / bucketSize), 0, bucketCount - 1)
                        local maxRow = Clamp(math.floor((math.max(first.y, second.y, third.y) - originY) / bucketSize), 0, bucketCount - 1)
                        for row = minRow, maxRow do
                            for column = minColumn, maxColumn do
                                local bucketIndex = row * bucketCount + column + 1
                                buckets[bucketIndex] = buckets[bucketIndex] or {}
                                table.insert(buckets[bucketIndex], storedIndex)
                                bucketRegistrationCount = bucketRegistrationCount + 1
                                bucketOccupancyMax = math.max(bucketOccupancyMax, #buckets[bucketIndex])
                            end
                        end
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
            construction_elapsed_milliseconds = (os.clock() - constructionStartedAt) * 1000,
            construction_memory_delta_kilobytes = collectgarbage("count") - constructionMemoryBefore,
        },
        errorCount = 0,
    }
    setmetatable(sampler, { __index = this })
    return sampler
end

return this
