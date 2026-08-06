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
---@field tes3_type string TES3 type name such as tes3npc or a type derived from tes3.objectType.
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

--- Compact timestamp metadata used by repeated Memory observations.
---@class MCP.MemoryObservationTimestamp
---@field system_time string? UTC ISO 8601 time.
---@field in_game_time_text string? Compact Tamriel time text.

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

--- Per-resource cache for either lazy live documents or eagerly serialized snapshots.
---@class MCP.MemoryCacheState
---@field read_policy MCP.MemoryReadPolicy
---@field dirty boolean Live entries rebuild on the next read when true; snapshot entries remain false.
---@field scope_generation integer?
---@field source_version string|number?
---@field cached_document MCP.MemoryDocument?
---@field cached_json string?
---@field built_at MCP.MemoryTimestamp?

--- Compact serialized facts for a TES3 cell used by player location Memory.
---@class MCP.MemoryCell
---@field id string Raw TES3 cell id. Exterior cells can share an ID across grid positions.
---@field display_name string? Gameplay-facing cell name.
---@field is_interior boolean
---@field grid_x number? Exterior cell X coordinate.
---@field grid_y number? Exterior cell Y coordinate.
---@field region MCP.AnyMap? Exterior or exterior-behaving cell region identity.
---@field resting_is_illegal boolean

--- One current-loaded-game cell observation.
---@class MCP.MemoryVisitedCell: MCP.MemoryCell
---@field first_observed_at MCP.MemoryObservationTimestamp? Time when tracking first saw this cell.
---@field last_observed_at MCP.MemoryObservationTimestamp? Time when tracking last saw this cell.
---@field entry_count integer Number of tracked cell-change entries after initial load.

--- Runtime state for one observed actor managed inside the Actor Memory module.
---@class MCP.MemoryObservedActor
---@field id string Stable memory id for the observed actor entry.
---@field title string Display label for the actor.
---@field descriptor MCP.Resource Resource descriptor for the actor memory entry.
---@field entry MCP.MemoryResourceEntry? Snapshot entry assigned before the observed actor is published.
---@field subject MCP.MemorySubject Subject identity for the actor.
---@field source_description string Source text describing how this actor was observed.
---@field data_type MCP.MemoryDataType Data type selected from the actor's TES3 object type.
---@field data MCP.AnyMap Serialized actor/reference data captured when the module refreshed.
---@field dialogue_descriptor MCP.Resource? Resource descriptor for actor-local dialogue notes.
---@field dialogue_entry MCP.MemoryResourceEntry? Snapshot resource entry for actor-local dialogue notes.
---@field dialogue_data MCP.AnyMap? Mutable actor-local dialogue notes payload.
---@field dialogue_topic_index table<string, boolean>? Runtime-only case-insensitive lookup for actor-local dialogue topics.
---@field dialogue_observation_index table<string, MCP.AnyMap>? Runtime-only duplicate lookup for actor-local dialogue observations.
---@field inventory_descriptor MCP.Resource? Resource descriptor for actor actual-inventory memory.
---@field inventory_entry MCP.MemoryResourceEntry? Snapshot resource entry for actor actual-inventory memory.
---@field inventory_data MCP.AnyMap? Captured actor actual-inventory payload.
---@field inventory_source MCP.MemorySource? Provenance for the captured actual inventory.
---@field barter_descriptor MCP.Resource? Resource descriptor for actor barter-inventory memory.
---@field barter_entry MCP.MemoryResourceEntry? Snapshot resource entry for actor barter-inventory memory.
---@field barter_data MCP.AnyMap? Captured merchant trade-eligible inventory payload.
---@field barter_source MCP.MemorySource? Provenance for the captured barter inventory.

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

