local this = {}
---@diagnostic disable: missing-fields

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })
    -- Restore function spies before mocks so UnitWind does not reapply a mocked function.
    unitwind.afterEach = function(self)
        self:clearSpies()
        self:clearMocks()
    end

    local player = require("morrowind-mcp.resources.memory.player")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.player")

    --- Build one statistic fixture with mutable primitive values.
    ---@param base number
    ---@param current number
    ---@return tes3statistic
    local function Statistic(base, current)
        return {
            base = base,
            current = current,
            normalized = current / base,
        }
    end

    --- Build the complete player mobile state required by all Player Memory documents.
    ---@return tes3mobilePlayer
    local function MobilePlayer()
        local attributes = {}
        local skills = {}
        for index = 0, 7 do
            attributes[index] = Statistic(40 + index, 40 + index)
        end
        for index = 0, 26 do
            skills[index] = Statistic(20 + index, 20 + index)
            skills[index].type = tes3.skillType.miscellaneous
        end
        return {
            level = 4,
            health = Statistic(100, 100),
            magicka = Statistic(50, 50),
            fatigue = Statistic(90, 90),
            attributes = attributes,
            skills = skills,
            birthsign = { name = "The Mage" },
            firstPerson = {
                objectType = tes3.objectType.npc,
                name = "Nerevarine",
                female = true,
                race = { name = "Dark Elf" },
                class = {
                    id = "NEWCLASSID_CHARGEN",
                    objectType = tes3.objectType.class,
                    isValid = function(self) return true end,
                    name = "Adventurer",
                    specialization = tes3.specialization.combat,
                    attributes = { tes3.attribute.strength, tes3.attribute.luck },
                    majorSkills = { tes3.skill.block },
                    minorSkills = { tes3.skill.mediumArmor },
                    skills = { tes3.skill.block, tes3.skill.mediumArmor },
                },
            },
        }
    end

    --- Create a Player Memory module with a lightweight resource and scope manager.
    ---@return MCP.Resources.Memory.Player
    local function CreateModule()
        local resource = {}
        function resource:PublishResource(entry)
            return entry.descriptor.uri
        end
        function resource:UnpublishResource(uri)
            return true
        end
        local manager = {
            GetScope = function(self) return document.Scope(1) end,
            GetLinksForParent = function(self, parentUri) return {} end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        return player.new({ resource = resource, manager = manager })
    end

    --- Read one live entry and return its cached document.
    ---@param entry MCP.MemoryResourceEntry
    ---@return MCP.MemoryDocument
    local function ReadEntry(entry)
        entry.handler(entry.descriptor)
        return entry.cache.cached_document
    end

    --- Configure a finished character generation fixture and return its mobile state.
    ---@return tes3mobilePlayer
    local function MockReadyPlayer()
        local mobilePlayer = MobilePlayer()
        local playerReference = {
            isDead = false,
            object = mobilePlayer.firstPerson,
        }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(tes3, "mobilePlayer", mobilePlayer)
        unitwind:mock(tes3, "isCharGenStarted", function() return true end)
        unitwind:mock(tes3, "isCharGenRunning", function() return false end)
        unitwind:mock(tes3, "isCharGenFinished", function() return true end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)
        return mobilePlayer
    end

    unitwind:test("Player Memory separates finalized identity, progression, and vitals", function()
        MockReadyPlayer()
        local module = CreateModule()
        local indexDocument = ReadEntry(module.playerEntry)
        local progressionDocument = ReadEntry(module.progressionEntry)
        local vitalsDocument = ReadEntry(module.vitalsEntry)

        unitwind:expect(indexDocument.data_type).toBe("player_summary")
        unitwind:expect(indexDocument.subject ~= nil).toBe(true)
        unitwind:expect(indexDocument.subject.id).toBe("player")
        unitwind:expect(indexDocument.data.ready).toBe(true)
        unitwind:expect(indexDocument.data.name).toBe("Nerevarine")
        unitwind:expect(indexDocument.data.race).toBe("Dark Elf")
        unitwind:expect(indexDocument.data.gender).toBe("female")
        unitwind:expect(indexDocument.data.class.name).toBe("Adventurer")
        unitwind:expect(indexDocument.data.class.specialization).toBe("combat")
        unitwind:expect(indexDocument.data.class.attributes[1]).toBe("strength")
        unitwind:expect(indexDocument.data.class.attributes[2]).toBe("luck")
        unitwind:expect(indexDocument.data.class.majorSkills[1]).toBe("Block")
        unitwind:expect(indexDocument.data.class.minorSkills[1]).toBe("Medium Armor")
        unitwind:expect(indexDocument.data.birthsign).toBe("The Mage")
        unitwind:expect(indexDocument.data.level == nil).toBe(true)
        unitwind:expect(indexDocument.links[1].rel).toBe("progression")
        unitwind:expect(indexDocument.links[2].rel).toBe("vitals")
        unitwind:expect(progressionDocument.data_type).toBe("player_progression")
        unitwind:expect(progressionDocument.data.level).toBe(4)
        unitwind:expect(table.size(progressionDocument.data.attributes)).toBe(8)
        unitwind:expect(table.size(progressionDocument.data.skills)).toBe(27)
        unitwind:expect(vitalsDocument.data_type).toBe("player_vitals")
        unitwind:expect(vitalsDocument.data.alive).toBe(true)
        unitwind:expect(vitalsDocument.data.health.current).toBe(100)
    end)

    unitwind:test("Player Memory omits identity while character generation is incomplete", function()
        local mobilePlayer = MockReadyPlayer()
        unitwind:mock(tes3, "isCharGenFinished", function() return false end)
        unitwind:mock(tes3, "isCharGenRunning", function() return true end)
        local module = CreateModule()
        local indexDocument = ReadEntry(module.playerEntry)

        unitwind:expect(mobilePlayer ~= nil).toBe(true)
        unitwind:expect(indexDocument.data.ready).toBe(false)
        unitwind:expect(indexDocument.data.name == nil).toBe(true)
        unitwind:expect(indexDocument.data.class == nil).toBe(true)
        unitwind:expect(indexDocument.data.character_generation.running).toBe(true)
    end)

    unitwind:test("Player Memory tolerates missing class while identity is otherwise ready", function()
        local mobilePlayer = MockReadyPlayer()
        mobilePlayer.firstPerson.class = nil
        local module = CreateModule()
        local indexDocument = ReadEntry(module.playerEntry)

        unitwind:expect(indexDocument.data.ready).toBe(true)
        unitwind:expect(indexDocument.data.name).toBe("Nerevarine")
        unitwind:expect(indexDocument.data.race).toBe("Dark Elf")
        unitwind:expect(indexDocument.data.class == nil).toBe(true)
        unitwind:expect(indexDocument.data.birthsign).toBe("The Mage")
    end)

    unitwind:test("Player Memory applies vital thresholds from the last published snapshot", function()
        local mobilePlayer = MockReadyPlayer()
        local module = CreateModule()
        mobilePlayer.health.current = 80
        mobilePlayer.health.normalized = 0.8
        ReadEntry(module.vitalsEntry)

        mobilePlayer.health.current = 77
        mobilePlayer.health.normalized = 0.77
        module:OnSimulated()
        unitwind:expect(module.vitalsEntry.cache.dirty).toBe(false)

        mobilePlayer.health.current = 74
        mobilePlayer.health.normalized = 0.74
        module:OnSimulated()
        unitwind:expect(module.vitalsEntry.cache.dirty).toBe(true)

        ReadEntry(module.vitalsEntry)
        mobilePlayer.health.current = 0
        mobilePlayer.health.normalized = 0
        module:OnSimulated()
        unitwind:expect(module.vitalsEntry.cache.dirty).toBe(true)
    end)

    unitwind:test("Player Memory invalidates only matching player vital events and progression changes", function()
        local mobilePlayer = MockReadyPlayer()
        local playerObject = tes3.player
        local module = CreateModule()
        ReadEntry(module.vitalsEntry)
        ReadEntry(module.progressionEntry)

        module:OnVitalEvent({ reference = {} })
        unitwind:expect(module.vitalsEntry.cache.dirty).toBe(false)
        module:OnVitalEvent({ reference = playerObject })
        unitwind:expect(module.vitalsEntry.cache.dirty).toBe(true)

        ReadEntry(module.progressionEntry)
        mobilePlayer.attributes[0].current = 41
        module:OnSimulated()
        unitwind:expect(module.progressionEntry.cache.dirty).toBe(true)

        ReadEntry(module.progressionEntry)
        module:OnProgressionEvent()
        unitwind:expect(module.progressionEntry.cache.dirty).toBe(true)
    end)

    unitwind:test("Player Memory registers its player-only event handlers", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback)
            registered[eventId] = true
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            unregistered[eventId] = true
        end)
        local module = CreateModule()
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.charGenFinished]).toBe(true)
        unitwind:expect(registered[tes3.event.damaged]).toBe(true)
        unitwind:expect(registered[tes3.event.damagedHandToHand]).toBe(true)
        unitwind:expect(registered[tes3.event.death]).toBe(true)
        unitwind:expect(registered[tes3.event.levelUp]).toBe(true)
        unitwind:expect(registered[tes3.event.skillRaised]).toBe(true)
        unitwind:expect(registered[tes3.event.simulated]).toBe(true)
        unitwind:expect(unregistered[tes3.event.simulated]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
