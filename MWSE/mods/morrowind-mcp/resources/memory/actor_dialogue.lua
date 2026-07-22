local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local document = require("morrowind-mcp.resources.memory.document")
local dialogue = require("morrowind-mcp.util.dialogue")
local datetime = require("morrowind-mcp.util.datetime")

--- Helpers for actor-local dialogue Memory child resources.
--- Actor Memory owns the lifecycle; this module owns the dialogue payload shape.
local this = {}

--- Extract vanilla Choice command options into a lightweight list.
---@param command string?
---@return MCP.AnyMap[]?
local function ParseChoiceCommand(command)
    if type(command) ~= "string" then
        return nil
    end

    local rest = string.match(command, "^%s*[Cc]hoice%s*,%s*(.+)$")
    if not rest then
        return nil
    end

    local choices = jsonrpc.array()
    for label, value in string.gmatch(rest, "\"([^\"]*)\"%s*,%s*([%-]?%d+)") do
        table.insert(choices, jsonrpc.object({
            label = label,
            value = tonumber(value),
        }))
    end
    if table.size(choices) == 0 then
        return nil
    end
    return choices
end

--- Add one topic id to dialogue data without duplicating it.
---@param dialogueData MCP.AnyMap
---@param topic string?
local function AddTopic(dialogueData, topic)
    if not topic or topic == "" then
        return
    end
    dialogueData.topics = dialogueData.topics or jsonrpc.array()
    for _, existingTopic in ipairs(dialogueData.topics) do
        if existingTopic == topic then
            return
        end
    end
    table.insert(dialogueData.topics, topic)
end

--- Add all topic ids from a normalized text parse result without duplicating them.
---@param dialogueData MCP.AnyMap
---@param topics string[]?
local function AddTopics(dialogueData, topics)
    for _, topic in ipairs(topics or {}) do
        AddTopic(dialogueData, topic)
    end
end

--- Build a compact observation timestamp; dialogue histories can repeat many times in one document.
---@return MCP.AnyMap
local function ObservationTimestamp()
    local timestamp = document.TimestampNow()
    return jsonrpc.object({
        system_time = timestamp.system_time,
        in_game_time = datetime.ToInGameShortText(timestamp.in_game_time),
    })
end

--- Build a lightweight speaker object from actor facts for dialogue define replacement.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.DialogueDefineSourceActor
local function SpeakerFromObservedActor(observedActor)
    local facts = observedActor.data and observedActor.data.facts or {}
    return {
        name = facts.name,
        race = facts.race and { name = facts.race.name } or nil,
        class = facts.class and { name = facts.class.name } or nil,
    }
end

--- Return a dialogue define source context for one observed actor and event.
---@param observedActor MCP.MemoryObservedActor
---@param eventData infoResponseEventData|postInfoResponseEventData|infoGetTextEventData
---@return MCP.DialogueDefineSourceContext
local function DialogueDefineSource(observedActor, eventData)
    local facts = observedActor.data and observedActor.data.facts or {}
    local location = facts.location
    return {
        player = tes3.player,
        actor = (eventData.info and eventData.info.actor) or SpeakerFromObservedActor(observedActor),
        dialogueInfo = eventData.info,
        cell = location and { displayName = location.display_name or location.name } or nil,
    }
end

--- Resolve dialogue defines, normalize topic markup, and return fields for an observation.
---@param observedActor MCP.MemoryObservedActor
---@param eventData infoResponseEventData|postInfoResponseEventData|infoGetTextEventData
---@param rawText string?
---@return string?
---@return string[]?
---@return string?
local function NormalizeObservationText(observedActor, eventData, rawText)
    if type(rawText) ~= "string" or rawText == "" then
        return nil, nil, nil
    end

    local defineContext = dialogue.BuildDialogueDefineContext(DialogueDefineSource(observedActor, eventData))
    local replacedText = dialogue.ReplaceDialogueDefines(rawText, defineContext)
    local normalizedText, linkedTopics = dialogue.NormalizeDialogueText(replacedText)
    ---@type string?
    local outputText = normalizedText
    if normalizedText == "" then
        outputText = nil
    end
    local rawOutput = rawText ~= normalizedText and rawText or nil
    ---@type string[]?
    local outputTopics = linkedTopics
    if linkedTopics and table.size(linkedTopics) == 0 then
        outputTopics = nil
    end
    return outputText, outputTopics, rawOutput
end

--- Return the displayed text from an infoGetText event, loading the original text when no override is present.
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

