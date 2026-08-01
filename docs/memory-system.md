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

- `live`: rebuild only when the owning module marks the entry dirty.
- `snapshot`: fixed content for the lifetime of the entry.

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
- `actor_dialogue_notes`: actor-local conversation notes observed from dialogue events.

Link relation values currently used:

- `self`: canonical link to the current document.
- `player`: player Memory document.
- `inventory`: player inventory Memory collection.
- `journal`: journal Memory document.
- `quests`: quest Memory document or collection.
- `actors`: actor collection index.
- `actor`: one observed actor document.
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

Loaded behavior:

- The Memory manager loaded handler should run early enough to update scope before module loaded callbacks run.
- The current implementation uses loaded event priority `100` for the manager.
- Base module loaded handling must not assume every module should publish on load. Dynamic modules can opt in or manage refreshes themselves.

## Player Inventory Memory

Player inventory is published at `morrowind://memory/player/inventory.json` as a child link of `morrowind://memory/player/index.json`. It is a `memory.collection` document with `data_type` `inventory_items` and the conceptual Player subject.

The payload contains `available`, `is_current`, aggregated numeric `gold`, `item_count`, and `items`. Gold is excluded from `items` so barter value deltas update one scalar balance. Each remaining item contains only `item.id`, `item.name`, optional mutable `itemData` fields (`charge`, `condition`, `timeLeft`, `scriptId`, `soulId`), and `count`; static object definitions and arbitrary mod data are not copied. Runtime snapshots retain these minimal tables, raw item ids, and serialized item-data fingerprints instead of MWSE userdata, so stale item-data handles cannot outlive an inventory mutation. The id and fingerprint index keeps custom and ordinary stacks separate for barter deltas.

Inventory Memory takes a full snapshot on `loaded`. It refreshes again when `MenuInventory` is visible after `uiActivated` or `menuEnter`, and after an observed visible-to-invisible transition at `menuExit`. The module registers `MenuInventory` once with `tes3ui.registerID` and uses the numeric ID for lookup and event comparison.

Successful `barterOffer` events apply `buying`, `selling`, and `value` gold deltas to the current snapshot. Gold transfers update the aggregated `gold` value directly. If a selling stack cannot be reconciled or a gold delta would make the balance negative, `is_current` becomes false rather than inventing item state; the next full refresh restores it. Failed barter offers make no change.

`containerClosed` and `itemTileUpdated` are intentionally not registered. Runtime logs show `containerClosed` arriving for batches of unrelated containers, while `itemTileUpdated` repeats the entire tile population for both `MenuInventory` and `MenuBarter`. Equipment changes, enchanting-charge use, and potion brewing are not inventory-memory triggers in the current phase.

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
