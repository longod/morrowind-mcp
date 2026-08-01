# Memory System Specification

This file records the Memory system decisions made during development. It is intended to be referenced from instruction files and updated whenever the Memory architecture or schema changes.

## Purpose

Memory is a higher-level layer over MCP resources. It exposes structured, navigable game-state documents that describe in-game concepts such as the player, journal, quests, and observed actors.

Memory is not persistent storage yet. Current persistence-like behavior is limited to debug JSON dumps for inspection and tests.

## Resource Boundary

- Memory resources use the normal MCP resource URI scheme, currently `morrowind://`.
- The root Memory index is `morrowind://memory/index.json`.
- Runtime Memory resources are published through `ResourceManager:PublishResource`.
- Debug dumps must be written outside `settings.resourceRootDir` so `resources/list` does not expose saved debug files as live resources.
- Debug dump files are server-generated Lua output data and are written under `settings.modDataDir`, which resolves physically to `<paths.datafilesOverwriteDir>/MWSE/mods/morrowind-mcp`.

## Document Envelope

Every Memory document uses a common JSON envelope built by `resources.memory.document`.

Required or common fields:

- `schema_version`: integer Memory schema version.
- `type`: broad document role.
- `data_type`: domain-specific payload shape.
- `title`: human-readable title.
- `subject`: stable in-game object or concept when the document describes one subject.
- `scope`: loaded-game boundary for the document.
- `source`: provenance category for the data.
- `links`: canonical traversal links to related Memory documents.
- `created_at` and `updated_at`: timestamps. `updated_at.system_time` is UTC wall-clock time; `updated_at.in_game_time` should be included when a loaded game exposes the current Tamriel time.
- `data`: payload for the selected `data_type`.

Document type values:

- `memory.index`: traversal index.
- `memory.entity`: one in-game object or conceptual entity.
- `memory.collection`: collection of related Memory documents.
- `memory.observation`: observation or event-like document.

Read policy values:

- `live`: mark the entry dirty when its source may have changed, then rebuild and serialize it on the next read. Later reads reuse that JSON until the entry is marked dirty again.
- `snapshot`: build and serialize the document immediately at an explicit capture point. Reads return that fixed JSON until the owning module explicitly captures another document.

Current read policies:

- Root, player, journal, quest, inventory, equipment, and actor collection indexes are `live` entries.
- Actor entity, actor-local dialogue, actor inventory, actor barter inventory, and unattributed dialogue documents are `snapshot` entries.
- Snapshot capture timing belongs to the feature module. The generic document helper only stores a completed `MCP.MemoryDocument`; it does not know actor ids, observation events, or feature-specific update boundaries.

## Player Memory

Player identity is published at `morrowind://memory/player/index.json`. It contains availability and character-generation readiness plus finalized `name`, `race`, `gender`, a structured `class`, and `birthsign`. The class contains its name, specialization, governing attributes, and major/minor skills so user-defined classes remain intelligible. While character generation is incomplete, identity fields are omitted and `ready` is false. The index links to `morrowind://memory/player/progression.json` and `morrowind://memory/player/vitals.json`.

Progression is a live `player_progression` document containing level, the eight named attributes, and the 27 named skills. Each statistic uses the shared `base`, `current`, `normalized` representation; skills additionally expose their class-assigned `type`.

Vitals are a live `player_vitals` document containing `alive`, health, magicka, and fatigue. `damaged`, `damagedHandToHand`, and `death` immediately invalidate player vitals. `levelUp` and `skillRaised` immediately invalidate progression. `charGenFinished` invalidates all Player Memory entries.

The `simulated` event is a player-only fallback for changes without a complete event source, including mod, potion, and magic effects. It compares values only while the relevant live entry is clean. Progression invalidates for any observed value change. Vitals invalidate when `base` changes, when zero or full state changes, or when the published normalized value differs by at least 0.05. The comparison baseline is the last resource build, so repeated small changes accumulate instead of causing one invalidation per tick. Magic-specific events are intentionally not registered yet; they may later request the same re-evaluation paths without changing the resource contract.

Scope kind values:

