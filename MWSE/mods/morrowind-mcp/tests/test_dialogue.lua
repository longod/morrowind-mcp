local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local dialogue = require("morrowind-mcp.util.dialogue")

    unitwind:start("morrowind-mcp.util.dialogue")

    unitwind:test("NormalizeDialogueText strips markup and deduplicates topics", function()
        local text, topics = dialogue.NormalizeDialogueText(
            "My @orders# are to go to @Balmora# and @report# to @Caius Cosades# in @Balmora# for further @orders#."
        )

        unitwind:expect(text).toBe(
            "My orders are to go to Balmora and report to Caius Cosades in Balmora for further orders."
        )
        unitwind:expect(getmetatable(topics).__jsontype).toBe("array")
        unitwind:expect(topics[1]).toBe("orders")
        unitwind:expect(topics[2]).toBe("Balmora")
        unitwind:expect(topics[3]).toBe("report")
        unitwind:expect(topics[4]).toBe("Caius Cosades")
        unitwind:expect(topics[5]).toBe(nil)
    end)

    unitwind:test("NormalizeTopicText deduplicates topics case-insensitively", function()
        local _, topics = dialogue.NormalizeDialogueText(
            "Speak to @Caius Cosades# after you @report# to @caius cosades# and @Report#."
        )

        unitwind:expect(getmetatable(topics).__jsontype).toBe("array")
        unitwind:expect(topics[1]).toBe("Caius Cosades")
        unitwind:expect(topics[2]).toBe("report")
        unitwind:expect(topics[3]).toBe(nil)
    end)

    unitwind:test("ReplaceDialogueDefines resolves known tokens case-insensitively", function()
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourcePlayer
        local player = { ---@diagnostic disable-line: missing-fields
            object = { ---@diagnostic disable-line: missing-fields
                name = "Nerevarine",
                race = { name = "Dunmer" }, ---@diagnostic disable-line: missing-fields
                class = { name = "Pilgrim" }, ---@diagnostic disable-line: missing-fields
            },
            mobile = { ---@diagnostic disable-line: missing-fields
                bounty = 123,
            },
        }
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourceActor
        local speaker = { ---@diagnostic disable-line: missing-fields
            name = "Caius Cosades",
            race = { name = "Imperial" }, ---@diagnostic disable-line: missing-fields
            class = { name = "Spymaster" }, ---@diagnostic disable-line: missing-fields
            faction = { name = "Blades" }, ---@diagnostic disable-line: missing-fields
        }
        ---@diagnostic disable-next-line: missing-fields
        ---@type tes3dialogueInfo
        local dialogueInfo = { ---@diagnostic disable-line: missing-fields
            cell = { displayName = "Balmora" }, ---@diagnostic disable-line: missing-fields
            npcFaction = { name = "Blades" }, ---@diagnostic disable-line: missing-fields
            npcRank = 2,
            pcRank = 3,
        }
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourceContext
        local source = {
            player = player,
            actor = speaker,
            dialogueInfo = dialogueInfo,
            cell = { displayName = "Balmora" }, ---@diagnostic disable-line: missing-fields
        }
        local context = dialogue.BuildDialogueDefineContext(source)

        local replaced = dialogue.ReplaceDialogueDefines(
            "%PCNAME, meet %Name in %Cell. %pCrAcE %PcClass %PcCrimeLevel %Faction %Class %Race %Rank %PcRank",
            context
        )

        unitwind:expect(replaced).toBe(
            "Nerevarine, meet Caius Cosades in Balmora. Dunmer Pilgrim 123 Blades Spymaster Imperial %Rank 3"
        )
    end)

    unitwind:test("ReplaceDialogueDefines keeps pcnextrank unresolved without dedicated value", function()
        ---@diagnostic disable-next-line: missing-fields
        ---@type tes3dialogueInfo
        local dialogueInfo = { ---@diagnostic disable-line: missing-fields
            pcRank = 3,
        }
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourceContext
        local source = {
            dialogueInfo = dialogueInfo,
        }
        local context = dialogue.BuildDialogueDefineContext(source)

        local replaced = dialogue.ReplaceDialogueDefines("%PcRank %PcNextRank %NextPcRank", context)
        unitwind:expect(replaced).toBe("3 %PcNextRank %NextPcRank")
    end)

    unitwind:test("BuildDialogueDefineContext extracts values from player and speaker", function()
        ---@diagnostic disable-next-line: missing-fields
        ---@type tes3dialogueInfo
        local dialogueInfo = { ---@diagnostic disable-line: missing-fields
            cell = { displayName = "Balmora" }, ---@diagnostic disable-line: missing-fields
            npcFaction = { name = "Blades" }, ---@diagnostic disable-line: missing-fields
            npcRank = 2,
            pcRank = 3,
        }
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourceContext
        local source = {
            player = { ---@diagnostic disable-line: missing-fields
                object = { ---@diagnostic disable-line: missing-fields
                    name = "Nerevarine",
                    race = { name = "Dunmer" }, ---@diagnostic disable-line: missing-fields
                    class = { name = "Pilgrim" }, ---@diagnostic disable-line: missing-fields
                },
                mobile = { ---@diagnostic disable-line: missing-fields
                    bounty = 123,
                },
            },
            actor = { ---@diagnostic disable-line: missing-fields
                name = "Caius Cosades",
                race = { name = "Imperial" }, ---@diagnostic disable-line: missing-fields
                class = { name = "Spymaster" }, ---@diagnostic disable-line: missing-fields
                faction = { name = "Blades" }, ---@diagnostic disable-line: missing-fields
            },
            dialogueInfo = dialogueInfo,
            cell = { displayName = "Balmora" }, ---@diagnostic disable-line: missing-fields
        }
        local context = dialogue.BuildDialogueDefineContext(source)

        unitwind:expect(context.pcname).toBe("Nerevarine")
        unitwind:expect(context.pcrace).toBe("Dunmer")
        unitwind:expect(context.pcclass).toBe("Pilgrim")
        unitwind:expect(context.pccrimelevel).toBe("123")
        unitwind:expect(context.name).toBe("Caius Cosades")
        unitwind:expect(context.race).toBe("Imperial")
        unitwind:expect(context.class).toBe("Spymaster")
        unitwind:expect(context.faction).toBe("Blades")
        unitwind:expect(context.rank).toBe(nil)
        unitwind:expect(context.pcrank).toBe("3")
        unitwind:expect(context.cell).toBe("Balmora")
    end)

    unitwind:test("BuildDialogueDefineContext uses speaker faction only", function()
        ---@diagnostic disable-next-line: missing-fields
        ---@type MCP.DialogueDefineSourceContext
        local source = {
            actor = { ---@diagnostic disable-line: missing-fields
                faction = { ---@diagnostic disable-line: missing-fields
                    name = "ActorFaction",
                    ranks = {
                        { name = "ActorRank0" }, ---@diagnostic disable-line: missing-fields
                        { name = "ActorRank1" }, ---@diagnostic disable-line: missing-fields
                    },
                },
            },
            dialogueInfo = { ---@diagnostic disable-line: missing-fields
                npcFaction = { ---@diagnostic disable-line: missing-fields
                    name = "DialogueInfoFaction",
                    ranks = {
                        { name = "DialogueRank0" }, ---@diagnostic disable-line: missing-fields
                        { name = "DialogueRank1" }, ---@diagnostic disable-line: missing-fields
                    },
                },
                npcRank = 1,
            },
            npcFaction = { ---@diagnostic disable-line: missing-fields
                name = "SourceFaction",
                ranks = {
                    { name = "SourceRank0" }, ---@diagnostic disable-line: missing-fields
                    { name = "SourceRank1" }, ---@diagnostic disable-line: missing-fields
                },
            },
        }
        local context = dialogue.BuildDialogueDefineContext(source)

        unitwind:expect(context.faction).toBe("ActorFaction")
        unitwind:expect(context.rank).toBe("ActorRank1")
    end)

    unitwind:test("ReplaceDialogueDefines keeps unresolved tokens", function()
        local replaced = dialogue.ReplaceDialogueDefines("Hello %UnknownToken and %AnotherOne", nil)
        unitwind:expect(replaced).toBe("Hello %UnknownToken and %AnotherOne")
    end)

    unitwind:test("ReplaceDialogueDefines keeps text unchanged when input is nil", function()
        local replaced = dialogue.ReplaceDialogueDefines(nil, nil)
        unitwind:expect(replaced).toBe(nil)
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
