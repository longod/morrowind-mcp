local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local imodule = require("morrowind-mcp.resources.memory.imodule")
    local manager = require("morrowind-mcp.resources.memory.manager")
    local actor = require("morrowind-mcp.resources.memory.actor")
    local document = require("morrowind-mcp.resources.memory.document")
    local datetime = require("morrowind-mcp.util.datetime")

    unitwind:start("morrowind-mcp.resources.memory.imodule")

    --- Run a Memory module test with in-game clock lookup mocked because UnitWind runs before TES3 is initialized.
    ---@param name string
    ---@param callback fun()
    local function testMemoryModule(name, callback)
        unitwind:test(name, function()
            unitwind:mock(datetime, "InGameNow", function()
                return nil
            end)

            callback()

            unitwind:unmock(datetime, "InGameNow")
        end)
    end

    testMemoryModule("Memory module publishes all registered entries", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/module.json", "Module", "Module test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Module")
        end)
        module.entries = { entry }

        module:Publish()

        unitwind:expect(published[1]).toBe("morrowind://memory/module.json")
    end)

    testMemoryModule("Memory module marks all registered entries dirty", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/dirty.json", "Dirty", "Dirty test.")
        local buildCount = 0
        local entry = document.LiveEntry(descriptor, function()
            buildCount = buildCount + 1
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Dirty")
        end)
        module.entries = { entry }

        entry.handler(descriptor)
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(1)

        module:MarkDirty()
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(2)
    end)

    testMemoryModule("Memory module publish invalidates cached entries", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/publish-dirty.json", "Publish Dirty", "Publish dirty test.")
        local buildCount = 0
        local entry = document.LiveEntry(descriptor, function()
            buildCount = buildCount + 1
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Publish Dirty")
        end)
        module.entries = { entry }

        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(1)

        module:Publish()
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(2)
    end)

    testMemoryModule("Memory module unpublish invalidates cached entries", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/unpublish-dirty.json", "Unpublish Dirty", "Unpublish dirty test.")
        local buildCount = 0
        local entry = document.LiveEntry(descriptor, function()
            buildCount = buildCount + 1
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Unpublish Dirty")
        end)
        module.entries = { entry }

        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(1)

        module:Unpublish()
        entry.handler(descriptor)
        unitwind:expect(buildCount).toBe(2)
    end)

    testMemoryModule("Memory module reports visibility only when published state changes", function()
        local visibilityChanges = 0
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local fakeManager = {
            OnModuleVisibilityChanged = function(self, module)
                visibilityChanges = visibilityChanges + 1
            end,
        }
        local module = imodule.new({ resource = resource, manager = fakeManager })
        local descriptor = document.Descriptor("memory/visibility-state.json", "Visibility State",
            "Visibility state test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Visibility State")
        end)
        module.entries = { entry }

        module:Unpublish()
        module:Publish()
        module:Publish()
        module:Unpublish()
        module:Unpublish()

        unitwind:expect(visibilityChanges).toBe(2)
    end)

    testMemoryModule("Memory module does not publish on loaded by default", function()
        local published = {}
        local unpublished = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                table.insert(unpublished, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/load-default.json", "Load Default", "Load default test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Load Default")
        end)
        module.entries = { entry }

        module:OnLoaded({ claim = function() end, filename = "", newGame = false, quickload = false })

        unitwind:expect(table.size(published)).toBe(0)
        unitwind:expect(unpublished[1]).toBe("morrowind://memory/load-default.json")
    end)

    testMemoryModule("Memory module can opt in to publish on loaded", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource, publishOnLoaded = true })
        local descriptor = document.Descriptor("memory/load-opt-in.json", "Load Opt In", "Load opt-in test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Load Opt In")
        end)
        module.entries = { entry }

        module:OnLoaded({ claim = function() end, filename = "", newGame = false, quickload = false })

        unitwind:expect(published[1]).toBe("morrowind://memory/load-opt-in.json")
    end)

    testMemoryModule("Memory manager publishes only modules that opt in on register", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local memory = manager.new({ resource = resource })
        local defaultModule = imodule.new({ resource = resource })
        local optInModule = imodule.new({ resource = resource, publishOnRegister = true })
        local defaultDescriptor = document.Descriptor("memory/register-default.json", "Register Default",
            "Register default test.")
        local optInDescriptor = document.Descriptor("memory/register-opt-in.json", "Register Opt In",
            "Register opt-in test.")
        defaultModule.entries = { document.LiveEntry(defaultDescriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Register Default")
        end) }
        optInModule.entries = { document.LiveEntry(optInDescriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Register Opt In")
        end) }
        memory.modules = { defaultModule, optInModule }

        memory:PublishOnRegisterModules()

        unitwind:expect(table.size(published)).toBe(1)
        unitwind:expect(published[1]).toBe("morrowind://memory/register-opt-in.json")
    end)

    testMemoryModule("Memory manager publishes only root index on register for built-in modules", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local memory = manager.new({ resource = resource })

        memory:PublishOnRegisterModules()

        unitwind:expect(table.size(published)).toBe(1)
        unitwind:expect(published[1]).toBe("morrowind://memory/index.json")
    end)

    testMemoryModule("Memory manager saves current debug documents once per URI", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local memory = manager.new({ resource = resource })
        local firstDescriptor = document.Descriptor("memory/debug/first.json", "First", "First debug test.")
        local secondDescriptor = document.Descriptor("memory/debug/second.json", "Second", "Second debug test.")
        local firstEntry = document.LiveEntry(firstDescriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "First")
        end)
        local secondEntry = document.LiveEntry(secondDescriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Second")
        end)
        local firstModule = imodule.new({ resource = resource })
        firstModule.entries = { firstEntry, secondEntry }
        local duplicateModule = imodule.new({ resource = resource })
        duplicateModule.entries = { firstEntry }
        memory.modules = { firstModule, duplicateModule }
        local savedCalls = {}
        unitwind:mock(document, "SaveEntry", function(entry, rootDir)
            table.insert(savedCalls, { uri = entry.descriptor.uri, rootDir = rootDir })
            return {
                uri = entry.descriptor.uri,
                file_path = rootDir .. entry.descriptor.name,
                bytes = 2,
            }
        end)

        local results = memory:SaveDebugDocuments("debug\\")

        unitwind:expect(table.size(results)).toBe(2)
        unitwind:expect(table.size(savedCalls)).toBe(2)
        unitwind:expect(savedCalls[1].uri).toBe("morrowind://memory/debug/first.json")
        unitwind:expect(savedCalls[1].rootDir).toBe("debug\\")
        unitwind:expect(savedCalls[2].uri).toBe("morrowind://memory/debug/second.json")

        unitwind:unmock(document, "SaveEntry")
    end)

    testMemoryModule("Memory manager groups links by parent", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local memory = manager.new({ resource = resource })
        local rootModule = imodule.new({ resource = resource })
        local playerUri = "morrowind://memory/player/index.json"
        local playerChildModule = imodule.new({ resource = resource, parentUri = playerUri })
        local rootDescriptor = document.Descriptor("memory/root-link.json", "Root Link", "Root link test.")
        local childDescriptor = document.Descriptor("memory/player/child-link.json", "Child Link", "Child link test.")
        rootModule.links = { document.Link(document.linkRel.self, rootDescriptor.uri, rootDescriptor.title,
            rootDescriptor.description) }
        rootModule.published = true
        playerChildModule.links = { document.Link(document.linkRel.journal, childDescriptor.uri, childDescriptor.title,
            childDescriptor.description) }
        playerChildModule.published = true
        memory.modules = { rootModule, playerChildModule }

        local rootLinks = memory:GetRootLinks()
        local playerLinks = memory:GetLinksForParent(playerUri)

        unitwind:expect(table.size(rootLinks)).toBe(1)
        unitwind:expect(rootLinks[1].uri).toBe("morrowind://memory/root-link.json")
        unitwind:expect(table.size(playerLinks)).toBe(1)
        unitwind:expect(playerLinks[1].uri).toBe("morrowind://memory/player/child-link.json")
    end)

    testMemoryModule("Memory visibility changes dirty only related link indexes", function()
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local memory = manager.new({ resource = resource })
        ---@type MCP.MemoryResourceEntry?
        local indexEntry = nil
        ---@type MCP.MemoryResourceEntry?
        local playerEntry = nil
        for _, module in ipairs(memory.modules) do
            local entry = module.entries and module.entries[1]
            if entry and entry.descriptor.uri == "morrowind://memory/index.json" then
                indexEntry = entry
            elseif entry and entry.descriptor.uri == "morrowind://memory/player/index.json" then
                playerEntry = entry
            end
        end
        if not indexEntry or not playerEntry then
            error("Built-in Memory index or player entry was not registered.")
        end
        local topLevelModule = imodule.new({ resource = resource })
        local playerChildModule = imodule.new({ resource = resource, parentUri = "morrowind://memory/player/index.json" })

        indexEntry.cache.dirty = false
        playerEntry.cache.dirty = false
        memory:OnModuleVisibilityChanged(topLevelModule)

        unitwind:expect(indexEntry.cache.dirty).toBe(true)
        unitwind:expect(playerEntry.cache.dirty).toBe(false)

        indexEntry.cache.dirty = false
        playerEntry.cache.dirty = false
        memory:OnModuleVisibilityChanged(playerChildModule)

        unitwind:expect(indexEntry.cache.dirty).toBe(false)
        unitwind:expect(playerEntry.cache.dirty).toBe(true)
    end)

    testMemoryModule("Memory Actor module manages observed actor instances internally", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local fakeManager = {
            GetScope = function(self)
                return document.Scope(1)
            end,
            OnModuleVisibilityChanged = function(self, module)
            end,
        }
        local function object(id, name, objectType)
            return {
                id = id,
                name = name,
                objectType = objectType,
                attributes = {},
                skills = {},
                isValid = function(self)
                    return true
                end,
            }
        end
        local function reference(object, baseObject, params)
            params = params or {}
            return {
                id = object.id,
                objectType = tes3.objectType.reference,
                object = object,
                baseObject = baseObject or object,
                isRespawn = params.isRespawn == true,
                isLeveledSpawn = params.isLeveledSpawn == true,
                leveledBaseReference = params.leveledBaseReference,
                isValid = function(self)
                    return true
                end,
            }
        end
        local ratBaseObject = object("rat", "Rat", tes3.objectType.creature)
        local ratInstance = object("rat00000004", "Rat", tes3.objectType.creature)
        ratInstance.isInstance = true
        ratInstance.baseObject = ratBaseObject
        local guard = object("imperial guard", "Guard", tes3.objectType.npc)
        guard.isRespawn = true
        guard.isGuard = true
        local din = object("din", "Din", tes3.objectType.npc)
        din.isRespawn = true
        local caius = reference(object("caius cosades", "Caius Cosades", tes3.objectType.npc))
        local fargoth = reference(object("fargoth", "Fargoth", tes3.objectType.npc))
        local rat = reference(ratInstance, ratBaseObject, { isLeveledSpawn = true })
        local guardRef = reference(guard)
        local dinRef = reference(din)
        caius.nextNode = fargoth
        fargoth.nextNode = rat
        rat.nextNode = guardRef
        guardRef.nextNode = dinRef
        local activeCells = {
            {
                actors = {
                    size = 5,
                    head = caius,
                },
            },
        }
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "getActiveCells", function()
            return activeCells
        end)

        local module = actor.new({ resource = resource, manager = fakeManager })
        module:Publish()

        local rootLinks = module:GetLinksForParent(nil)
        local actorLinks = module:GetLinksForParent("morrowind://memory/actors/index.json")
        local indexDocument = module:BuildIndexDocument()

        unitwind:expect(table.size(published)).toBe(6)
        unitwind:expect(published[1]).toBe("morrowind://memory/actors/index.json")
        unitwind:expect(table.size(rootLinks)).toBe(1)
        unitwind:expect(rootLinks[1].uri).toBe("morrowind://memory/actors/index.json")
        unitwind:expect(table.size(actorLinks)).toBe(5)
        unitwind:expect(actorLinks[1].uri).toBe("morrowind://memory/actors/caius-cosades/index.json")
        unitwind:expect(actorLinks[1].description).toBe(
        "data_type=npc_summary base_id=caius cosades reference_id=caius cosades identity_kind=unique interaction_state=observed")
        unitwind:expect(actorLinks[2].uri).toBe("morrowind://memory/actors/fargoth/index.json")
        unitwind:expect(actorLinks[3].uri).toBe("morrowind://memory/actors/rat/index.json")
        unitwind:expect(actorLinks[3].description).toBe(
        "data_type=creature_summary base_id=rat reference_id=rat00000004 identity_kind=generic interaction_state=observed")
        unitwind:expect(actorLinks[4].description).toBe(
        "data_type=npc_summary base_id=imperial guard reference_id=imperial guard identity_kind=generic interaction_state=observed")
        unitwind:expect(actorLinks[5].description).toBe(
        "data_type=npc_summary base_id=din reference_id=din identity_kind=unique interaction_state=observed")
        unitwind:expect(indexDocument.data.actor_count).toBe(5)
        unitwind:expect(indexDocument.data.actors == nil).toBe(true)
        unitwind:expect(table.size(indexDocument.links)).toBe(5)
        unitwind:expect(module.observedActors["caius-cosades"].subject.tes3_type).toBe("tes3npc")
        unitwind:expect(module.observedActors["caius-cosades"].data_type).toBe("npc_summary")
        unitwind:expect(module.observedActors["caius-cosades"].data.interaction.state).toBe("observed")
        unitwind:expect(module.observedActors["caius-cosades"].data.interaction.source_kinds[1]).toBe("active_cells")
        unitwind:expect(module.observedActors["caius-cosades"].data.interaction.activation_count).toBe(0)
        unitwind:expect(module.observedActors["rat"].subject.tes3_type).toBe("tes3creature")
        unitwind:expect(module.observedActors["rat"].data_type).toBe("creature_summary")
        unitwind:expect(module.observedActors["rat"].data.base_id).toBe("rat")
        unitwind:expect(module.observedActors["rat"].data.reference_id).toBe("rat00000004")
        unitwind:expect(module.observedActors["rat"].data.is_instance).toBe(true)
        unitwind:expect(module.observedActors["rat"].data.identity_kind).toBe("generic")
        unitwind:expect(module.observedActors["imperial-guard"].data.identity_kind).toBe("generic")
        unitwind:expect(module.observedActors["din"].data.identity_kind).toBe("unique")

        unitwind:unmock(tes3, "getActiveCells")
        unitwind:unmock(tes3, "onMainMenu")
    end)

    testMemoryModule("Memory Actor module adds activation target without clearing loaded actors", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local fakeManager = {
            GetScope = function(self)
                return document.Scope(1)
            end,
            OnModuleVisibilityChanged = function(self, module)
            end,
        }
        local function object(id, name, objectType)
            return {
                id = id,
                name = name,
                objectType = objectType,
                attributes = {},
                skills = {},
                isValid = function(self)
                    return true
                end,
            }
        end
        local function reference(object)
            return {
                id = object.id,
                objectType = tes3.objectType.reference,
                object = object,
                baseObject = object,
                isValid = function(self)
                    return true
                end,
            }
        end
        local caius = reference(object("caius cosades", "Caius Cosades", tes3.objectType.npc))
        local fargoth = reference(object("fargoth", "Fargoth", tes3.objectType.npc))
        local activeCells = {
            {
                actors = {
                    size = 1,
                    head = caius,
                },
            },
        }
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "getActiveCells", function()
            return activeCells
        end)

        local module = actor.new({ resource = resource, manager = fakeManager })
        module:Publish()
        module:OnActivationTargetChanged({ claim = function() end, current = fargoth, previous = caius })
        module:OnActivationTargetChanged({ claim = function() end, current = fargoth, previous = caius })

        local actorLinks = module:GetLinksForParent("morrowind://memory/actors/index.json")
        local indexDocument = module:BuildIndexDocument()

        unitwind:expect(table.size(actorLinks)).toBe(2)
        unitwind:expect(actorLinks[1].uri).toBe("morrowind://memory/actors/caius-cosades/index.json")
        unitwind:expect(actorLinks[2].uri).toBe("morrowind://memory/actors/fargoth/index.json")
        unitwind:expect(indexDocument.data.actor_count).toBe(2)
        unitwind:expect(module.observedActors["caius-cosades"] ~= nil).toBe(true)
        unitwind:expect(module.observedActors["fargoth"].source_description).toBe(
        "Observed actor reference from activationTargetChanged.")
        unitwind:expect(module.observedActors["fargoth"].data.interaction.state).toBe("targeted")
        unitwind:expect(module.observedActors["fargoth"].data.interaction.source_kinds[1]).toBe(
        "activation_target_changed")
        unitwind:expect(published[#published]).toBe("morrowind://memory/actors/fargoth/index.json")

        unitwind:unmock(tes3, "getActiveCells")
        unitwind:unmock(tes3, "onMainMenu")
    end)

    testMemoryModule("Memory Actor module marks player-activated actors", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local fakeManager = {
            GetScope = function(self)
                return document.Scope(1)
            end,
            OnModuleVisibilityChanged = function(self, module)
            end,
        }
        local function object(id, name, objectType)
            return {
                id = id,
                name = name,
                objectType = objectType,
                attributes = {},
                skills = {},
                isValid = function(self)
                    return true
                end,
            }
        end
        local function reference(object)
            return {
                id = object.id,
                objectType = tes3.objectType.reference,
                object = object,
                baseObject = object,
                isValid = function(self)
                    return true
                end,
            }
        end
        local playerObject = object("player", "Player", tes3.objectType.npc)
        local playerRef = reference(playerObject)
        local caius = reference(object("caius cosades", "Caius Cosades", tes3.objectType.npc))
        local activeCells = {
            {
                actors = {
                    size = 1,
                    head = caius,
                },
            },
        }
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "getActiveCells", function()
            return activeCells
        end)

        local module = actor.new({ resource = resource, manager = fakeManager })
        module:Publish()
        module:OnActivate({ block = false, claim = false, activator = playerRef, target = caius })
        module:OnActivate({ block = false, claim = false, activator = playerRef, target = caius })

        local actorLinks = module:GetLinksForParent("morrowind://memory/actors/index.json")
        local observedActor = module.observedActors["caius-cosades"]
        local actorDocument = module:BuildActorDocument("caius-cosades")
        local debugActorDocument = module:BuildActorDocument("caius-cosades")

        unitwind:expect(table.size(actorLinks)).toBe(1)
        unitwind:expect(actorLinks[1].description).toBe(
        "data_type=npc_summary base_id=caius cosades reference_id=caius cosades identity_kind=unique interaction_state=activated")
        unitwind:expect(observedActor.source_description).toBe("Observed actor reference from activate.")
        unitwind:expect(observedActor.data.interaction.state).toBe("activated")
        unitwind:expect(observedActor.data.interaction.activation_count).toBe(2)
        unitwind:expect(observedActor.data.interaction.conversation_count).toBe(0)
        unitwind:expect(table.size(observedActor.data.interaction.source_kinds)).toBe(2)
        unitwind:expect(observedActor.data.interaction.source_kinds[1]).toBe("active_cells")
        unitwind:expect(observedActor.data.interaction.source_kinds[2]).toBe("activate")
        unitwind:expect(actorDocument ~= nil).toBe(true)
        unitwind:expect(debugActorDocument ~= nil).toBe(true)
        ---@cast actorDocument MCP.MemoryDocument
        ---@cast debugActorDocument MCP.MemoryDocument
        local actorData = actorDocument.data
        local debugActorData = debugActorDocument.data
        unitwind:expect(actorData.reference == nil).toBe(true)
        unitwind:expect(actorData.debug == nil).toBe(true)
        unitwind:expect(actorData.observations == nil).toBe(true)
        unitwind:expect(actorData.facts.name).toBe("Caius Cosades")
        unitwind:expect(actorData.facts.data_type).toBe("npc_summary")
        unitwind:expect(actorData.interaction.state).toBe("activated")
        unitwind:expect(actorData.interaction.activated).toBe(true)
        unitwind:expect(debugActorData.debug == nil).toBe(true)

        unitwind:unmock(tes3, "getActiveCells")
        unitwind:unmock(tes3, "onMainMenu")
    end)

    testMemoryModule("Memory Actor module marks dialog service actors as conversed", function()
        local published = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                table.insert(published, entry.descriptor.uri)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        local fakeManager = {
            GetScope = function(self)
                return document.Scope(1)
            end,
            OnModuleVisibilityChanged = function(self, module)
            end,
        }
        local function object(id, name, objectType, actorClass)
            return {
                id = id,
                name = name,
                objectType = objectType,
                class = actorClass,
                attributes = {},
                skills = {},
                isValid = function(self)
                    return true
                end,
            }
        end
        local function reference(object)
            return {
                id = object.id,
                objectType = tes3.objectType.reference,
                object = object,
                baseObject = object,
                isValid = function(self)
                    return true
                end,
            }
        end
        local serviceClass = {
            id = "agent",
            name = "Agent",
            offersBartering = true,
            offersSpells = true,
            offersTraining = true,
            bartersIngredients = true,
            bartersWeapons = true,
        }
        local caius = reference(object("caius cosades", "Caius Cosades", tes3.objectType.npc, serviceClass))
        local activeCells = {
            {
                actors = {
                    size = 1,
                    head = caius,
                },
            },
        }
        unitwind:mock(tes3, "onMainMenu", function()
            return false
        end)
        unitwind:mock(tes3, "getActiveCells", function()
            return activeCells
        end)
        unitwind:mock(tes3ui, "getServiceActor", function()
            return { reference = caius }
        end)
        ---@param newlyCreated boolean
        ---@return uiActivatedEventData
        local function uiActivatedEvent(newlyCreated)
            ---@diagnostic disable-next-line: missing-fields
            return { claim = false, newlyCreated = newlyCreated, element = {} }
        end

        local module = actor.new({ resource = resource, manager = fakeManager })
        module:Publish()
        module:OnMenuDialogActivated(uiActivatedEvent(false))
        module:OnMenuDialogActivated(uiActivatedEvent(true))
        module:OnMenuDialogActivated(uiActivatedEvent(true))

        local actorLinks = module:GetLinksForParent("morrowind://memory/actors/index.json")
        local observedActor = module.observedActors["caius-cosades"]
        local actorDocument = module:BuildActorDocument("caius-cosades")

        unitwind:expect(table.size(actorLinks)).toBe(1)
        unitwind:expect(actorLinks[1].description).toBe(
        "data_type=npc_summary base_id=caius cosades reference_id=caius cosades identity_kind=unique interaction_state=conversed")
        unitwind:expect(observedActor.source_description).toBe("Observed actor reference from MenuDialog.")
        unitwind:expect(observedActor.data.interaction.state).toBe("conversed")
        unitwind:expect(observedActor.data.interaction.activation_count).toBe(0)
        unitwind:expect(observedActor.data.interaction.conversation_count).toBe(2)
        unitwind:expect(table.size(observedActor.data.interaction.source_kinds)).toBe(2)
        unitwind:expect(observedActor.data.interaction.source_kinds[1]).toBe("active_cells")
        unitwind:expect(observedActor.data.interaction.source_kinds[2]).toBe("menu_dialog")
        unitwind:expect(actorDocument ~= nil).toBe(true)
        ---@cast actorDocument MCP.MemoryDocument
        local actorData = actorDocument.data
        unitwind:expect(actorData.observations == nil).toBe(true)
        unitwind:expect(actorData.interaction.state).toBe("conversed")
        unitwind:expect(actorData.interaction.conversed).toBe(true)
        unitwind:expect(actorData.facts.services.offers.bartering).toBe(true)
        unitwind:expect(actorData.facts.services.offers.spells).toBe(true)
        unitwind:expect(actorData.facts.services.offers.training).toBe(true)
        unitwind:expect(actorData.facts.services.barters.ingredients).toBe(true)
        unitwind:expect(actorData.facts.services.barters.weapons).toBe(true)
        unitwind:expect(actorData.debug == nil).toBe(true)

        unitwind:unmock(tes3ui, "getServiceActor")
        unitwind:unmock(tes3, "getActiveCells")
        unitwind:unmock(tes3, "onMainMenu")
    end)

    testMemoryModule("Memory module hides links after unpublish", function()
        local unpublished = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                table.insert(unpublished, uri)
                return true
            end,
        }
        local module = imodule.new({ resource = resource })
        local descriptor = document.Descriptor("memory/unpublish.json", "Unpublish", "Unpublish test.")
        local entry = document.LiveEntry(descriptor, function()
            return document.Document(document.documentType.entity, document.dataType.playerSummary, "Unpublish")
        end)
        module.entries = { entry }
        module.links = { document.Link(document.linkRel.self, descriptor.uri, descriptor.title, descriptor.description) }

        module:Publish()
        unitwind:expect(module:GetLinks()[1].uri).toBe("morrowind://memory/unpublish.json")

        module:Unpublish()
        unitwind:expect(unpublished[1]).toBe("morrowind://memory/unpublish.json")
        unitwind:expect(table.size(module:GetLinks())).toBe(0)
    end)

    testMemoryModule("Memory manager registers loaded before module loaded callbacks", function()
        local registered = {}
        ---@type MCP.IResourceManager
        local resource = {
            Release = function(self)
            end,
            PublishResource = function(self, entry)
                return entry.descriptor.uri
            end,
            UnpublishResource = function(self, uri)
                return true
            end,
        }
        unitwind:mock(event, "register", function(eventId, callback, options)
            table.insert(registered, {
                eventId = eventId,
                callback = callback,
                options = options,
            })
        end)
        unitwind:mock(event, "unregister", function(eventId, callback)
        end)

        local memory = manager.new({ resource = resource })
        memory:RegisterEvent()

        unitwind:expect(registered[1].eventId).toBe(tes3.event.loaded)
        unitwind:expect(registered[1].options.priority).toBe(100)

        memory:UnregisterEvent()
        unitwind:unmock(event, "unregister")
        unitwind:unmock(event, "register")
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
