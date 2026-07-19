local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local document = require("morrowind-mcp.resources.memory.document")

    unitwind:start("morrowind-mcp.resources.memory.document")

    unitwind:test("Descriptor builds an application/json Memory resource", function()
        local descriptor = document.Descriptor("memory/test.json", "Test Memory", "Test description.")

        unitwind:expect(descriptor.name).toBe("memory/test.json")
        unitwind:expect(descriptor.uri).toBe("morrowind://memory/test.json")
        unitwind:expect(descriptor.title).toBe("Test Memory")
        unitwind:expect(descriptor.description).toBe("Test description.")
        unitwind:expect(descriptor.mimeType).toBe("application/json")
    end)

    unitwind:test("Document builds the Memory envelope with data and links", function()
        local link = document.Link(document.linkRel.self, "morrowind://memory/test.json", "Self", nil)
        local subject = document.Subject(document.SubjectTypeFromObjectType(tes3.objectType.npc), "player", "Player")
        local scope = document.Scope(3, nil, "Player")
        local memoryDocument = document.Document(
            document.documentType.collection,
            document.dataType.questEntries,
            "Quest Memory",
            { quests = {} },
            {
                subject = subject,
                scope = scope,
                links = { link },
            }
        )

        unitwind:expect(memoryDocument.schema_version).toBe(1)
        unitwind:expect(memoryDocument.type).toBe("memory.collection")
        unitwind:expect(memoryDocument.data_type).toBe("quest_entries")
        unitwind:expect(memoryDocument.subject.tes3_type).toBe("tes3npc")
        unitwind:expect(memoryDocument.scope.generation).toBe(3)
        unitwind:expect(memoryDocument.links[1].rel).toBe("self")
        unitwind:expect(memoryDocument.data.quests ~= nil).toBe(true)
    end)

    unitwind:test("Subject type resolves from objectType and reference base object", function()
        local npcObject = { objectType = tes3.objectType.npc }
        local activatorObject = { objectType = tes3.objectType.activator }
        local reference = {
            objectType = tes3.objectType.reference,
            object = activatorObject,
            baseObject = npcObject,
        }

        unitwind:expect(document.SubjectTypeFromObject(npcObject)).toBe("tes3npc")
        unitwind:expect(document.SubjectTypeFromReference(reference)).toBe("tes3npc")
        unitwind:expect(document.SubjectTypeFromObject(reference)).toBe("tes3npc")
    end)

    unitwind:test("LiveEntry reuses cached JSON until marked dirty", function()
        local descriptor = document.Descriptor("memory/cache.json", "Cache Memory", "Cache test.")
        local buildCount = 0
        local entry = document.LiveEntry(descriptor, function()
            buildCount = buildCount + 1
            return document.Document(
                document.documentType.entity,
                document.dataType.playerSummary,
                "Cache Memory",
                { count = buildCount }
            )
        end)

        entry.handler(descriptor)
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(1)

        document.MarkDirty(entry)
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(2)
    end)

    unitwind:test("SaveEntry writes a Memory resource entry as debug JSON", function()
        local descriptor = document.Descriptor("memory/save/test.json", "Save Memory", "Save test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(
                document.documentType.entity,
                document.dataType.playerSummary,
                "Save Memory",
                { value = 7 }
            )
        end)
        local directories = {}
        local writes = {}
        local closed = false

        unitwind:mock(lfs, "attributes", function(path, attribute)
            if directories[path] then
                if attribute == "mode" then
                    return "directory"
                end
                return { mode = "directory" }
            end
            return nil
        end)
        unitwind:mock(lfs, "mkdir", function(path)
            directories[path] = true
            return true
        end)
        unitwind:mock(io, "open", function(path, mode)
            unitwind:expect(path).toBe("debug\\memory\\save\\test.json")
            unitwind:expect(mode).toBe("wb")
            return {
                write = function(self, text)
                    table.insert(writes, text)
                end,
                close = function(self)
                    closed = true
                end,
            }
        end)

        local result = assert(document.SaveEntry(entry, "debug"))

        unitwind:expect(result.uri).toBe("morrowind://memory/save/test.json")
        unitwind:expect(result.file_path).toBe("debug\\memory\\save\\test.json")
        unitwind:expect(result.bytes).toBe(string.len(writes[1]))
        unitwind:expect(string.find(writes[1], '"schema_version":1') ~= nil).toBe(true)
        unitwind:expect(closed).toBe(true)

        unitwind:unmock(io, "open")
        unitwind:unmock(lfs, "mkdir")
        unitwind:unmock(lfs, "attributes")
    end)

    unitwind:finish()
end

return this
