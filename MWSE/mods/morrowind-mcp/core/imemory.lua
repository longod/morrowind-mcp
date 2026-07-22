--- Memory: this is a concept in a higher layer than MCP resources.
--- Information obtained during gameplay is handled as memory.
---
--- The agent also has its own memory, but its capacity is small compared to the amount of information gained in-game.
--- It is preferable not to retain temporarily unnecessary information until it is needed.
--- Also, loading save data can make the situation (that is, the information state) completely different,
--- but whether this is noticed depends on the agent.
---
--- This memory layer is intended to help the agent behave well by managing a medium-sized amount of information: more than the agent's own memory,
--- but less than the total information in the entire game, while accounting for game-specific volume and change.
--- Memories have relational links. Details such as what kind of person an NPC was, what they talked about,
--- and what items they had are stored in separate resources and connected at an appropriate granularity.
--- This allows necessary information to be followed without making any single resource excessively large.
---
--- Architecture overview:
--- Memory is exposed as virtual MCP resources, but the Memory layer is not the same as the low-level resource manager.
--- Each Memory module owns a feature-level area such as the root index, player, journal, quests, or actor collection.
--- A module may publish one resource or many dynamic resources internally; the manager only coordinates modules.
--- Links are grouped by parent resource URI so indexes can discover their direct children without assuming singleton modules.
--- Scope generation changes on loaded-game transitions so clients can recognize documents from an older save context.
--- Actor memory separates raw TES3 identity from route-friendly URI segments. It also uses an explicit identity kind
--- instead of a boolean unique flag because creatures can be generic, unique, or not yet knowable from active-cell data.

--- Stable identity for the in-game object or concept described by a Memory document.
---@class MCP.MemorySubject
---@field tes3_type string TES3 type name such as tes3mobilePlayer or a type derived from tes3.objectType.
---@field id string|number Stable subject id within the current subject type.
---@field title string? Display label for the subject.
---@field base MCP.MemorySubject? Base object identity when the subject is a runtime instance.

--- Loaded-game boundary used to distinguish stale Memory documents across saves and new games.
---@class MCP.MemoryScope
---@field kind MCP.MemoryScopeKind
---@field generation integer Current loaded-game generation.
---@field save_name string? Save file or display name when available.
---@field player_name string? Player name when available.

--- Provenance metadata describing how a Memory document was observed or derived.
---@class MCP.MemorySource
---@field kind MCP.MemorySourceKind Source kind such as event, resource, file, or live_state.
---@field uri MCP.ResourceUri? Source resource URI when the memory is derived from another resource.
---@field event string? MWSE event name when the memory is derived from an event.
---@field description string? Human-readable source note.

--- Lightweight relationship from one Memory document to another resource.
---@class MCP.MemoryLink
---@field rel MCP.MemoryLinkRel Relationship name from this memory document to the linked resource.
---@field uri MCP.ResourceUri
---@field title string? Display label for the linked resource.
---@field description string? Human-readable link description.

--- Time metadata for Memory observation and document construction.
---@class MCP.MemoryTimestamp
---@field system_time string? UTC ISO 8601 time.
---@field in_game_time MCP.DateTimeInGame?

--- JSON envelope returned by Memory resources.
---@class MCP.MemoryDocument
---@field schema_version integer
---@field type MCP.MemoryDocumentType
---@field data_type MCP.MemoryDataType
---@field title string
---@field subject MCP.MemorySubject?
---@field scope MCP.MemoryScope?
---@field source MCP.MemorySource?
---@field links MCP.MemoryLink[]
---@field observed_at MCP.MemoryTimestamp?
---@field updated_at MCP.MemoryTimestamp?
---@field data table

--- Optional fields used when constructing a Memory document envelope.
---@class MCP.MemoryDocumentParams
---@field subject MCP.MemorySubject? Subject identity described by the memory document.
---@field scope MCP.MemoryScope? Loaded-game scope for the memory document.
---@field source MCP.MemorySource? Source used to build the memory document.
---@field links MCP.MemoryLink[]? Links from this memory document to related memory resources.
---@field observed_at MCP.MemoryTimestamp? Time when the underlying state was observed.
---@field updated_at MCP.MemoryTimestamp? Explicit document update timestamp.
---@field in_game_time MCP.DateTimeInGame? In-game time used when generating the default update timestamp.

--- Per-resource live cache used to avoid rebuilding JSON until a Memory module marks it dirty.
---@class MCP.MemoryCacheState
---@field read_policy MCP.MemoryReadPolicy
---@field dirty boolean
---@field scope_generation integer?
---@field source_version string|number?
---@field cached_document MCP.MemoryDocument?
---@field cached_json string?
---@field built_at MCP.MemoryTimestamp?

--- Runtime state for one observed actor managed inside the Actor Memory module.
---@class MCP.MemoryObservedActor
---@field id string Stable memory id for the observed actor entry.
---@field title string Display label for the actor.
---@field descriptor MCP.Resource Resource descriptor for the actor memory entry.
---@field entry MCP.MemoryResourceEntry Live resource entry for the actor memory document.
---@field subject MCP.MemorySubject Subject identity for the actor.
---@field source_description string Source text describing how this actor was observed.
---@field data_type MCP.MemoryDataType Data type selected from the actor's TES3 object type.
---@field data MCP.AnyMap Serialized actor/reference data captured when the module refreshed.
---@field dialogue_descriptor MCP.Resource? Resource descriptor for actor-local dialogue notes.
---@field dialogue_entry MCP.MemoryResourceEntry? Live resource entry for actor-local dialogue notes.
---@field dialogue_data MCP.AnyMap? Mutable actor-local dialogue notes payload.
---@field dialogue_observation_index table<string, MCP.AnyMap>? Runtime-only duplicate lookup for actor-local dialogue observations.

--- Payload fields currently written by Actor Memory documents.
--- Raw ids preserve TES3 casing and spacing; only the resource URI segment is normalized.
---@class MCP.MemoryObservedActorData
---@field id string Resource-local actor id used in the Memory URI.
---@field base_id string Raw TES3 base actor id.
---@field reference_id string Raw TES3 reference or runtime instance id.
---@field identity_kind MCP.MemoryActorIdentityKind Unique, generic, or unknown identity classification.
---@field is_instance boolean Whether the observed actor object is an MWSE instance object.
---@field facts MCP.AnyMap Lightweight blackboard facts currently known about the actor.
---@field interaction MCP.AnyMap Mechanical player interaction state, counters, and observation sources.

--- File written by a debug-only Memory dump operation.
---@class MCP.MemoryDebugSaveResult
---@field uri MCP.ResourceUri Source Memory resource URI.
---@field file_path string Filesystem path written outside resourceRootDir.
---@field bytes integer Number of JSON bytes written.

--- Base interface for Memory managers that publish Memory resources through the resource manager.
---@class MCP.Resources.IMemory
---@field resource MCP.IResourceManager
local this = {}

---@param params table?
---@return MCP.Resources.IMemory
function this.new(params)
    local instance = {}
    if params then
        table.copymissing(instance, params)
    end
    ---@type MCP.Resources.IMemory
    setmetatable(instance, { __index = this })
    return instance
end


return this