--- Return the topic/dialogue record for an infoGetText event when MWSE exposes it.
---@param eventData infoGetTextEventData
---@return tes3dialogue?
local function DialogueFromInfoGetText(eventData)
    if eventData.info and type(eventData.info.findDialogue) == "function" then
        return eventData.info:findDialogue()
    end
    return nil
end

--- Build a compact dialogue event observation from an infoResponse-like event.
---@param observedActor MCP.MemoryObservedActor
---@param eventName string
---@param eventData infoResponseEventData|postInfoResponseEventData
---@return MCP.AnyMap
local function ResponseObservation(observedActor, eventName, eventData)
    local dialogueId = eventData.dialogue and eventData.dialogue.id
    local infoId = eventData.info and eventData.info.id
    local text, linkedTopics, rawText = NormalizeObservationText(observedActor, eventData, eventData.info and eventData.info.text)
    return jsonrpc.object({
        observed_at = ObservationTimestamp(),
        event = eventName,
        dialogue_id = dialogueId,
        info_id = infoId and tostring(infoId) or nil,
        command = eventData.command,
        text = text,
        raw_text = rawText,
        linked_topics = linkedTopics,
        choices = ParseChoiceCommand(eventData.command),
        repeat_count = 1,
    })
end

--- Build a compact dialogue text observation from an infoGetText event.
---@param observedActor MCP.MemoryObservedActor
---@param eventName string
---@param eventData infoGetTextEventData
---@return MCP.AnyMap
local function TextObservation(observedActor, eventName, eventData)
    local dialogue = DialogueFromInfoGetText(eventData)
    local infoId = eventData.info and eventData.info.id
    local text, linkedTopics, rawText = NormalizeObservationText(observedActor, eventData, TextFromInfoGetText(eventData))
    return jsonrpc.object({
        observed_at = ObservationTimestamp(),
        event = eventName,
        dialogue_id = dialogue and dialogue.id,
        info_id = infoId and tostring(infoId) or nil,
        dialogue_type = eventData.info and eventData.info.type,
        text = text,
        raw_text = rawText,
        linked_topics = linkedTopics,
        repeat_count = 1,
    })
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
    if observation.event == "info_get_text" then
        return table.concat({
            ObservationKeyPart(observation.event),
            ObservationKeyPart(observation.info_id),
            ObservationKeyPart(observation.text),
        }, "|")
    end
    if observation.event == "info_response" then
        return table.concat({
            ObservationKeyPart(observation.event),
            ObservationKeyPart(observation.info_id),
            ObservationKeyPart(observation.command),
            ObservationKeyPart(observation.text),
        }, "|")
    end
    return nil
end

--- Build or return the runtime-only observation lookup without changing the exported JSON payload.
---@param observedActor MCP.MemoryObservedActor
---@return table<string, MCP.AnyMap>
local function EnsureObservationIndex(observedActor)
    if observedActor.dialogue_observation_index then
        return observedActor.dialogue_observation_index
    end

    local index = {}
    local dialogueData = observedActor.dialogue_data
    for _, observation in ipairs((dialogueData and dialogueData.observations) or {}) do
        local key = ObservationKey(observation)
        if key and not index[key] then
            index[key] = observation
        end
    end
    observedActor.dialogue_observation_index = index
    return index
end

--- Return an existing observation when the new observation repeats the same captured fact.
---@param observedActor MCP.MemoryObservedActor
---@param observation MCP.AnyMap
---@return MCP.AnyMap?
local function FindDuplicateObservation(observedActor, observation)
    local key = ObservationKey(observation)
    if not key then
        return nil
    end
    return EnsureObservationIndex(observedActor)[key]
end

--- Add a new unique observation to the runtime-only duplicate lookup.
---@param observedActor MCP.MemoryObservedActor
---@param observation MCP.AnyMap
local function RegisterObservation(observedActor, observation)
    local key = ObservationKey(observation)
    if key then
        EnsureObservationIndex(observedActor)[key] = observation
    end
end

--- Build a link to the actor-local dialogue notes document.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.MemoryLink?
function this.Link(observedActor)
    if not observedActor.dialogue_descriptor then
        return nil
    end
    return document.Link(
        document.linkRel.dialogue,
        observedActor.dialogue_descriptor.uri,
        string.format("%s Dialogue Memory", observedActor.title),
        string.format("Conversation notes observed with %s.", observedActor.title)
    )
end