- `current_loaded_game`: current loaded game or save context.

Source kind values:

- `event`: captured from an event.
- `resource`: derived from another resource.
- `file`: read from a file.
- `live_state`: read from current game state.

Data type values currently used:

- `memory_roots`: root Memory index payload.
- `player_summary`: player Memory document payload.
- `inventory_items`: current player inventory snapshot payload.
- `journal_entries`: journal Memory document payload.
- `quest_entries`: quest Memory document payload.
- `actor_index`: observed actor collection index payload.
- `npc_summary`: observed NPC Memory document payload.
- `creature_summary`: observed creature Memory document payload.
- `actor_inventory_items`: actual inventory observed directly from one actor.
- `actor_barter_items`: merchant inventory filtered by its item-record trade eligibility.
- `actor_dialogue_notes`: actor-local conversation notes observed from dialogue events.

Link relation values currently used:

- `self`: canonical link to the current document.
- `player`: player Memory document.
- `inventory`: player inventory Memory collection.
- `journal`: journal Memory document.
- `quests`: quest Memory document or collection.
- `actors`: actor collection index.
- `actor`: one observed actor document.
- `barter`: one observed actor merchant barter-inventory snapshot.
- `dialogue`: actor-local dialogue notes.

Index documents should avoid duplicating links inside `data`. The canonical traversal list is `links`; `data` may contain counts or summary metadata such as `root_count` or `actor_count`.

## Subject Identity

Subject identity should come from the in-game object's base identity whenever possible.

- Use `document.SubjectTypeFromObject(object)` at call sites.
- If the object is a `tes3reference`, `SubjectTypeFromObject` must internally resolve through `SubjectTypeFromReference` and use the reference base object.
- Do not use `tes3reference` itself as the subject type for actor or item documents.
- Runtime reference details belong in `data`, not in `subject.type`.
- Built-in conceptual subjects use stable ids from `document.subjectId`.

Raw TES3 ids must be preserved in data fields when they come from the game. Do not normalize `base_id` or `reference_id` because the game may treat casing or spacing as meaningful. Normalize only URI path segments.

## Module Architecture

Memory behavior is owned by modules. The manager coordinates modules but should not contain feature-specific resource definitions.

- Each Memory module inherits from the Memory module base class.
- Adding a new static Memory area should usually mean adding a new module file and registering it, not editing feature logic into the manager.
- The root index is owned by the root index module, not by player or another domain module.
- Player, journal, quest, and actor modules own only their own resources and events.
- A module that represents many in-game instances must manage dynamic entries internally. Do not add one module per actor or per instance to the manager module list.

Publish behavior:

- `publishOnRegister` means the module publishes when registered.
- `publishOnLoaded` means the module publishes after a loaded-game transition.
- `PublishAll` is not an appropriate name for behavior that only publishes opt-in modules.
- Calling `Publish` or `Unpublish` may mark only that module's entries dirty.

Dirty behavior:

- Visibility changes should dirty only indexes related to the changed module or parent URI.
- Avoid global invalidation when one module publishes or unpublishes.
- Do not make player, journal, quest, or actor entries dirty just because an unrelated module changed visibility.
- Dirty marking affects only `live` entries. A snapshot changes only through an explicit capture after its owning module finishes updating the captured state.

Loaded behavior:

- The Memory manager loaded handler should run early enough to update scope before module loaded callbacks run.
- The current implementation uses loaded event priority `100` for the manager.
- Base module loaded handling must not assume every module should publish on load. Dynamic modules can opt in or manage refreshes themselves.

## Player Inventory Memory

Player inventory is published at `morrowind://memory/player/inventory.json` as a child link of `morrowind://memory/player/index.json`. It is a `memory.collection` document with `data_type` `inventory_items` and the conceptual Player subject.

The payload contains aggregated numeric `gold`, `item_count`, and `items`. Gold is excluded from `items`. Each remaining item contains only serialized item fields and optional mutable `itemData` fields (`charge`, `condition`, `scriptId`, `soulId`); static object definitions and arbitrary mod data are not copied.

