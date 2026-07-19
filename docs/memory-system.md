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
- `created_at` and `updated_at`: timestamps.
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
- `journal_entries`: journal Memory document payload.
- `quest_entries`: quest Memory document payload.
- `actor_index`: observed actor collection index payload.
- `npc_summary`: observed NPC Memory document payload.
- `creature_summary`: observed creature Memory document payload.

Link relation values currently used:

- `self`: canonical link to the current document.
- `player`: player Memory document.
- `journal`: journal Memory document.
- `quests`: quest Memory document or collection.
- `actors`: actor collection index.
- `actor`: one observed actor document.

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
- `reference`: serialized TES3 reference snapshot.

Actor `data_type` values:

- NPC actors use `npc_summary`.
- Creature actors use `creature_summary`.

Actor link descriptions should include enough identity fields to decide which actor link to follow without first reading every child document. Include at least `data_type`, `base_id`, `reference_id`, and `identity_kind`.

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
