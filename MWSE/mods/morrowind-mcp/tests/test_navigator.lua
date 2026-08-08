local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({ enabled = true, highlight = false })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end
    local navigator = require("morrowind-mcp.util.navigator")
    local inputAction = require("morrowind-mcp.util.input_action")

    --- Build the minimal graph data used to snapshot a route.
    local function Graph(edgeKind)
        return {
            edgeKind = edgeKind,
            nodes = {
                [1] = { position = { x = 0, y = 0, z = 0 } },
                [2] = { position = { x = 100, y = 0, z = 0 } },
            },
            edges = { [1] = { kind = edgeKind.walk } },
            FindPath = function() return { nodeIds = { 1, 2 }, edgeIds = { 1 } } end,
        }
    end

    unitwind:start("morrowind-mcp.util.navigator")

    unitwind:test("Start snapshots walk waypoints and Release unregisters callbacks", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } })
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(tes3, "pushKey", function() end)
        unitwind:mock(tes3, "releaseKey", function() end)
        unitwind:mock(event, "register", function(eventId, callback) registered[eventId] = callback end)
        unitwind:mock(event, "unregister", function(eventId, callback) unregistered[eventId] = callback end)

        local instance = navigator.new({ pathfinding = Graph({ walk = 1 }) })
        local ok, _, navigation = instance:Start({ cell = tes3.player.cell, position = { x = 200, y = 0, z = 0 } })
        instance:Release()
        navigation = navigation or {}

        unitwind:expect(ok).toBe(true)
        unitwind:expect(table.size(instance.waypoints)).toBe(3)
        unitwind:expect(navigation.routeNodeCount).toBe(2)
        unitwind:expect(navigation.waypointCount).toBe(3)
        unitwind:expect(registered[tes3.event.simulate] ~= nil).toBe(true)
        unitwind:expect(unregistered[tes3.event.simulate] ~= nil).toBe(true)
    end)

    unitwind:test("StartRoute copies provider-independent waypoints", function()
        local registered = {}
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } })
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(tes3, "pushKey", function() end)
        unitwind:mock(tes3, "releaseKey", function() end)
        unitwind:mock(event, "register", function(eventId, callback) registered[eventId] = callback end)
        unitwind:mock(event, "unregister", function() end)
        local route = { { position = { x = 10, y = 20, z = 30 } }, { position = { x = 40, y = 50, z = 60 } } }
        local instance = navigator.new({ pathfinding = Graph({ walk = 1 }) })
        local ok, _, result = instance:StartRoute(route, 7)
        route[1].position.x = 999
        instance:Release()
        unitwind:expect(ok).toBe(true)
        ---@cast result MCP.NavigatorStartResult
        unitwind:expect(instance.waypoints[1].position.x).toBe(10)
        unitwind:expect(result.routeNodeCount).toBe(7)
        unitwind:expect(result.waypointCount).toBe(2)
    end)

    unitwind:test("Start rejects a path requiring travel activation", function()
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } })
        local graph = Graph({ walk = 1 })
        graph.edges[1].kind = 2
        local instance = navigator.new({ pathfinding = graph })

        local ok, message = instance:Start({ cell = tes3.player.cell, position = { x = 200, y = 0, z = 0 } })
        unitwind:expect(ok).toBe(false)
        unitwind:expect(message ~= nil).toBe(true)
        message = message or ""
        unitwind:expect(message:find("travel activation", 1, true) ~= nil).toBe(true)
    end)

    unitwind:test("Only Escape cancels an active navigation", function()
        local registered = {}
        local keyDownFilter = nil
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } })
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(tes3, "pushKey", function() end)
        unitwind:mock(tes3, "releaseKey", function() end)
        unitwind:mock(event, "register", function(eventId, callback, options)
            registered[eventId] = callback
            if eventId == tes3.event.keyDown then
                keyDownFilter = options and options.filter
            end
        end)
        unitwind:mock(event, "unregister", function() end)

        local instance = navigator.new({ pathfinding = Graph({ walk = 1 }) })
        unitwind:expect(instance:Start({ cell = tes3.player.cell, position = { x = 200, y = 0, z = 0 } })).toBe(true)
        unitwind:expect(keyDownFilter).toBe(tes3.scanCode.escape)
        registered[tes3.event.keyDown]({ keyCode = 17 })
        unitwind:expect(instance.isActive).toBe(true)
        registered[tes3.event.keyDown]({ keyCode = tes3.scanCode.escape })
        unitwind:expect(instance.isActive).toBe(false)
        unitwind:expect(instance.result.message).toBe("Cancelled by local Escape key.")
    end)

    unitwind:test("Navigation fails after the configured duration without sufficient movement", function()
        local registered = {}
        local released = 0
        unitwind:mock(tes3, "player", { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } })
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(tes3, "pushKey", function() end)
        unitwind:mock(tes3, "releaseKey", function() released = released + 1 end)
        unitwind:mock(tes3, "rayTest", function() return nil end)
        unitwind:mock(event, "register", function(eventId, callback) registered[eventId] = callback end)
        unitwind:mock(event, "unregister", function() end)

        local instance = navigator.new({ pathfinding = Graph({ walk = 1 }) })
        unitwind:expect(instance:Start({ cell = tes3.player.cell, position = { x = 200, y = 0, z = 0 } })).toBe(true)
        registered[tes3.event.simulate]({ delta = 4.99 })
        unitwind:expect(instance.isActive).toBe(true)
        registered[tes3.event.simulate]({ delta = 0.01 })
        unitwind:expect(instance.isActive).toBe(false)
        unitwind:expect(instance.result.status).toBe("failed")
        unitwind:expect(instance.result.message:find("player position", 1, true) ~= nil).toBe(true)
        unitwind:expect(released).toBe(1)
    end)

    unitwind:test("Sufficient movement resets the navigation stuck timer", function()
        local registered = {}
        local player = { position = { x = 0, y = 0, z = 0 }, cell = { id = "Test", isInterior = true } }
        unitwind:mock(tes3, "player", player)
        unitwind:mock(tes3, "getInputBinding", function() return { device = 0, code = 17 } end)
        unitwind:mock(tes3, "pushKey", function() end)
        unitwind:mock(tes3, "releaseKey", function() end)
        unitwind:mock(tes3, "rayTest", function() return nil end)
        unitwind:mock(event, "register", function(eventId, callback) registered[eventId] = callback end)
        unitwind:mock(event, "unregister", function() end)

        local instance = navigator.new({ pathfinding = Graph({ walk = 1 }) })
        unitwind:expect(instance:Start({ cell = player.cell, position = { x = 200, y = 0, z = 0 } })).toBe(true)
        registered[tes3.event.simulate]({ delta = 4 })
        player.position.x = 16
        registered[tes3.event.simulate]({ delta = 0.01 })
        registered[tes3.event.simulate]({ delta = 4.99 })
        unitwind:expect(instance.isActive).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