Inventory Memory is a `live` entry. `resources/read` enumerates and serializes the current player inventory only when the entry is dirty; later reads return the cached JSON. The normal loaded-game publication marks the entry dirty, so the first read after loading builds from the current player state. There is no retained inventory snapshot, stack binning, or barter delta reconciliation.

Mutation events only invalidate and republish the entry. Repeated events while the entry is already dirty do not republish or re-enumerate. Successful `barterOffer`, the player `activate` event, player `itemDropped`, potion brewing completion, pickpocket-window close, and player enchantment creation attempts invalidate the entry. `enchantChargeUse` requires a player cast and a matching item currently in player inventory. `lockPick` and `trapDisarm` require the player, a physical `lockpick` or `probe`, and matching player inventory item data, excluding magic methods. `repair` requires a successful player roll with both the repaired item and repair tool in player inventory.

`menuEnter` remains as an eventual-consistency fallback only when `MenuInventory` is visible. `uiActivated` and `menuExit` are not used because opening or closing a menu does not by itself change inventory state. `containerClosed` and `itemTileUpdated` are intentionally not registered: runtime logs show unrelated container batches and repeated UI tile population. `convertReferenceToItem` fires before transfer, while spell, equipment, leveled-item, and power-recharge events do not reliably change fields represented by this document.

These exclusions apply to the player's live Inventory Memory only. Actor inventory snapshots use different capture boundaries because their meaning is what the player has directly observed.

## Player Equipment Memory

Player equipment is published at `morrowind://memory/player/equipment.json` as a child link of `morrowind://memory/player/index.json`. It is a live `memory.collection` document with `data_type` `equipment_items` and the conceptual Player subject.

The payload contains `available`, `item_count`, and `items`. Each equipment stack contains the same serialized `item` and optional mutable `itemData` fields as Player Inventory Memory. Ammunition uses `tes3.mobilePlayer.readiedAmmoCount`; all other equipped stacks have `count` 1. Spell selection and selected enchantments are not part of this document.

Successful player `equipped` and `unequipped` events invalidate and republish the entry. Events from other actors are ignored. This is intentionally event-driven: `tes3.equip` normally raises equip-related events, but calls that use `bypassEquipEvents = true` and `tes3mobileActor:equip()` may leave an already-read cache stale. Condition, charge, and other mutable item data can also change while an item remains equipped and are not immediately tracked in this initial implementation.

If a future equipment field requires eventual consistency outside those events, add a `simulated` fallback that compares a clean entry's primitive tuple for every published field. Extend that tuple whenever the resource adds a field backed by mutable runtime state; do not compare serialized JSON or use a hash.

## Actor Memory

Actor Memory is the first dynamic Memory module. It owns an actor collection index and the currently observed actor documents.

Observed actors:

- Include NPC references and creature references.
- Exclude `leveledCreature` as a standalone Memory subject.
- `tes3npcInstance` and `tes3creatureInstance` are valid actor observations when reachable through references.
- Whether an actor object is an instance is detected by the presence of `isInstance`.
- Dynamic actor entries are owned internally by the actor module.
- The loaded-game refresh intentionally rebuilds actor entries from active cells because broad dumps are useful during debugging.
- `activationTargetChanged.current` is an additional observation source and may add one actor without clearing actors found by the loaded-game active-cell refresh.
- Player `activate` events are an additional interaction source for actor targets. They update the existing actor entry when the actor is already observed, or add one actor when the activated target was not observed yet.

Actor ids:

- `base_id`: raw TES3 id from the actor base object.
- `reference_id`: raw TES3 id from the concrete reference or runtime instance.
- Resource URI path segments use a safe normalized segment derived from those ids.
- Do not add excessive identity metadata to the URI path.

Actor document data includes:

- `id`: Memory-local actor id used in the URI.
- `base_id`: raw TES3 base id.
- `reference_id`: raw TES3 reference or instance id.
- `identity_kind`: `unique`, `generic`, or `unknown`.
- `is_instance`: whether the observed actor object is an MWSE instance object.
- `facts`: lightweight blackboard facts currently known about the actor.
- `interaction`: mechanical player interaction state, counters, and observation sources.

