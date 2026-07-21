local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local iterator = require("morrowind-mcp.tes3.iterator")
    local jsonrpc = require("morrowind-mcp.server.jsonrpc")

    local function CollectReferences(iter)
        local values = {}
        while true do
            local ref = iter()
            if not ref then
                break
            end
            table.insert(values, ref)
        end
        return values
    end

    local function CollectInventory(iter)
        local values = {}
        while true do
            local item, count, data = iter()
            if not item then
                break
            end
            table.insert(values, {
                item = item,
                count = count,
                data = data,
            })
        end
        return values
    end

    unitwind:start("morrowind-mcp.tes3.iterator")

    unitwind:test("ForEachReferenceList returns nothing for empty list", function()
        local emptyList = {
            size = 0,
            head = {},
        } ---@type any

        local iter = iterator.ForEachReferenceList(emptyList)

        unitwind:expect(iter()).toBe(nil)
    end)

    unitwind:test("ForEachReferenceList yields all nodes in order", function()
        local ref3 = { id = "ref3", nextNode = nil }
        local ref2 = { id = "ref2", nextNode = ref3 }
        local ref1 = { id = "ref1", nextNode = ref2 }

        local referenceList = {
            size = 3,
            head = ref1,
        } ---@type any

        local refs = CollectReferences(iterator.ForEachReferenceList(referenceList))

        unitwind:expect(table.size(refs)).toBe(3)
        unitwind:expect(refs[1]).toBe(ref1)
        unitwind:expect(refs[2]).toBe(ref2)
        unitwind:expect(refs[3]).toBe(ref3)
    end)

    unitwind:test("ForEachInventory expands variable stacks and skips uncarryable items", function()
        local itemA = { id = "itemA", canCarry = true }
        local itemB = { id = "itemB", canCarry = true }
        local itemC = { id = "itemC", canCarry = false }

        local data1 = { count = 2, soul = "A" }
        local data2 = { count = 1, soul = "B" }

        local inventory = {
            {
                object = itemA,
                count = 3,
            },
            {
                object = itemB,
                count = -5,
                variables = {
                    data1,
                    data2,
                },
            },
            {
                object = itemC,
                count = 10,
            },
        }

        local values = CollectInventory(iterator.ForEachInventory(inventory))

        unitwind:expect(table.size(values)).toBe(4)

        unitwind:expect(values[1].item).toBe(itemA)
        unitwind:expect(values[1].count).toBe(3)
        unitwind:expect(values[1].data).toBe(nil)

        unitwind:expect(values[2].item).toBe(itemB)
        unitwind:expect(values[2].count).toBe(2)
        unitwind:expect(values[2].data).toBe(data1)

        unitwind:expect(values[3].item).toBe(itemB)
        unitwind:expect(values[3].count).toBe(1)
        unitwind:expect(values[3].data).toBe(data2)

        unitwind:expect(values[4].item).toBe(itemB)
        unitwind:expect(values[4].count).toBe(2)
        unitwind:expect(values[4].data).toBe(nil)
    end)

    unitwind:test("ForEachObject returns nil for nil input", function()
        local values = iterator.ForEachObject(nil, function(value) ---@diagnostic disable-line: param-type-mismatch
            return { value = value }
        end)

        unitwind:expect(values).toBe(nil)
    end)

    unitwind:test("ForEachObject builds array from transformed values", function()
        local values = iterator.ForEachObject({ 1, 2, 3 }, function(value)
            if value % 2 == 0 then
                return nil
            end
            return { value = value * 10 }
        end)

        unitwind:expect(values == nil).toBe(false)
        if values then
            unitwind:expect(getmetatable(values).__jsontype).toBe("array")
            unitwind:expect(table.size(values)).toBe(2)
            unitwind:expect(values[1].value).toBe(10)
            unitwind:expect(values[2].value).toBe(30)
        end
    end)

    unitwind:test("ForEachObject appends to provided output array", function()
        local out = jsonrpc.array({
            { value = 0 },
        })

        local values = iterator.ForEachObject({ 4 }, function(value)
            return { value = value }
        end, out)

        unitwind:expect(values).toBe(out)
        if values then
            unitwind:expect(table.size(values)).toBe(2)
            unitwind:expect(values[1].value).toBe(0)
            unitwind:expect(values[2].value).toBe(4)
        end
    end)

    unitwind:test("ForEachObject returns nil when callback returns no values", function()
        local values = iterator.ForEachObject({ 2, 4, 6 }, function(_)
            return nil
        end)

        unitwind:expect(values).toBe(nil)
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
