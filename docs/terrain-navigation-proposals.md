# Terrain Navigation Proposals

This document is non-normative. It records possible extensions and alternatives that are not implemented or guaranteed by the current [Terrain Grid Specification](terrain-grid.md).

## Open Decisions and Follow-Up Work

This section tracks work identified during implementation review. A listed item does not change the current terrain-grid contract. When a decision is made, update [Terrain Grid Specification](terrain-grid.md), implementation, and focused tests together.

### Decisions Required Before Implementation

| ID | Decision required | Current state | Evidence needed to decide | Completion condition |
|---|---|---|---|---|
| TD-01 | Define the route-provider policy between pathgrid and terrain grid. | Terrain grids are generated but player navigation only uses pathgrid. | Representative destinations with missing, disconnected, and complete pathgrids; expected provider and fallback behavior for each. | The selection, fallback, and result contract are normative and covered by server tests. |
| TD-02 | Define active-cell boundary traversal. | Terrain queries reject start and destination locators in different cells. Remote-cell planning is out of scope. | Boundary-crossing route examples, active-cell activation timing, and a rule for unavailable neighbor grids. | The manager can return an ordered multi-cell route or an explicit boundary handoff result, with UnitWind coverage. |
| TD-03 | Define the final quality gate and default interval. | `128` is provisional from height-only comparison. | An independent land-root ray reference, fixed route pairs, and thresholds for error, reachability, route length, and frame cost. | The quality command reports agreed metrics and the accepted interval is recorded as normative. |
| TD-04 | Define persistent-obstacle policy for stateful references. | Static and unattributed ray hits become learned blocked edges; doors have not been measured. | Runtime captures for closed/open doors, activators, moving platforms, and actors across state changes. | Classification and invalidation rules prevent stateful obstacles from being permanently learned as static. |

### Implementation and Validation Follow-Up

| ID | Work | Current limitation | Acceptance check |
|---|---|---|---|
| TF-01 | Replace the temporary 64-unit grid reference with independent downward land-root ray samples. | The 64-unit result self-compares to zero height error. | Measurements include between-vertex samples and produce non-self-referential metrics for all three resolutions. |
| TF-02 | Add route-quality metrics after TD-03 defines their corpus and thresholds. | Normal angular error, slope disagreement, climb false-pass/false-block, components, reachability, path length, and direction changes are not reported. | The debug comparison returns each approved metric for the fixed scene and route pairs. |
| TF-03 | Add an opt-in diagnostic route operation after TD-01. | `FindPath` and segment validation have no public runtime caller or per-route observability. | A debug-only operation reports provider, reroutes, ray count, elapsed time, and hit classifications without moving the player. |
| TF-04 | Measure and remove fallback player dimensions. | Ray validation uses hard-coded bounds only when `tes3.mobilePlayer` is unavailable. | Runtime probe confirms normal values; fallback values have a documented source or are replaced by a conservative no-query result. |
| TF-05 | Re-measure benchmark timings after the work-time accounting correction. | Existing build times included inter-frame delay and cannot be compared to the corrected metric. | `tests/terrain_benchmark.ps1` produces updated 64/128/256 results with work duration and maximum slice recorded. |

## Remote Exterior Travel

Use exterior cells as a coarse grid graph outside the active area. Plan to the next active-area boundary, use terrain navigation locally, and replan after cell activation. The coarse graph must not claim detailed terrain passability for unloaded cells.

## Pathgrid Integration

Pathgrids may provide preferred corridors, authored links, and teleport-door topology. Terrain grids may provide destination coverage and alternatives. Future integration could merge both into one hierarchical graph or compare route costs from independent providers.

## Storage Optimization

Replace Lua flat arrays with LuaJIT FFI arrays after profiling. The storage interface is intended to isolate allocation, indexing, and release details. Packed heights, flags, and edge masks may make broader caching feasible, but inactive-cell caching remains outside the initial implementation.

## Static Collision

Possible improvements beyond route-time multiple rays:

- Extract collision triangles from runtime collision groups or object collision roots.
- Bucket triangles spatially by terrain tile or grid cell.
- Rasterize occupancy and head clearance into the grid.
- Dilate blocked space by the actor radius or calculate a distance field.
- Refine only cells near obstacles with an adaptive grid.
- Layer temporary actor and moving-prop obstacles over immutable static occupancy.

## Bridges and Multiple Floors

A single-height terrain grid cannot represent a bridge deck and terrain below at the same horizontal coordinate. Candidate approaches are:

- Multi-span columns with vertical clearance and climb-qualified links.
- A separate static-surface layer generated from upward-facing collision triangles.
- Authored pathgrid or discovered off-mesh links between terrain and deck layers.
- A local polygon navmesh around bridges, stairs, docks, and other multi-level structures.

## Other Route Representations

- Probabilistic roadmaps for sparse collision-aware local planning.
- Visibility graphs when reliable obstacle contours exist.
- Learned breadcrumb graphs from successfully traversed routes.
- Local navmeshes only where terrain-grid assumptions fail.

## Exact Collision Queries

A capsule cast or swept box matching the player's collision volume would be preferable to multiple rays. MWSE currently exposes scene-graph ray picking but no public shape sweep. A future native or newly exposed API could replace the approximation behind the obstacle-query interface.