Actor `facts` should be lightweight and human-oriented. They may include:

- `name`, `subject_type`, and `data_type`.
- `alive`, `is_empty`, `is_respawn`, and `is_leveled_spawn`.
- `location`, `position`, and `facing`.
- Compact actor object facts such as `actor_id`, `race`, `class`, `level`, `disposition`, `health`, `is_guard`, and `is_essential`.
- `services` when dialogue has exposed an NPC service actor and its class provides service fields.

Actor `interaction` includes:

- `state`: strongest mechanical player interaction observed for this actor. Current values are `heard`, `observed`, `targeted`, `activated`, `combat`, and `conversed`.
- `source_kinds`: mechanical sources that observed or updated this actor. Current values are `active_cells`, `activation_target_changed`, `activate`, `combat_started`, `voiceover_sound`, `menu_dialog`, `info_response`, and `info_get_text`.
- `heard`, `observed`, `targeted`, `activated`, `combat`, and `conversed`: booleans for observed interaction categories.
- `activation_count`: number of player `activate` events observed for this actor.
- `combat_count`: number of `combatStarted` events observed between the player and this actor.
- `player_started_combat_count`: number of player-initiated `combatStarted` events observed against this actor.
- `actor_started_combat_count`: number of actor-initiated `combatStarted` events observed against the player.
- `conversation_count`: number of newly created `MenuDialog` events observed for this actor.

Actor `senses` stores weak sensory evidence when the actor source is known. The initial sound-backed case is `addSound`/`addTempSound` with `isVoiceover == true` and an actor `reference`. This writes `heard`, `heard_voiceover`, `voiceover_count`, and a compact `last_voiceover` object. Sounds without a source actor, non-voiceover sounds, and ambiguous environmental sounds should not be attached to Actor Memory. `infoGetText` can also expose subtitle text for `tes3.dialogueType.voice`; when actor resolution is directly available, those events should update `heard_dialogue_subtitle`, `dialogue_subtitle_count`, optional per-kind counts, and `last_dialogue_subtitle`. Actor-unresolved voice subtitles are intentionally not attached to Actor Memory because nearby actors can speak unsolicited voice lines. `tes3.dialogueType.greeting` text is kept in actor dialogue notes when actor-resolvable, but it is not duplicated into `senses` because greeting lines already represent ordinary dialogue content. This subtitle record is sensory evidence only and should not imply a direct relationship to a sound event.

Actor-unresolved voice subtitles are stored separately at `morrowind://memory/unattributed/dialogue.json`. This document records `infoGetText` events for `tes3.dialogueType.voice` only when neither `tes3ui.getServiceActor()` nor `info.actor` exposes a direct actor source. The payload uses the same compact dialogue observation style as actor dialogue notes: lower-case linked `topics`, unique `text_count`, ordered `observations`, compact observation timestamps, and runtime-only duplicate aggregation by `event + info_id`. `tes3.dialogueType.greeting` is not stored here because greetings are ordinary dialogue content when actor-resolvable, and actor-unresolved greetings are too ambiguous to keep by default. Actor-unresolved sound events are also ignored for now because sound identity alone has low memory value.

Actor `risk` stores danger-oriented evidence separately from social or sensory evidence. `combatStarted` sets `risk.present`, `risk.combat`, `risk_count`, `combat_risk_count`, and `last_risk`. More ambiguous risks such as projectiles near the player should only be attached to an actor when the source actor is known.

Normal actor Memory reads must not expose the full serialized TES3 reference by default. Actor documents should update the blackboard from each mechanical source:

- `active_cells`: active-cell refresh saw the actor.
- `activation_target_changed`: `activationTargetChanged` exposed the actor as the current activation target.
- `activate`: the player activated the actor.
- `combat_started`: `combatStarted` exposed combat between the player and the actor. Combat between non-player actors is ignored.
- `voiceover_sound`: `addSound` or `addTempSound` exposed an actor reference for a voiceover sound.
- `menu_dialog`: a newly created `MenuDialog` exposed the service actor through `tes3ui.getServiceActor()`.
- `info_response`: a dialogue response event exposed a concrete actor reference.
- `info_get_text`: a non-journal dialogue text retrieval exposed a service actor or matched exactly one observed actor by base id.

