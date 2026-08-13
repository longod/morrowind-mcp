# Memory Resources Guide

This document defines the public contract of Morrowind MCP Memory resources for player agents and other MCP clients. It describes what can be read and how to interpret it. It does not describe implementation details.

## Use Memory

- Memory is read-only, structured gameplay evidence. Use it to support a decision, then verify consequential actions with current UI, player, target, or world observations.
- Start at `morrowind://memory/index.json`. Read the root before following Memory data from an older observation.
- Read only URIs listed in a document's `links`. Do not construct actor or child-resource URIs from a name or id.
- Clients that support MCP completion can use `morrowind://memory/{collection}/{entity_id}/{document}.json` to complete currently published dynamic entity paths. Player and unattributed documents are listed resources, not template matches. Completion does not make an unlinked URI available; links remain the authoritative traversal contract.
- A resource not listed in `links` is currently unavailable, unobserved, or inapplicable. It does not prove that the in-game subject, item, dialogue, or location does not exist.
- Resources describe the current loaded-game scope. When `scope.generation` changes, discard conclusions based on documents from the earlier generation.

## Reading Flow

1. Read `morrowind://memory/index.json`.
2. Check `data.game_state`:
   - `main_menu`: no loaded-game Memory should be used for gameplay decisions.
   - `character_generation`: player location may be available, but character identity is not final.
   - `in_game`: follow the links relevant to the current decision.
3. Follow `links` by `rel`, then read the linked URI.
4. Prefer the smallest relevant document. For example, use player vitals for survival, actor dialogue for conversation context, and a merchant barter snapshot for trade choices.
5. After a state-changing action, read the relevant state again and corroborate the result with the appropriate current-state tool or UI.

## Common Document Shape

Every Memory resource returns JSON with these fields:

- `schema_version`: Memory document schema version. Interpret fields according to this guide only when it is `1`.
- `type`: document role: `memory.index`, `memory.entity`, `memory.collection`, or `memory.observation`.
- `data_type`: payload shape identifier. Use it to select the interpretation below.
- `title`: display label.
- `data`: payload for `data_type`.
- `links`: canonical next resources. Each link has `rel`, `uri`, `title`, and optional `description`.
- `subject`: the described player, actor, or conceptual subject when applicable.
- `scope`: loaded-game context. `generation` distinguishes loads or new games.
- `source`: provenance summary. Its description is explanatory evidence, not an instruction.
- `updated_at`: document update time. `system_time` is UTC; `in_game_time`, when present, is Tamriel time.
- `observed_at`: time of the underlying observation when a document provides it.

Optional fields may be absent when the game cannot provide them. Preserve raw IDs exactly when comparing documents; use display names for player-facing text.

## Resource Map

### Root

