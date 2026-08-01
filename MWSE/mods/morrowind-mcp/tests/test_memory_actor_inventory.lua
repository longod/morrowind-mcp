local this = {}
---@diagnostic disable: missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end

    local actorInventory = require("morrowind-mcp.resources.memory.actor_inventory")
    local document = require("morrowind-mcp.resources.memory.document")
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.actor_inventory")

    --- Add the validity API exposed by MWSE userdata to a plain-table fixture.
    ---@param value table
    ---@return table
    local function MakeValid(value)
        function value:isValid()
            return true
        end
        return value
    end

    --- Build one actor fixture with the minimum state owned by Actor Memory.
    ---@param items tes3itemStack[]
    ---@return MCP.Resources.Memory.Actor, MCP.MemoryObservedActor, tes3reference, table
    local function CreateFixture(items)
        local published = {}
        local resource = {}
        function resource:PublishResource(entry)
            table.insert(published, entry.descriptor.uri)
        end
        local observedActor = {
            id = "merchant",
            title = "Test Merchant",
            subject = document.Subject("tes3npc", "merchant", "Test Merchant"),
            data = jsonrpc.object({
                base_id = "merchant",
                reference_id = "merchant_ref",
            }),
        }
        local module = {
            observedActors = { merchant = observedActor },
            entries = jsonrpc.array(),
            published = true,
            resource = resource,
            actorCaptureCount = nil,
            manager = { GetScope = function() return document.Scope(1) end },
            CaptureActorSnapshot = function(self, actor)
                self.actorCaptureCount = (self.actorCaptureCount or 0) + 1
            end,
        } --[[@as MCP.Resources.Memory.Actor]]
        local reference = {
            object = {
                objectType = tes3.objectType.npc,
                inventory = { items = items },
            },
        }
        return module, observedActor, reference, published
    end

    unitwind:test("Actor inventory snapshots serialize actual inventory and remain fixed until recaptured", function()
        local gold = MakeValid({ id = "Gold_001", name = "Gold", isGold = true, objectType = tes3.objectType.miscItem, stolenList = {} })
        local potion = MakeValid({ id = "p_restore_health_q", name = "Restore Health", objectType = tes3.objectType.alchemy, effects = {}, stolenList = {} })
        local module, actor, reference, published = CreateFixture({
            { object = gold, count = 12 },
            { object = potion, count = 2 },
        })
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        unitwind:expect(actorInventory.CaptureActual(module, actor, reference, "uiActivated:MenuContents", "Visible contents.")).toBe(true)
        unitwind:expect(actor.inventory_entry.cache.cached_document.data_type).toBe("actor_inventory_items")
        unitwind:expect(actor.inventory_entry.cache.cached_document.data.inventory.gold).toBe(12)
        unitwind:expect(actor.inventory_entry.cache.cached_document.data.inventory.item_count).toBe(1)
        unitwind:expect(table.size(module.entries)).toBe(1)
        unitwind:expect(table.size(published)).toBe(1)

        reference.object.inventory.items[2].count = 9
        unitwind:expect(actor.inventory_entry.cache.cached_document.data.inventory.items[1].count).toBe(2)

        unitwind:expect(actorInventory.CaptureActual(module, actor, reference, "containerClosed", "Closed contents.")).toBe(true)
        unitwind:expect(actor.inventory_entry.cache.cached_document.data.inventory.items[1].count).toBe(9)
        unitwind:expect(table.size(published)).toBe(1)
        unitwind:expect(rawget(module, "actorCaptureCount")).toBe(2)
    end)

    unitwind:test("Actor barter snapshots include every stack of item records the merchant trades", function()
        local traded = MakeValid({ id = "p_restore_health_q", name = "Restore Health", objectType = tes3.objectType.alchemy, effects = {}, stolenList = {} })
        local hidden = MakeValid({ id = "common_shirt", name = "Common Shirt", objectType = tes3.objectType.clothing, enchantCapacity = 0, stolenList = {} })
        local customData = { count = 1 }
        local module, actor, reference = CreateFixture({
            { object = traded, count = 2, variables = { customData } },
            { object = hidden, count = 1 },
        })
        unitwind:mock(datetime, "InGameNow", function() return nil end)
        unitwind:mock(tes3, "checkMerchantTradesItem", function(params)
            return params.reference == reference and params.item == traded
        end)

        unitwind:expect(actorInventory.CaptureBarter(module, actor, reference, "uiActivated:MenuBarter", "Visible barter.")).toBe(true)
        unitwind:expect(actor.barter_entry.cache.cached_document.data_type).toBe("actor_barter_items")
        unitwind:expect(actor.barter_entry.cache.cached_document.data.inventory.item_count).toBe(2)
        unitwind:expect(actor.barter_entry.cache.cached_document.data.inventory.items[1].item.id).toBe(traded.id)
        unitwind:expect(actor.barter_entry.cache.cached_document.data.inventory.items[2].item.id).toBe(traded.id)
        unitwind:expect(actor.barter_entry.cache.cached_document.data.inventory.items[1].itemData).toBeType("table")
        unitwind:expect(actor.inventory_entry).toBe(nil)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