--- One player inventory stack captured by Inventory Memory.
--- Item identity and mutable stack-state fields are captured during refresh, so the snapshot holds no MWSE userdata.
---@class MCP.MemoryInventoryStack
---@field itemId string Raw TES3 item id used only by the runtime index.
---@field itemDataKey string Serialized minimal item-data fingerprint used only by the runtime index.
---@field item MCP.AnyMap Serialized `{ id, name }` item identity.
---@field itemData MCP.AnyMap? Serialized mutable stack state: charge, condition, timeLeft, scriptId, soulId.
---@field count integer
---@field snapshotIndex integer Runtime-only position in the collection array for constant-time removal.

--- Runtime-only lookup index for player inventory stacks.
--- The first key is the raw item id; the second is a serialized item-data fingerprint.
---@class MCP.MemoryInventoryStackIndex

--- Payload written by the player Inventory Memory document.
---@class MCP.MemoryInventoryData
---@field available boolean Whether player inventory could be captured from the current loaded game.
---@field is_current boolean Whether all known mutations have been applied to the captured snapshot.
---@field gold integer Aggregated player gold, kept separate from item stacks.
---@field item_count integer Number of distinct serialized inventory stacks.
---@field items MCP.AnyMap[] Serialized player inventory stacks.

--- Stable identity and readiness payload written by the Player Memory index.
---@class MCP.MemoryPlayerSummaryData
---@field available boolean Whether a player mobile is available outside the main menu.
---@field ready boolean Whether character generation has finished and identity fields are final.
---@field character_generation MCP.AnyMap Current character generation lifecycle state.
---@field name string? Player name after character generation finishes.
---@field race string? Player race name after character generation finishes.
---@field gender string? Player gender after character generation finishes.
---@field class string? Player class name after character generation finishes.
---@field birthsign string? Player birthsign name after character generation finishes.

--- Progression payload written by Player Memory.
---@class MCP.MemoryPlayerProgressionData
---@field available boolean Whether progression values can be read from the current player mobile.
---@field level integer? Current player level.
---@field attributes MCP.AnyMap Attribute statistics keyed by display name.
---@field skills MCP.AnyMap Skill statistics keyed by display name.

--- Vital state payload written by Player Memory.
---@class MCP.MemoryPlayerVitalsData
---@field available boolean Whether vital values can be read from the current player mobile.
---@field alive boolean? Whether the player reference is alive.
---@field health MCP.AnyMap? Current health statistic.
---@field magicka MCP.AnyMap? Current magicka statistic.
---@field fatigue MCP.AnyMap? Current fatigue statistic.

--- One spell definition listed by Player Spellbook Memory.
--- This shape deliberately supports every TES3 spell cast type so actor Memory can reuse it later.
---@class MCP.MemorySpell
---@field id string Raw TES3 spell id.
---@field name string Spell display name.
---@field castType string Spell cast type name.
---@field magickaCost number Static spell definition cost, not a runtime consumption prediction.
---@field effects MCP.AnyMap[] Serialized spell effects.

--- One power entry listed by Player Spellbook Memory.
---@class MCP.MemoryPower: MCP.MemorySpell
---@field used boolean Whether the player has used this power during its current recharge period.
---@field available boolean Whether the power is currently available for casting.

--- Payload written by Player Spellbook Memory.
---@class MCP.MemoryPlayerSpellbookData
---@field available boolean Whether the current player spell list can be read.
---@field spell_count integer Number of normal spells known by the player.
---@field power_count integer Number of powers available to the player.
---@field spells MCP.MemorySpell[] Current normal spells.
---@field powers MCP.MemoryPower[] Current powers and their recharge state.

--- Runtime payload for dialogue text that is intentionally not assigned to an actor.
---@class MCP.MemoryUnattributedDialogueData
---@field topics string[] Lower-case topics linked from unattributed text.
---@field text_count integer Unique text observations in this loaded-game scope.
---@field observations MCP.AnyMap[] Ordered unattributed dialogue observations.

--- Runtime payload for transient notification text without a stable domain subject.
---@class MCP.MemoryNotificationData
---@field notification_count integer Unique notification observations in this loaded-game scope.
---@field observations MCP.AnyMap[] Ordered notification observations.

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
