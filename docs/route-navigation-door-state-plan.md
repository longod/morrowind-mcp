# Route Navigation and Door State Plan

## Purpose

This document records the original implementation plan for the two failures found during NEW GAME progression exploration:

- A route request to a destination in another cell failed once, after which the agent treated navigation as generally unavailable.
- A door was opened, then closed again, but the available reference data did not make the state or the appropriate next action clear.

The plan separates destination-specific walking limits from overall route capability. It also avoids treating an unlocked door as proof that it is currently passable.

## Goals

1. Return structured guidance when a requested destination cannot be reached by walking alone, including reachable travel-door candidates, without starting movement.
2. Provide a read-only route-discovery operation so clients can inspect travel options before choosing an action.
3. Normalize the door/reference fields that are reliable at runtime.
4. Investigate, rather than infer, whether MWSE exposes a reliable open/closed door state.
5. Rename the movement operation to make its route-planning role clear.

## Non-Goals

- Do not automatically activate doors or travel services.
- Do not infer door state from lock state, destination presence, or an absent action flag.
- Do not implement remote-cell walking or a terrain-navigation fallback.
- Do not change the pathfinding graph's normal travel-edge behavior outside the walk-only classification path.

## Phase 0: Probe Door Action Flags

Use the `door0000.ess` scenario to capture the target door before activation, after opening, and after closing. Compare each supported `testActionFlag` value.

Decision rule:

- If a flag changes consistently, expose its raw name in reference summaries and document its semantics as observed behavior.
- If no reliable transition is observed, do not expose a synthesized `open` or `closed` state. Record the limitation and retain only raw flags when present.

Acceptance check: a repeatable live capture establishes whether action flags can distinguish the observed door states.

## Phase 1: Normalize Door and Reference Summaries

Adjust `object_summary.lua` so consumers can distinguish lock information from destination information without assuming either is passability:

- Return `lockState` as `locked` or `unlocked` when applicable.
- Return `destinationCellId` for minimal door/reference summaries when a destination exists.
- Return raw door `actionFlags` only when supported flags are set.
- Remove ambiguous or redundant minimal fields such as `locked` and `hasDestination`.

Acceptance check: focused UnitWind tests cover locked and unlocked values, destination-cell output in normal and minimal summaries, and conditional raw action flags.

## Phase 2: Add Walk-Only Path Classification and Travel Discovery

Extend pathfinding with an explicit `walkOnly` option:

- A walk-only search may traverse only `edgeKind.walk` edges.
- Its heuristic must remain valid even when the graph also contains travel edges.
- The regular path search continues to allow travel edges.

Add a query that finds travel nodes reachable from the player through walk-only edges. Each candidate contains:

- Door reference ID and kind.
- Door position.
- One or more destination cell IDs and marker positions.
- Target relation metadata when available.
- Walking distance and route-node count.

Candidates are sorted by walking distance. They are recommendations only and never trigger activation.

Acceptance check: pathfinding UnitWind tests demonstrate that walk-only search excludes travel edges, normal search preserves travel-edge behavior, and travel nodes are returned in stable distance order with destination metadata.

## Phase 3: Return Structured Navigation Failure

Change navigator startup to classify the destination before issuing player input:

1. Run a walk-only search.
2. When it succeeds, build waypoints and start the route normally.
3. When it fails, run the normal graph search only to classify the failure.
4. Return a structured failure and reachable travel nodes without calling route-following input.

Failure reasons:

- `requires_travel_activation`: the full graph can reach the destination only by using travel edges.
- `no_path`: the full graph has no route to the requested destination.

Every non-start result explicitly reports `movement_started: false`.

Acceptance check: navigator UnitWind tests verify successful walking startup, both failure reasons, absence of movement on failure, and travel-node propagation.

## Phase 4: Wire Navigation Context Through the Server

Expose the walkability and reachable-travel-node queries through the HTTP server tool context. Preserve the navigator's success result and add a typed structured failure return without changing unrelated tool behavior.

Acceptance check: Lua annotations and static diagnostics recognize all return values; route tools receive the added context dependencies.

## Phase 5: Rename and Update the Navigation Tool

Rename `mw-player-navigate` to `mw-route-navigate` and rename its implementation module accordingly. The tool continues to start direct walking routes, but on failure returns:

- `reason`
- `movement_started: false`
- `travel_nodes`

The success response retains route and waypoint counts. Tool descriptions direct clients to route discovery before attempting an unreachable destination.

Acceptance check: tool catalog output contains `mw-route-navigate`, contains no `mw-player-navigate`, and focused tests cover both response shapes.

## Phase 6: Add Read-Only Route Discovery

Add `mw-route-fetch` as a read-only tool. It optionally accepts a complete destination locator; partial coordinate sets are rejected. It returns:

- `destination_walkable` when a destination is supplied.
- Reachable travel nodes with destination marker and target relation data.

The tool must preserve an explicit `false` value for `destination_walkable` rather than converting it to an absent field.

Acceptance check: tool tests validate complete-or-absent destination coordinates, the read-only annotation, false preservation, and travel-node response shape.

## Phase 7: Update Public Documentation

Update the feature inventory and navigation proposal documentation to describe:

- `mw-route-fetch` and `mw-route-navigate`.
- The distinction between walk-only reachability and travel candidates.
- The policy that travel nodes are suggestions, not automatic activations.
- The result of the door action-flag probe and the limits of lock and destination data.

Acceptance check: public feature documentation uses the new tool name and has no remaining references to `mw-player-navigate`.

## Phase 8: Validate in Layers

1. Run focused UnitWind tests for object summaries, pathfinding, navigator, and route tools.
2. Run the `door0000.ess` server-integration scenario to verify action-flag observations, route discovery, native array argument transport, and an unreachable route that does not move the player.
3. Run the initial read-only server-integration suite including `mw-route-fetch`.
4. Run the full UnitWind suite with runtime recovery verification.
5. Run the server test catalog and direct reachable-route scenario to verify the renamed tool and actual route movement.

Expected evidence includes retained test summaries and runtime logs. Expected-error and skip cases already classified by test policy are reported separately from unexpected integration failures.