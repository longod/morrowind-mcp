# Terrain Grid Specification

This document defines the normative contract for terrain-grid navigation. Statements in [Terrain Navigation Proposals](terrain-navigation-proposals.md) are non-normative until moved here by an implementation decision.

## Purpose

Terrain-grid navigation provides walking routes through active exterior cells, including cells whose pathgrid is absent or does not cover the requested destination. It complements the existing pathgrid graph; selection and merging policy between the two route sources is not defined yet.

Open design decisions and implementation follow-up are tracked in [Terrain Navigation Proposals](terrain-navigation-proposals.md#open-decisions-and-follow-up-work). They are non-normative until an implementation decision moves the resulting contract into this document.

## Scope

- Support walking in active exterior cells only.
- Keep no terrain-grid cache for inactive cells.
- Do not support interiors, swimming, levitation, jumping, bridges, or overlapping floors initially.
- Use terrain height and normal data without reading terrain texture pixels.
- Treat pathgrid travel doors and remote-cell planning as separate concerns.

## Runtime Feasibility Gate

Before implementing grid generation, the outdoor server test must establish that:

1. Active exterior cells and their `tes3land.sceneNode` are accessible.
2. Land scene roots expose pickable `NiTriShape` terrain surfaces.
3. The experimental collision group can be inspected without crashing the runtime.
4. Root-filtered `tes3.rayTest` calls can distinguish landscape, static-object, and pick-object scene graphs.

If terrain geometry or height cannot be read safely, implementation stops until an alternative source is selected. Ray picking is scene-graph triangle testing, not a swept player collision shape, so any disagreement with movement collision must be recorded. Current MWSE exposes each triangle's index triplet through `niTriangle.vertices`; generated metadata incorrectly documents the property as `verticies`. Direct mesh sampling is preferred, with downward rays restricted to the cell landscape root retained as a fallback.

## Module Layout

Terrain navigation lives under `MWSE/mods/morrowind-mcp/navigation/terrain/`:

- `source.lua`: MWSE terrain and collision access.
- `storage.lua`: replaceable flat-array storage.
- `grid.lua`: coordinates, traversal rules, and A*.
- `builder.lua`: resumable generation jobs.
- `manager.lua`: active-cell ownership and lifecycle.
- `parameters.lua`: private terrain-navigation tuning constants.
- `raycast.lua`: candidate-edge validation and hit classification.
- `quality.lua`: resolution and approximation measurements.

## Grid Model

- One grid owns one active exterior cell.
- Samples are stored in flat arrays; per-sample tables and explicit edge tables are prohibited.
- Neighbor relationships are derived from coordinates when queried.
- Eight-direction movement is allowed, with diagonal corner cutting prohibited.
- Initial movement parameters are a maximum slope of 46 degrees and maximum climb of 34 game units, pending measurement against the original engine.
- Water classification uses the cell water level. Initial walking routes do not traverse water unless a later movement policy explicitly allows it.
- Completed grids contain only data needed for route queries. Builder-only data is released.

## Resolution

No default sampling interval is normative until the quality comparison is complete. The implementation must compare at least 64, 128, and 256 game-unit intervals on the same active terrain.

Quality measurements include:

- Height MAE, RMSE, maximum error, and 95th-percentile absolute error.
- Surface-normal angular error.
- Walkable-slope classification disagreement.
- Climb false-pass and false-block rates.
- Connected-component count and fixed route-pair reachability.
- Route length and direction-change count.
- Total generation time, maximum frame slice, sample count, and Lua memory delta. The current memory delta is a signed heap snapshot difference, so garbage collection may make it negative; it is diagnostic rather than an allocation total.

The reference surface is a finer set of downward ray samples against the active land root. Measurements include points between coarse grid samples, not only grid vertices.

The debug quality comparison builds 64-, 128-, and 256-unit grids sequentially for the player's active cell. It uses the 64-unit grid as the temporary reference surface, records build and height-error metrics, then releases every comparison grid. By default, `tests/terrain_benchmark.ps1` starts the server, continues the saved game from the main menu, runs the measurement, and stops the server. Pass `-UseRunningServer` after moving a running game to the intended outdoor location to preserve its current state; it writes the structured result and logs under `tests/logs/terrain_benchmark/`.

## Incremental Generation

A builder transitions through `queued`, `sampling`, and `ready`, or terminates as `cancelled` or `failed`. Sampling classifies each point immediately, so no separately observable `classifying` state exists.

Runtime budget modes are:

- `time`: stop a frame step at the configured elapsed-time limit.
- `samples`: stop at the configured processed-sample limit.
- `hybrid`: stop at whichever limit is reached first.

Time checks may be batched after several samples to reduce clock-call overhead. Tests inject deterministic limits and do not rely on wall-clock timing.

## Active-Cell Lifecycle

- `cellActivated`: queue an exterior-cell build.
- `cellDeactivated`: cancel its build and release both incomplete and completed data immediately.
- `loaded`: release all state, then discover the current active exterior cells again.
- `simulate`: spend one bounded generation step.
- shutdown: unregister callbacks and release all jobs, safe handles, and grids.

The player's current cell has highest build priority. Other active exterior cells are ordered by grid distance from it. Queries distinguish `pending`, `ready`, and `unavailable`.

## Obstacle Validation

Initial static-obstacle support validates candidate route edges with bounded, root-filtered `tes3.rayTest` calls. Because a ray has no radius, multiple rays approximate the player's width and height using `tes3.mobilePlayer.boundSize2D` and `height`.

- Landscape, non-interactable static, and pick-object roots are queried separately.
- Every ray specifies `maxDistance` and the smallest practical root.
- Actor or moving-object hits do not become persistent blocked edges.
- Grid edges are validated as single segments; splitting longer segments is deferred until terrain routes are integrated.
- A blocked candidate edge causes route recomputation.
- Same-cell route queries perform at most eight static-obstacle path attempts by default, including the initial attempt.

## Storage

The first implementation uses ordinary Lua flat arrays. Grid algorithms access data only through the storage module so a later LuaJIT FFI implementation does not alter traversal or builder contracts.

Terrain-navigation parameters are private implementation details in `navigation/terrain/parameters.lua`. They are not part of `settings.defaultConfig`, the saved mod config, or MCM.

## Testing

- Server tests are the feasibility gate for MWSE scene graph, collision group, ray classification, and runtime lifecycle.
- UnitWind covers storage, grid traversal, A*, quality aggregation, builder budgets, cancellation, and manager event ownership.
- Runtime measurements are logged with cell identity, resolution, samples, elapsed time, maximum step time, and memory delta.

## Measured Parameters

The Pelagiad outdoor server scene produced nine ready active-cell grids at the provisional 128-unit interval. Each grid contained 4,225 samples. Generation used the hybrid budget and observed a maximum measured step of 1-2 milliseconds.

The player-cell comparison used the 64-unit grid as its temporary reference:

| Interval | Samples | Height MAE | Height RMSE | 95th percentile | Maximum error | Build time |
|---:|---:|---:|---:|---:|---:|---:|
| 64 | 16,641 | 0 | 0 | 0 | 0 | 45 ms |
| 128 | 4,225 | 0.4140 | 1.2250 | 2 | 20 | 39 ms |
| 256 | 1,089 | 3.9017 | 5.8939 | 12 | 50 | 42 ms |

These values are the builder's accumulated Step work duration from [result_20260809_010734.json](../tests/logs/terrain_benchmark/result_20260809_010734.json); they exclude inter-frame wait. They support 128 game units as the provisional default: its height error remained small while using roughly one quarter of the 64-unit samples. Route-quality and obstacle-classification measurements remain necessary before treating the default as final.

## Decision Log

- Active exterior cells only; no inactive-cell terrain cache.
- Ordinary Lua flat arrays precede FFI optimization.
- Time, sample-count, and hybrid generation budgets are runtime options.
- Scene-graph ray picking is an approximation for player-volume collision.
- Normative behavior and future proposals are maintained in separate documents.
- The Pelagiad outdoor server scene exposed 256 land shapes and 8,192 land triangles in the player cell. Its experimental collision group exposed zero `collidees` and 31 referenced `NiNode` records under `colliders`; code must not infer static or dynamic semantics from the array names alone.
- Current MWSE metadata documents `niTriangle.verticies`, but runtime probing found the actual property is `niTriangle.vertices`, containing three 0-based indices. Grid generation uses these indices and retains root-filtered downward rays as a fallback.
