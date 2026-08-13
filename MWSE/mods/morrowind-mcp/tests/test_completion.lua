local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    local completion = require("morrowind-mcp.resources.completion")
    local templates = require("morrowind-mcp.resources.templates")

    ---@return table<MCP.ResourceUri, MCP.ResourceEntry>
    local function Resources(uris)
        local resources = {}
        for _, uri in ipairs(uris) do
            resources[uri] = { descriptor = { uri = uri } }
        end
        return resources
    end

    ---@param templateUri string
    ---@param name string
    ---@param value string
    ---@param context table?
    local function Params(templateUri, name, value, context)
        return {
            ref = { type = "ref/resource", uri = templateUri },
            argument = { name = name, value = value },
            context = context,
        }
    end

    unitwind:start("morrowind-mcp.resources.completion")

    unitwind:test("Memory completion filters each hierarchy level by context", function()
        -- This fixture exercises sorting across dynamic collections.
        local resources = Resources({
            "morrowind://memory/actors/guard/dialogue.json",
            "morrowind://memory/actors/guard/index.json",
            "morrowind://memory/activators/door/index.json",
            "morrowind://memory/actors/index.json",
            "morrowind://memory/player/inventory.json",
            "morrowind://memory/unattributed/dialogue.json",
        })

        local collections = completion.Complete(Params(templates.memoryEntity.uriTemplate, "collection", "", nil), resources)
        local entities = completion.Complete(Params(templates.memoryEntity.uriTemplate, "entity_id", "g", {
            arguments = { collection = "actors" },
        }), resources)
        local documents = completion.Complete(Params(templates.memoryEntity.uriTemplate, "document", "", {
            arguments = { collection = "actors", entity_id = "guard" },
        }), resources)
        local collectionValues = table.concat(collections.values, ",")

        unitwind:expect(collectionValues).toBe("activators,actors")
        unitwind:expect(string.find(collectionValues, "player", 1, true)).toBe(nil)
        unitwind:expect(string.find(collectionValues, "unattributed", 1, true)).toBe(nil)
        unitwind:expect(table.concat(entities.values, ",")).toBe("guard")
        unitwind:expect(table.concat(documents.values, ",")).toBe("dialogue,index")
    end)

    unitwind:test("Screenshot completion prioritizes exact matches and uses a stable case tie-break", function()
        local first = Resources({
            "morrowind://screenshot/zeta.png",
            "morrowind://screenshot/Alpha.png",
            "morrowind://screenshot/alpha.png",
        })
        local second = Resources({
            "morrowind://screenshot/alpha.png",
            "morrowind://screenshot/Alpha.png",
            "morrowind://screenshot/zeta.png",
        })
        local params = Params(templates.screenshot.uriTemplate, "file", "", nil)
        local firstResult = completion.Complete(params, first)
        local secondResult = completion.Complete(params, second)
        local exactResult = completion.Complete(Params(templates.screenshot.uriTemplate, "file", "alpha.png", nil), first)

        unitwind:expect(table.concat(firstResult.values, ",")).toBe("Alpha.png,alpha.png,zeta.png")
        unitwind:expect(table.concat(secondResult.values, ",")).toBe(table.concat(firstResult.values, ","))
        unitwind:expect(exactResult.values[1]).toBe("alpha.png")
    end)

    unitwind:test("Completion returns default and bounded result counts", function()
        local uris = {}
        for index = 1, 105 do
            uris[index] = string.format("morrowind://screenshot/item-%03d.jpg", index)
        end
        local resources = Resources(uris)
        local params = Params(templates.screenshot.uriTemplate, "file", "item-", nil)
        local defaultResult = completion.Complete(params, resources)
        local boundedResult = completion.Complete(params, resources, 200)
        local invalidLimitResult = completion.Complete(params, resources, 0)

        unitwind:expect(defaultResult.total).toBe(105)
        unitwind:expect(#defaultResult.values).toBe(10)
        unitwind:expect(defaultResult.hasMore).toBe(true)
        unitwind:expect(#boundedResult.values).toBe(100)
        unitwind:expect(boundedResult.hasMore).toBe(true)
        unitwind:expect(#invalidLimitResult.values).toBe(10)
    end)

    unitwind:test("Completion rejects unknown templates and incomplete Memory context", function()
        local resources = Resources({ "morrowind://memory/actors/guard/index.json" })
        local unknown = completion.Complete(Params("morrowind://unknown/{value}", "value", "", nil), resources)
        local incomplete = completion.Complete(Params(templates.memoryEntity.uriTemplate, "document", "", {
            arguments = { collection = "actors" },
        }), resources)

        unitwind:expect(unknown.valid).toBe(false)
        unitwind:expect(incomplete.valid).toBe(false)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
