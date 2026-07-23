local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local dialogue = require("morrowind-mcp.util.dialogue")
local datetime = require("morrowind-mcp.util.datetime")

--- Memory module for dialogue text that should not be assigned to an actor.
---@class MCP.Resources.Memory.UnattributedDialogue: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field data MCP.AnyMap
---@field topicIndex table<string, boolean>
---@field observationIndex table<string, MCP.AnyMap>
---@field infoGetTextCallback fun(e: infoGetTextEventData)?
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/unattributed/dialogue.json",
    "Unattributed Dialogue Memory",
    "Dialogue text observed without a resolved actor."
)

local rootLink = document.Link(
    document.linkRel.unattributed,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

--- Return a compact observation timestamp for dialogue histories.
---@return MCP.AnyMap
local function ObservationTimestamp()
    local timestamp = document.TimestampNow()
    return jsonrpc.object({
        system_time = timestamp.system_time,
        in_game_time = datetime.ToInGameShortText(timestamp.in_game_time),
    })
end

--- Return displayed dialogue text from an infoGetText event.
---@param eventData infoGetTextEventData
---@return string?
local function TextFromInfoGetText(eventData)
    if type(eventData.text) == "string" and eventData.text ~= "" then
        return eventData.text
    end
    if type(eventData.loadOriginalText) == "function" then
        return eventData:loadOriginalText()
    end
    return eventData.info and eventData.info.text
end

--- Return the dialogue record for an infoGetText event when MWSE exposes it.
---@param eventData infoGetTextEventData
---@return tes3dialogue?
local function DialogueFromInfoGetText(eventData)
    if eventData.info and type(eventData.info.findDialogue) == "function" then
        return eventData.info:findDialogue()
    end
    return nil
end

--- Return true when this voice subtitle has an actor source exposed by MWSE.
---@param eventData infoGetTextEventData
---@return boolean
local function HasResolvedActor(eventData)
    if eventData.info and eventData.info.actor then
        return true
    end

    local ok, serviceActor = pcall(function()
        return tes3ui.getServiceActor()
    end)
    if not ok or not serviceActor then
        return false
    end
    return (serviceActor.reference or serviceActor) ~= nil
end

--- Return true for actor-unresolved voice subtitles worth keeping outside Actor Memory.
---@param eventData infoGetTextEventData
---@return boolean
local function IsUnattributedVoice(eventData)
    return eventData
        and eventData.info
        and eventData.info.type == tes3.dialogueType.voice
        and not HasResolvedActor(eventData)
end

--- Build a define source that intentionally lacks an actor speaker.
---@param eventData infoGetTextEventData
---@return MCP.DialogueDefineSourceContext
local function DialogueDefineSource(eventData)
    return {
        player = tes3.player,
        actor = nil,
        dialogueInfo = eventData.info,
    }
end

--- Resolve safe dialogue defines and topic markup without inventing an actor identity.
---@param eventData infoGetTextEventData
---@param rawText string?
---@return string?
---@return string[]?
---@return string?
local function NormalizeObservationText(eventData, rawText)
    if type(rawText) ~= "string" or rawText == "" then
        return nil, nil, nil
    end

    local defineContext = dialogue.BuildDialogueDefineContext(DialogueDefineSource(eventData))
    local replacedText = dialogue.ReplaceDialogueDefines(rawText, defineContext)
    local normalizedText, linkedTopics = dialogue.NormalizeDialogueText(replacedText)
    local outputText = normalizedText ~= "" and normalizedText or nil
    local rawOutput = rawText ~= normalizedText and rawText or nil
    ---@type string[]?
    local outputTopics = linkedTopics
    if linkedTopics and table.size(linkedTopics) == 0 then
        outputTopics = nil
    end
    return outputText, outputTopics, rawOutput
end

--- Return the normalized key used for case-insensitive topic storage.
---@param topic string?
---@return string?
local function TopicKey(topic)
    if type(topic) ~= "string" or topic == "" then
        return nil
    end
    return topic:lower()
end

--- Add one topic to the exported lower-case topic array.
---@param module MCP.Resources.Memory.UnattributedDialogue
---@param topic string?
local function AddTopic(module, topic)
    local key = TopicKey(topic)
    if not key or module.topicIndex[key] then
        return
    end
    module.topicIndex[key] = true
    table.insert(module.data.topics, key)
end

--- Add linked topics without duplicating them.
---@param module MCP.Resources.Memory.UnattributedDialogue
---@param topics string[]?
local function AddTopics(module, topics)
    for _, topic in ipairs(topics or {}) do
        AddTopic(module, topic)
    end
end

--- Encode one key part with its byte length so adjacent fields cannot collide.
---@param value any
---@return string
local function ObservationKeyPart(value)
    local text = value == nil and "" or tostring(value)
    return string.format("%d:%s", string.len(text), text)
end

--- Build the runtime-only key used to aggregate repeated dialogue observations.
---@param observation MCP.AnyMap
---@return string?
local function ObservationKey(observation)
    if observation.event and observation.info_id then
        return table.concat({
            ObservationKeyPart(observation.event),
            ObservationKeyPart(observation.info_id),
        }, "|")
    end
    return nil
end

--- Add one unique observation to the runtime-only duplicate lookup.
---@param module MCP.Resources.Memory.UnattributedDialogue
---@param observation MCP.AnyMap
local function RegisterObservation(module, observation)
    local key = ObservationKey(observation)
    if key then
        module.observationIndex[key] = observation
    end
end

--- Return an existing observation when the new observation repeats the same captured fact.
---@param module MCP.Resources.Memory.UnattributedDialogue
---@param observation MCP.AnyMap
---@return MCP.AnyMap?
local function FindDuplicateObservation(module, observation)
    local key = ObservationKey(observation)
    return key and module.observationIndex[key] or nil
end

--- Build a compact text observation from an actor-unresolved infoGetText voice event.
---@param eventData infoGetTextEventData
---@return MCP.AnyMap
local function TextObservation(eventData)
    local dialogueRecord = DialogueFromInfoGetText(eventData)
    local infoId = eventData.info and eventData.info.id
    local text, linkedTopics, rawText = NormalizeObservationText(eventData, TextFromInfoGetText(eventData))
    return jsonrpc.object({
        observed_at = ObservationTimestamp(),
        event = "info_get_text",
        dialogue_id = dialogueRecord and dialogueRecord.id,
        info_id = infoId and tostring(infoId) or nil,
        dialogue_type = eventData.info and eventData.info.type,
        text = text,
        raw_text = rawText,
        linked_topics = linkedTopics,
        repeat_count = 1,
    })
end

--- Create an actor-unresolved dialogue module that becomes visible after a loaded game exists.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.UnattributedDialogue
function this.new(params)
    params.publishOnLoaded = true
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_unattributed_dialogue" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.UnattributedDialogue
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ rootLink })
    instance:ClearData()
    return instance