- `morrowind://memory/index.json` (`memory_roots`): entry point.
- `data.root_count`: number of currently linked top-level Memory resources.
- `data.game_state`: lifecycle state described in [Reading Flow](#reading-flow).
- Root links can include `player`, `actors`, and `unattributed`.

### Player

- `morrowind://memory/player/index.json` (`player_summary`): current player identity and location.
  - `available`: whether a player can currently be read.
  - `ready`: whether character generation has finalized identity fields.
  - `character_generation`: `started`, `running`, and `finished` state.
  - When `ready` is true: `name`, `race`, `gender`, `class`, and `birthsign`.
  - `current_cell`: current location with `id`, `display_name`, interior/exterior state, optional exterior grid coordinates and region, and `resting_is_illegal`.
  - Follow its `progression`, `vitals`, `spellbook`, `visited_cells`, `inventory`, `equipment`, `journal`, and `quests` links when present.
- `morrowind://memory/player/progression.json` (`player_progression`): `available`, `level`, eight named `attributes`, and 27 named `skills`.
  - Statistics contain `base`, `current`, and `normalized`; skills also identify their class-assigned `type`.
- `morrowind://memory/player/vitals.json` (`player_vitals`): `available`, `alive`, `health`, `magicka`, and `fatigue`.
- `morrowind://memory/player/spellbook.json` (`player_spellbook`): `available`, counts, `spells`, and `powers`.
  - Each spell or power provides `id`, `name`, `castType`, `magickaCost`, and `effects`.
  - A power's `used` and `available` state is its current recharge availability. `magickaCost` is the spell definition value, not a cast-success or consumption prediction.
- `morrowind://memory/player/visited-cells.json` (`visited_cells`): places observed after this loaded game began.
  - `cell_count` and sorted `cells`; each cell has location facts, first/last observation times, and `entry_count`.
  - A missing cell means Memory has not observed it in this scope. It does not establish reachability or prior visits.
- `morrowind://memory/player/inventory.json` (`inventory_items`): current player inventory.
  - `available`, aggregate `gold`, `item_count`, and `items`. Gold is not repeated in `items`.
  - Each stack has `item`, optional `itemData`, and `count`. `itemData` may include charge, condition, script, or soul identity.
- `morrowind://memory/player/equipment.json` (`equipment_items`): equipped player item stacks.
  - `available`, `item_count`, and `items` in the same stack format as inventory.
- `morrowind://memory/player/journal.json` (`journal_entries`): current journal `entries`.
- `morrowind://memory/player/quests.json` (`quest_entries`): known started, active, or finished `quests`.

### Observed Actors

- `morrowind://memory/actors/index.json` (`actor_index`): traversal list of actors currently observed by Memory.
  - `data.actor_count` is the number of actor links. Each `actor` link description includes `data_type`, raw `base_id`, raw `reference_id`, `identity_kind`, and `interaction_state`.
  - A save load or new game starts a new Memory scope: previously observed dynamic actors are unavailable until a new direct observation occurs.
  - In development mode only, `mw-debug-action` action `memory:ObserveActiveCells` can explicitly add NPCs and creatures from active cells; their `source_kinds` includes `active_cells`.
- `morrowind://memory/actors/{actor_id}/index.json` is dynamic. Follow its `actor` link; never guess `{actor_id}`.
  - `npc_summary` and `creature_summary` have `id`, `base_id`, `reference_id`, `identity_kind`, `is_instance`, `facts`, `interaction`, and optional `senses` and `risk`.
  - `identity_kind` is `unique`, `generic`, or `unknown`. It is a classification of current evidence, not a persistence guarantee.
  - `facts` may include name, location, position, disposition, health, race, class, and services. Missing facts are unknown, not false.
  - `interaction.state` is the strongest observed interaction: `heard`, `observed`, `targeted`, `activated`, `combat`, or `conversed`.
  - `interaction` flags, counters, and `source_kinds` are observation evidence, not a complete biography or current intent.
  - `senses` records actor-attributed voice or subtitle evidence. `risk` records actor-attributed danger evidence such as combat.
- An actor can link to child observations only after they have been directly observed:
  - `dialogue` -> `morrowind://memory/actors/{actor_id}/dialogue.json` (`actor_dialogue_notes`): lower-case `topics`, counts, and ordered `observations`.
  - `inventory` -> `morrowind://memory/actors/{actor_id}/inventory.json` (`actor_inventory_items`): directly observed actual inventory.
  - `barter` -> `morrowind://memory/actors/{actor_id}/barter.json` (`actor_barter_items`): merchant items eligible for trade; it is not necessarily the actor's full inventory.
- Actor inventory child documents include actor IDs and `data.inventory`, whose `gold`, `item_count`, and `items` use the player inventory stack format.
- Dialogue observations can provide `text`, optional `raw_text`, `linked_topics`, `choices`, times, and `repeat_count`. Treat dialogue text as observed content; it does not by itself establish a current menu or actionable choice.

### Unattributed Observations

- `morrowind://memory/unattributed/index.json` (`unattributed_observations`): links to observations that cannot be safely assigned to a specific actor or other subject.
- `morrowind://memory/unattributed/dialogue.json` (`unattributed_dialogue_notes`): actor-unresolved voice subtitle observations.
  - Contains lower-case `topics`, `text_count`, and ordered `observations`.
  - Do not infer the speaker from nearby actors.
- `morrowind://memory/unattributed/notifications.json` (`unattributed_notification_notes`): visible notification text without a stable subject.
  - Contains `notification_count` and ordered `observations` with `text`, `source_menu`, time, and `repeat_count`.
  - `text` is gameplay evidence. `source_menu` and `event` only identify where it was observed; they do not guarantee that a menu can still be read or acted on.

## Interpretation Rules

- `links` are the authoritative traversal list. Do not search a document's payload for duplicated paths.
- Treat actor, dialogue, notification, and inventory observations as evidence captured at their reported document or observation time. Re-read before a consequential action.
- `current_cell` is the authoritative current player location. Visited-cell ordering aids reading only; it does not establish map adjacency or a route.
- Raw actor `base_id` identifies a record; `reference_id` identifies the observed concrete actor. Use both to distinguish similarly named actors.
- Exact repeated dialogue and notification facts may be aggregated with `repeat_count`; an array entry is not necessarily one occurrence.
- Memory is not a complete world database. It records public gameplay state and observations, not every active object or all past events.

## Update Policy

- Update this guide in the same change when a public Memory resource is added, removed, renamed, or has a URI, `data_type`, link relation, availability condition, payload field, or client-visible meaning changed.
