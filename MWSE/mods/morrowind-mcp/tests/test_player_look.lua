local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local playerLook = require("morrowind-mcp.util.player_look")

    unitwind:start("morrowind-mcp.util.player_look")

    unitwind:test("ResolveTarget selects the nearest active reference with a matching ID", function()
        local farReference = {
            id = "shared_id",
            position = { x = 50, y = 0, z = 0 },
            object = { objectType = tes3.objectType.static },
            isValid = function() return true end,
        }
        local nearReference = {
            id = "shared_id",
            position = { x = 10, y = 0, z = 0 },
            object = { objectType = tes3.objectType.static },
            isValid = function() return true end,
        }
        local cells = {
            {
                activators = { size = 0 },
                actors = { size = 0 },
                statics = { size = 2, head = farReference },
            },
        }
        farReference.nextNode = nearReference
        nearReference.nextNode = nil
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 } })
        unitwind:mock(tes3, "getActiveCells", function() return cells end)

        local target = playerLook.ResolveTarget("shared_id")

        unitwind:expect(target ~= nil).toBe(true)
        if not target then
            return
        end
        unitwind:expect(target.reference).toBe(nearReference)
        unitwind:expect(target.pointKind).toBe("reference_position")
        unitwind:expect(target.point.x).toBe(10)
    end)

    unitwind:test("GetReferenceLookPoint prefers a loaded NPC head node", function()
        local reference = {
            position = { x = 1, y = 2, z = 3 },
            object = { objectType = tes3.objectType.npc },
            animationData = { headNode = { worldTransform = { translation = { x = 4, y = 5, z = 6 } } } },
        }

        local point, pointKind = playerLook.GetReferenceLookPoint(reference)

        unitwind:expect(pointKind).toBe("npc_head")
        unitwind:expect(point.x).toBe(4)
        unitwind:expect(point.y).toBe(5)
        unitwind:expect(point.z).toBe(6)
    end)

    unitwind:test("GetReferenceLookPoint falls back to an NPC head attachment", function()
        local reference = {
            position = { x = 1, y = 2, z = 3 },
            object = { objectType = tes3.objectType.npc },
            bodyPartManager = {
                getAttachNode = function()
                    return { node = { worldTransform = { translation = { x = 7, y = 8, z = 9 } } } }
                end,
            },
        }

        local point, pointKind = playerLook.GetReferenceLookPoint(reference)

        unitwind:expect(pointKind).toBe("npc_head")
        unitwind:expect(point.x).toBe(7)
        unitwind:expect(point.y).toBe(8)
        unitwind:expect(point.z).toBe(9)
    end)

    unitwind:test("GetReferenceLookPoint estimates an NPC eye height without a head node", function()
        local reference = {
            position = { x = 10, y = 20, z = 30 },
            object = { objectType = tes3.objectType.npc },
            mobile = { height = 200 },
        }
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 } })
        unitwind:mock(tes3, "mobilePlayer", { height = 100 })
        unitwind:mock(tes3, "getPlayerEyePosition", function() return { x = 0, y = 0, z = 75 } end)

        local point, pointKind = playerLook.GetReferenceLookPoint(reference)

        unitwind:expect(pointKind).toBe("npc_estimated_eye")
        unitwind:expect(point.x).toBe(10)
        unitwind:expect(point.y).toBe(20)
        unitwind:expect(point.z).toBe(180)
    end)

    unitwind:test("GetReferenceLookPoint uses a non-NPC bounding box center", function()
        local reference = {
            position = { x = 1, y = 2, z = 3 },
            object = { objectType = tes3.objectType.static },
            sceneNode = { worldBoundOrigin = { x = 4, y = 5, z = 6 } },
        }

        local point, pointKind = playerLook.GetReferenceLookPoint(reference)

        unitwind:expect(pointKind).toBe("bounding_box_center")
        unitwind:expect(point.x).toBe(4)
        unitwind:expect(point.y).toBe(5)
        unitwind:expect(point.z).toBe(6)
    end)

    unitwind:test("ResolveTarget ignores invalid and mismatched references", function()
        local invalidReference = {
            id = "shared_id",
            position = { x = 1, y = 0, z = 0 },
            object = { objectType = tes3.objectType.static },
            isValid = function() return false end,
        }
        local mismatchedReference = {
            id = "other_id",
            position = { x = 2, y = 0, z = 0 },
            object = { objectType = tes3.objectType.static },
            isValid = function() return true end,
        }
        local matchingReference = {
            id = "shared_id",
            position = { x = 3, y = 0, z = 0 },
            object = { objectType = tes3.objectType.static },
            isValid = function() return true end,
        }
        invalidReference.nextNode = mismatchedReference
        mismatchedReference.nextNode = matchingReference
        matchingReference.nextNode = nil
        local cells = {
            { activators = { size = 0 }, actors = { size = 0 }, statics = { size = 3, head = invalidReference } },
        }
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 } })
        unitwind:mock(tes3, "getActiveCells", function() return cells end)

        local target = playerLook.ResolveTarget("shared_id")

        unitwind:expect(target ~= nil).toBe(true)
        if target then
            unitwind:expect(target.reference).toBe(matchingReference)
        end
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