end

--- Clear runtime dialogue observations for a newly loaded game scope.
function this:ClearData()
    self.topicIndex = {}
    self.observationIndex = {}
    self.data = jsonrpc.object({
        topics = jsonrpc.array(),
        text_count = 0,
        observations = jsonrpc.array(),
    })
    document.MarkDirty(self.entry)
end

--- Append one actor-unresolved voice observation, aggregating exact repeated info records.
---@param eventData infoGetTextEventData
---@return boolean changed
function this:AddObservation(eventData)
    local observation = TextObservation(eventData)
    local duplicateObservation = FindDuplicateObservation(self, observation)
    if duplicateObservation then
        duplicateObservation.repeat_count = (duplicateObservation.repeat_count or 1) + 1
        duplicateObservation.last_observed_at = observation.observed_at
        document.MarkDirty(self.entry)
        return false
    end

    self.data.text_count = (self.data.text_count or 0) + 1
    table.insert(self.data.observations, observation)
    RegisterObservation(self, observation)
    AddTopics(self, observation.linked_topics)
    document.MarkDirty(self.entry)
    return true
end

--- Record only voice subtitles that MWSE did not expose with a direct actor source.
---@param e infoGetTextEventData
function this:OnInfoGetText(e)
    if not IsUnattributedVoice(e) then
        return
    end

    local changed = self:AddObservation(e)
    if not self.published then
        self:Publish()
    end
    self.logger:debug(
        "Memory unattributed dialogue observed: texts=%d changed=%s info_id=%s",
        self.data.text_count or 0,
        tostring(changed),
        e.info and e.info.id or ""
    )
end

--- Register the actor-unresolved dialogue event handler.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.infoGetTextCallback then
        return
    end

    self.infoGetTextCallback = function(e)
        self:OnInfoGetText(e)
    end
    event.register(tes3.event.infoGetText, self.infoGetTextCallback)
    self.logger:debug("Memory unattributed dialogue infoGetText handler registered")
end

--- Unregister the actor-unresolved dialogue event handler.
function this:UnregisterEvent()
    if self.infoGetTextCallback then
        event.unregister(tes3.event.infoGetText, self.infoGetTextCallback)
        self.infoGetTextCallback = nil
        self.logger:debug("Memory unattributed dialogue infoGetText handler unregistered")
    end
    base.UnregisterEvent(self)
end

--- Hide stale unattributed dialogue for a new game; otherwise reset and publish after loading a save.
---@param e loadedEventData
function this:OnLoaded(e)
    self:ClearData()
    if e.newGame then
        self:Unpublish()
        return
    end
    base.OnLoaded(self, e)
end

--- Build the actor-unresolved dialogue Memory document.
---@return MCP.MemoryDocument
function this:BuildDocument()
    return document.Document(
        document.documentType.observation,
        document.dataType.unattributedDialogueNotes,
        descriptor.title,
        self.data,
        {
            subject = document.Subject("unattributed", "dialogue", descriptor.title),
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.event, nil, "infoGetText", descriptor.description),
        }
    )
end

return this