--- Build actor-local child links for the actor document.
---@param observedActor MCP.MemoryObservedActor
---@return MCP.MemoryLink[]
function this.BuildLinks(observedActor)
    local links = jsonrpc.array()
    local dialogueLink = this.Link(observedActor)
    if dialogueLink then
        table.insert(links, dialogueLink)
    end
    return links
end

--- Ensure the actor has an owned dialogue child resource and return its mutable data.
---@param module MCP.Resources.Memory.Actor
---@param observedActor MCP.MemoryObservedActor
---@return MCP.AnyMap
function this.EnsureEntry(module, observedActor)
    if observedActor.dialogue_data then
        return observedActor.dialogue_data
    end

    local descriptor = document.Descriptor(
        string.format("memory/actors/%s/dialogue.json", observedActor.id),
        string.format("%s Dialogue Memory", observedActor.title),
        string.format("Conversation notes observed with %s.", observedActor.title)
    )
    local entry = document.LiveEntry(descriptor, function()
        return this.BuildDocument(module, observedActor.id)
    end)
    entry.debugHandler = function(desc)
        local memoryDocument = this.BuildDocument(module, observedActor.id)
        return { jsonrpc.TextResourceContents(desc.uri, json.encode(memoryDocument, { indent = true }), desc.mimeType) }
    end

    observedActor.dialogue_descriptor = descriptor
    observedActor.dialogue_entry = entry
    observedActor.dialogue_observation_index = {}
    observedActor.dialogue_data = jsonrpc.object({
        actor_id = observedActor.id,
        base_id = observedActor.data.base_id,
        reference_id = observedActor.data.reference_id,
        topics = jsonrpc.array(),
        response_count = 0,
        text_count = 0,
        observations = jsonrpc.array(),
    })
    table.insert(module.entries, entry)

    if module.published then
        module.resource:PublishResource(entry)
    end
    document.MarkDirty(observedActor.entry)
    return observedActor.dialogue_data
end

--- Append one dialogue observation to an actor-local dialogue document.
---@param module MCP.Resources.Memory.Actor
---@param observedActor MCP.MemoryObservedActor
---@param eventName string
---@param eventData infoResponseEventData|postInfoResponseEventData|infoGetTextEventData
---@return boolean
function this.AddObservation(module, observedActor, eventName, eventData)
    local dialogueData = this.EnsureEntry(module, observedActor)
    local observation
    if eventName == "info_get_text" then
        observation = TextObservation(observedActor, eventName, eventData --[[@as infoGetTextEventData]])
        local duplicateObservation = FindDuplicateObservation(observedActor, observation)
        if duplicateObservation then
            duplicateObservation.repeat_count = (duplicateObservation.repeat_count or 1) + 1
            duplicateObservation.last_observed_at = observation.observed_at
            document.MarkDirty(observedActor.entry)
            document.MarkDirty(observedActor.dialogue_entry)
            return false
        end
        dialogueData.text_count = (dialogueData.text_count or 0) + 1
    else
        observation = ResponseObservation(observedActor, eventName, eventData --[[@as infoResponseEventData|postInfoResponseEventData]])
        local duplicateObservation = FindDuplicateObservation(observedActor, observation)
        if duplicateObservation then
            duplicateObservation.repeat_count = (duplicateObservation.repeat_count or 1) + 1
            duplicateObservation.last_observed_at = observation.observed_at
            document.MarkDirty(observedActor.entry)
            document.MarkDirty(observedActor.dialogue_entry)
            return false
        end
        dialogueData.response_count = (dialogueData.response_count or 0) + 1
    end
    table.insert(dialogueData.observations, observation)
    RegisterObservation(observedActor, observation)
    AddTopic(dialogueData, observation.dialogue_id)
    AddTopics(dialogueData, observation.linked_topics)
    document.MarkDirty(observedActor.entry)
    document.MarkDirty(observedActor.dialogue_entry)
    return true
end

--- Build one actor-local dialogue Memory document.
---@param module MCP.Resources.Memory.Actor
---@param actorId string
---@return MCP.MemoryDocument?
function this.BuildDocument(module, actorId)
    local observedActor = module.observedActors[actorId]
    if not observedActor or not observedActor.dialogue_data then
        return nil
    end
    return document.Document(
        document.documentType.observation,
        document.dataType.actorDialogueNotes,
        string.format("%s Dialogue Memory", observedActor.title),
        observedActor.dialogue_data,
        {
            subject = observedActor.subject,
            scope = module.manager:GetScope(),
            source = document.Source(document.sourceKind.event, nil, "infoResponse/infoGetText", "Dialogue events observed for this actor."),
        }
    )
end

return this
