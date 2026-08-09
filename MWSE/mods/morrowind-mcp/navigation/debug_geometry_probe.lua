--- Minimal runtime geometry probe isolated from pathfinding and terrain navigation state.
--- It verifies that MWSE can create an NiTriShape and render it from the active world camera.
local this = {}

---@class MCP.DebugGeometryProbe
---@field logger mwseLogger
---@field root niNode?
---@field parent niNode?
local instance = {
    logger = require("morrowind-mcp.logger").Get({ moduleName = "debug_geometry_probe" }),
    root = nil,
    parent = nil,
}

--- Detach the probe before the camera root is replaced or the server is shut down.
function this.Remove()
    if instance.root and instance.parent then
        instance.parent:detachChild(instance.root)
        instance.parent:update()
        instance.logger:info("Removed runtime NiTriShape geometry probe.")
    end
    instance.root = nil
    instance.parent = nil
end

--- Create one double-sided solid line segment in camera-local space and attach it to the first-person camera root.
--- The line is represented as two triangles, avoiding the unavailable NiLines and NiWireframeProperty constructors.
---@return boolean created
---@return string? errorMessage
function this.Add()
    this.Remove()
    local worldController = tes3.worldController
    local camera = worldController and worldController.armCamera or nil
    local parent = camera and camera.cameraRoot or nil
    if not parent then
        return false, "First-person camera root is unavailable."
    end

    local root = niNode.new()
    root.name = "MorrowindMCP:RuntimeGeometryProbe"
    -- Inspect It's camera-root convention uses positive local Y as the forward viewing direction.
    root.translation = tes3vector3.new(0, 128, 0)

    local shape = niTriShape.new(4, false, true, 0, 2)
    shape.name = "MorrowindMCP:RuntimeGeometryProbeSolidLine"
    shape.data.vertices[1] = tes3vector3.new(-30, 0, -1)
    shape.data.vertices[2] = tes3vector3.new(30, 0, -1)
    shape.data.vertices[3] = tes3vector3.new(30, 0, 1)
    shape.data.vertices[4] = tes3vector3.new(-30, 0, 1)
    -- Emissive vertex colors keep this diagnostic geometry independent of scene lights.
    shape.data.colors[1] = niPackedColor.new(48, 224, 255, 255)
    shape.data.colors[2] = niPackedColor.new(48, 224, 255, 255)
    shape.data.colors[3] = niPackedColor.new(48, 224, 255, 255)
    shape.data.colors[4] = niPackedColor.new(48, 224, 255, 255)
    -- Reverse the winding so the camera sees the former back face during this double-sided probe.
    shape.data.triangles[1] = niTriangle.new(2, 1, 0)
    shape.data.triangles[2] = niTriangle.new(3, 2, 0)
    shape.data.activeTriangleCount = 2
    shape.data:markAsChanged()
    shape.data:updateModelBound()
    local vertexColor = niVertexColorProperty.new()
    vertexColor.lighting = ni.lightingMode.emissive
    vertexColor.source = ni.sourceVertexMode.emissive
    shape.vertexColorProperty = vertexColor
    -- Force both face orientations while keeping all stencil tests non-mutating.
    local stencil = niStencilProperty.new()
    stencil.enabled = true
    stencil.testFunc = ni.stencilTestFunction.always
    stencil.failAction = ni.stencilTestAction.keep
    stencil.passAction = ni.stencilTestAction.keep
    stencil.zFailAction = ni.stencilTestAction.keep
    stencil.drawMode = ni.stencilDrawMode.both
    shape.stencilProperty = stencil
    root:attachChild(shape)
    parent:attachChild(root)
    root:update()
    parent:update()

    instance.root = root
    instance.parent = parent
    instance.logger:info("Attached runtime NiTriShape geometry probe to the first-person camera root.")
    return true, nil
end

return this