Dialogue-derived service facts are stored under `facts.services` only when the actor is observed from dialogue-related events and the actor object has a class. The shape is compact:

- `facts.services.offers`: true-only service booleans such as `bartering`, `training`, `spells`, `spellmaking`, `enchanting`, and `repairs`.
- `facts.services.barters`: true-only barter category booleans such as `ingredients`, `weapons`, `books`, `armor`, and related class barter fields.

Service facts should stay on the actor Memory document instead of being hidden only inside a dialogue child document. A client should be able to revisit a merchant, trainer, spellmaker, or similar service actor by reading the actor index and actor facts without first traversing conversation notes.

Dialogue and conversation notes should not be appended to `memory/actors/index.json`. The actor collection index remains a lightweight traversal list. Conversation details should live in a child resource owned by the actor module, initially shaped as one actor-local dialogue document such as `morrowind://memory/actors/{actor_id}/dialogue.json`. The actor document may link to that child when dialogue notes exist.

Actor dialogue notes are currently written from reference-bearing `infoResponse` events and actor-resolvable non-journal `infoGetText` events. `infoResponse` captures the selected info record, command text, and parsed `Choice` command options. `infoGetText` captures the displayed response text; if the event text is not overridden, the module loads the original info text through MWSE. The child payload should keep `actor_id`, raw actor ids, a deduplicated lower-case `topics` array, unique `response_count`, unique `text_count`, and an ordered `observations` array. `topics` contains topic-type dialogue ids and normalized `@topic#` links from text; greeting ids such as `Greeting 5` are not topics and must not be added. Topic membership should be maintained with a runtime-only case-insensitive lookup, not serialized into `dialogue.json`, so exported `topics` stays compact and client-friendly. Dialogue text should resolve known percent/caret define tokens, normalize topic markup such as `@food#` into readable text, and expose those markers separately as lower-case `linked_topics`; `raw_text` may be kept when normalization changed the original text. Exact repeated observations should update `repeat_count` and `last_observed_at` instead of appending another observation, because subtitles and repeated topic selections can fire the same dialogue fact more than once. Duplicate lookup should be maintained by `event + info_id` in runtime-only module state, not serialized into `dialogue.json`, so the exported `observations` array stays traversal- and read-order friendly. Observation timestamps use compact in-game time strings inside the child payload to keep repeated dialogue notes readable; document-level `updated_at` still uses the normal structured timestamp envelope.

Full serialized TES3 reference data stays out of Actor Memory. When raw active actor data is needed, clients should call `mw-reference-fetch`, which is the tool-level interface for full active-cell actor serialization. Current normal reads and debug dumps both use lightweight actor facts and interaction metadata only.

Actor `data_type` values:

- NPC actors use `npc_summary`.
- Creature actors use `creature_summary`.

Actor link descriptions should include enough identity and interaction fields to decide which actor link to follow without first reading every child document. Include at least `data_type`, `base_id`, `reference_id`, `identity_kind`, and `interaction_state`.

Actor document `source.description` should use gameplay-facing prose such as `Seen in the current area.`, `Heard this actor's voice.`, or `Entered combat with the player.` The stable machine-readable source identifiers stay in `interaction.source_kinds`.

Actor interaction states are mechanical facts, not importance judgments:

- `heard`: a weak sensory event identified the actor, currently actor voiceover sound.
- `observed`: the actor was seen in active cells.
- `targeted`: the actor was the player's current activation target.
- `activated`: the actor was activated by the player.
- `combat`: combat started between the player and the actor.
- `conversed`: dialogue events exposed the actor through `tes3ui.getServiceActor()`, `infoResponse`, or actor-resolvable `infoGetText`.

Interaction state only moves to stronger states: `heard < observed < targeted < activated < combat < conversed`.

Actor entity and dialogue entries are snapshots. Actor event handlers first copy relevant MWSE values into compact Lua data, finish any event-specific interaction, sense, risk, or dialogue updates, and then capture the completed document. Reading an actor snapshot does not rebuild it from mutable runtime data. The actor collection index remains live because it is derived from current publication and link visibility.

