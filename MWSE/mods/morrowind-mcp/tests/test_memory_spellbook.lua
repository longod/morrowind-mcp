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

    local spellbook = require("morrowind-mcp.resources.memory.spellbook")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.spellbook")

    --- Build a valid spell fixture with a controllable cast type and effects.
    ---@param id string
    ---@param name string
    ---@param castType tes3.spellType
    ---@return tes3spell
    local function Spell(id, name, castType)
        return {
            id = id,
            name = name,
            castType = castType,
            magickaCost = 12,
            effects = {
                {
                    id = tes3.effect.restoreHealth,
                    duration = 5,
                    min = 2,
                    max = 4,
                    radius = 0,
                    rangeType = tes3.effectRange.self,
                },
            },
            isValid = function() return true end,
        }
    end

    --- Construct a published module and record its resource publication calls.
    ---@return MCP.Resources.Memory.Spellbook, table
    local function CreateModule()
        local resource = { publishCount = 0 }
        function resource:PublishResource(entry)
            self.publishCount = self.publishCount + 1
            return entry.descriptor.uri
        end
        function resource:UnpublishResource(uri)
            return true
        end
        local memory = {
            GetScope = function(self) return document.Scope(1) end,
            OnModuleVisibilityChanged = function(self, module) end,
        }
        local module = spellbook.new({ resource = resource, manager = memory })
        module:Publish()
        return module, resource
    end

    --- Read the live entry and return its authoritative cached document.
    ---@param module MCP.Resources.Memory.Spellbook
    ---@return MCP.MemoryDocument
    local function ReadDocument(module)
        module.entry.handler(module.entry.descriptor)
        return module.entry.cache.cached_document
    end

    unitwind:test("Spellbook Memory reads only player spells and powers with live power state", function()
        local playerReference = { object = { objectType = tes3.objectType.npc } }
        local normalSpell = Spell("fireball", "Fireball", tes3.spellType.spell)
        local power = Spell("ancestor_guardian", "Ancestor Guardian", tes3.spellType.power)
        local usedPowers = { [power] = true }
        local mobilePlayer = {
            hasUsedPower = function(self, value) return usedPowers[value] == true end,
        }

        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(tes3, "mobilePlayer", mobilePlayer)
        unitwind:mock(tes3, "getSpells", function(params)
            if params.spellType == tes3.spellType.spell then
                return { normalSpell }
            end
            if params.spellType == tes3.spellType.power then
                return { power }
            end
            return {}
        end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module = CreateModule()
        local firstDocument = ReadDocument(module)

        unitwind:expect(firstDocument.data_type).toBe("player_spellbook")
        unitwind:expect(firstDocument.data.available).toBe(true)
        unitwind:expect(firstDocument.data.spell_count).toBe(1)
        unitwind:expect(firstDocument.data.spells[1].id).toBe("fireball")
        unitwind:expect(firstDocument.data.spells[1].castType).toBe("spell")
        unitwind:expect(firstDocument.data.spells[1].magickaCost).toBe(12)
        unitwind:expect(firstDocument.data.spells[1].effects[1].id).toBe("restoreHealth")
        unitwind:expect(firstDocument.data.spells[1].effects[1].rangeType).toBe("self")
        unitwind:expect(firstDocument.data.power_count).toBe(1)
        unitwind:expect(firstDocument.data.powers[1].id).toBe("ancestor_guardian")
        unitwind:expect(firstDocument.data.powers[1].castType).toBe("power")
        unitwind:expect(firstDocument.data.powers[1].magickaCost).toBe(12)
        unitwind:expect(firstDocument.data.powers[1].effects[1].rangeType).toBe("self")
        unitwind:expect(firstDocument.data.powers[1].used).toBe(true)
        unitwind:expect(firstDocument.data.powers[1].available).toBe(false)

        usedPowers[power] = false
        local cachedDocument = ReadDocument(module)
        unitwind:expect(cachedDocument).toBe(firstDocument)
        unitwind:expect(cachedDocument.data.powers[1].available).toBe(false)

        module:OnPowerRecharged({ reference = playerReference, mobile = mobilePlayer, power = power })
        local refreshedDocument = ReadDocument(module)
        unitwind:expect(refreshedDocument.data.powers[1].used).toBe(false)
        unitwind:expect(refreshedDocument.data.powers[1].available).toBe(true)
    end)

    unitwind:test("Spellbook Memory invalidates only Player power events and coalesces refreshes", function()
        local playerReference = { object = { objectType = tes3.objectType.npc } }
        local power = Spell("power", "Power", tes3.spellType.power)
        local mobilePlayer = { hasUsedPower = function() return false end }
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", playerReference)
        unitwind:mock(tes3, "mobilePlayer", mobilePlayer)
        unitwind:mock(tes3, "getSpells", function() return {} end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module, resource = CreateModule()
        ReadDocument(module)
        module:OnSpellCasted({ caster = {}, source = power })
        module:OnSpellCasted({ caster = playerReference, source = Spell("spell", "Spell", tes3.spellType.spell) })
        module:OnPowerRecharged({ reference = {} })
        unitwind:expect(module.entry.cache.dirty).toBe(false)

        module:OnSpellCasted({ caster = playerReference, source = power })
        unitwind:expect(module.entry.cache.dirty).toBe(true)
        local publishCount = resource.publishCount
        module:OnPowerRecharged({ mobile = mobilePlayer, power = power })
        module:OnMagicMenuActivated({})
        unitwind:expect(resource.publishCount).toBe(publishCount)
    end)

    unitwind:test("Spellbook Memory invalidates after character generation finalizes", function()
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", { object = { objectType = tes3.objectType.npc } })
        unitwind:mock(tes3, "mobilePlayer", { hasUsedPower = function() return false end })
        unitwind:mock(tes3, "getSpells", function() return {} end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module = CreateModule()
        ReadDocument(module)
        module:OnCharGenFinished()
        unitwind:expect(module.entry.cache.dirty).toBe(true)
    end)

    unitwind:test("Spellbook Memory invalidates after a spell is created", function()
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", { object = { objectType = tes3.objectType.npc } })
        unitwind:mock(tes3, "mobilePlayer", { hasUsedPower = function() return false end })
        unitwind:mock(tes3, "getSpells", function() return {} end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module = CreateModule()
        ReadDocument(module)
        module:OnSpellCreated({})
        unitwind:expect(module.entry.cache.dirty).toBe(true)
    end)

    unitwind:test("Spellbook Memory invalidates when the magic menu is activated", function()
        unitwind:mock(tes3, "onMainMenu", function() return false end)
        unitwind:mock(tes3, "player", { object = { objectType = tes3.objectType.npc } })
        unitwind:mock(tes3, "mobilePlayer", { hasUsedPower = function() return false end })
        unitwind:mock(tes3, "getSpells", function() return {} end)
        unitwind:mock(datetime, "InGameNow", function() return nil end)

        local module = CreateModule()
        ReadDocument(module)
        module:OnMagicMenuActivated({})
        unitwind:expect(module.entry.cache.dirty).toBe(true)
    end)

    unitwind:test("Spellbook Memory links under Player and registers minimal refresh events", function()
        local registered = {}
        local unregistered = {}
        unitwind:mock(event, "register", function(eventId, callback, options)
            registered[eventId] = options or true
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
            unregistered[eventId] = true
        end)

        local module = CreateModule()
        local links = module:GetLinksForParent("morrowind://memory/player/index.json")
        module:RegisterEvent()
        module:UnregisterEvent()

        unitwind:expect(module.parentUri).toBe("morrowind://memory/player/index.json")
        unitwind:expect(links[1].rel).toBe("spellbook")
        unitwind:expect(links[1].uri).toBe("morrowind://memory/player/spellbook.json")
        unitwind:expect(registered[tes3.event.loaded]).toBe(true)
        unitwind:expect(registered[tes3.event.charGenFinished]).toBe(true)
        unitwind:expect(registered[tes3.event.spellCreated]).toBe(true)
        unitwind:expect(registered[tes3.event.spellCasted]).toBe(true)
        unitwind:expect(registered[tes3.event.powerRecharged]).toBe(true)
        unitwind:expect(registered[tes3.event.uiActivated].filter).toBe("MenuMagic")
        unitwind:expect(registered[tes3.event.simulated] == true).toBe(false)
        unitwind:expect(unregistered[tes3.event.uiActivated]).toBe(true)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()
    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this