### Actor Inventory Snapshots

Actor inventory is exposed only after the player has directly opened an actor-backed inventory UI. It is not a live read and is not inferred for every actor in an active cell.

- `morrowind://memory/actors/{actor_id}/inventory.json` is an `actor_inventory_items` snapshot of the actor's actual `reference.object.inventory`.
- `morrowind://memory/actors/{actor_id}/barter.json` is an `actor_barter_items` snapshot for a merchant. It is separate from actual inventory because the barter view is an eligibility-filtered subset.
- Both documents use the same `gold`, `item_count`, and `items` stack payload shape as Player Inventory Memory, wrapped under `data.inventory` with actor identity fields.
- An actor document links its observed snapshots using `inventory` and `barter` relations. The child resources are created only after a successful capture.

Actual actor inventory capture occurs when `uiActivated` exposes a visible `MenuContents` and its `MenuContents_ObjectRefr` property resolves to an NPC or creature reference. Ordinary containers remain outside Actor Memory. `containerClosed.reference` recaptures the same actor after looting or companion inventory changes; the pickpocket close event (`item == nil`) recaptures the pickpocket target after transfers complete.

Merchant barter capture occurs after visible `MenuBarter` activation using `tes3ui.getServiceActor().reference`. Every stack whose base item passes `tes3.checkMerchantTradesItem({ reference = merchantReference, item = item })` is included. The public API does not accept `itemData`, so Memory does not apply additional stack-level exclusions for equipped state, initial clothing, ownership, charge, condition, or other mutable state. A successful `barterOffer` refreshes both merchant snapshots. `menuExit` is intentionally not used because it does not identify the actor whose inventory changed.

During development, `filterBarterMenu` may be registered only as a diagnostic comparison against the API-derived merchant snapshot. Remove it after real-game validation confirms equivalence; retain it as an authoritative source only if that validation demonstrates a persistent mismatch.

## Actor Identity Classification

Actor identity is a classification, not a persistence guarantee.

Values:

- `unique`: the observed actor is treated as a unique individual.
- `generic`: the observed actor is treated as a replaceable spawned or generic actor.
- `unknown`: the current evidence is not enough to classify the actor as unique or generic.

NPC rules:

- Named non-respawning NPCs are treated as `unique`.
- Respawning NPCs are treated as `generic`.
- Guards and similar generic NPCs usually become `generic` through respawn signals.
- The NPC with base id `din` is a known exception and is treated as `unique`.

Creature rules:

- Respawning creatures are `generic`.
- Creatures spawned from leveled creature lists are `generic`.
- Non-respawning, non-leveled creatures are `unknown` unless stronger evidence is added later.

Potential future uniqueness signals include dialogue, quest involvement, player contact, custom record metadata, and meaningful `soundCreature` differences. These signals are not currently implemented and should not be implied in output.

## Debug Dumping

Memory manager debug dumping saves the current live Memory documents to JSON files.

- Save each current resource URI at most once per dump operation.
- Preserve the same document envelope used by live resources.
- For snapshot entries, save the same cached JSON returned by normal resource reads; debug dumping must not rebuild a newer document from mutable runtime state.
- Keep debug output outside the normal resource root.
- Debug dumps are for inspection and tests, not long-term persistence.

## Testing Expectations

Use focused UnitWind coverage when changing Memory document helpers, module behavior, manager behavior, actor identity, or debug dumping.

Useful existing tests:

- `MWSE/mods/morrowind-mcp/tests/test_memory_document.lua`
- `MWSE/mods/morrowind-mcp/tests/test_memory_module.lua`

Run `./tests/unit_test.ps1` after Lua Memory changes. Run `./tests/server_test.ps1` when behavior affects MCP resource publication, resource reads, server integration, or debug output visible through server flows.

## Update Policy

When Memory behavior changes, update this file together with the code and tests. In particular, update it when adding a new Memory module, document `data_type`, link relation, actor identity signal, debug dump behavior, or lifecycle rule.
