# Server Integration Testing

`tests/server_integration` runs ordered Inspector cases after Morrowind reaches either the main menu or a selected saved game.

Set `paths.morrowindProfileDir` in `mwmcp.local.json`, or set `MWMCP_MORROWIND_PROFILE_DIR`. The runner lists `saves/*.ess`; save names use the file stem. `quicksave` is never accepted.

```powershell
.\tests\server_integration_test.ps1 -ListSuites
.\tests\server_integration_test.ps1 -ListSaves
.\tests\server_integration_test.ps1 -Suite main-menu
```

Morrowind is activated in the foreground by default after the server is reachable. Use `--no-foreground` for read-only suites that do not send game input.

Add one suite per file under `tests/server_integration/suites/`.

```python
from case_api import Run, Suite, Wait

SUITE = Suite(
    id="seyda-neen",
    save_name="Seyda Neen Integration",
    cases=(Run("tools-available"), Wait(2), Run("menu-fetch")),
)
```

Reusable Inspector operations belong in `tests/server_integration/cases/`. `CaseDefinition` declares operation templates, required parameters, and JSON-pointer assertions. `Run` supplies parameters for each reuse.

`main-menu-read-only` covers discovery and menu-safe cases. `initial-read-only` covers player, world, player Memory, and prompt retrieval cases. Prompts and tools that require an active loaded game, such as `mw-role`, belong in a saved-game suite rather than a main-menu suite.

Lua writes `server-integration-status.json` beside the logical test context after the matching `loaded` event and one-frame delay. Its physical runtime location is `<Paths.modDataDir>/tests/`. It is retained intentionally; each run replaces it with a new `run_id` before launch.

## Proposals

The following items are not implemented. They are proposed to bring reusable saved-game suites closer to the diagnostic coverage of `tests/server_test.ps1` while preserving deterministic suite definitions.

### Priority 1: Reliable Case Execution

- Add `WaitUntil` for a bounded Inspector operation retry until its assertions pass. Prefer it to fixed `Wait` when waiting for post-load UI, Memory, or world state.
- Add an invocation-level condition that reports `[SKIPPED]` when an optional tool, UI target, or save-specific prerequisite is unavailable. A missing required prerequisite should still fail the suite.
- Recognize Inspector `UV_HANDLE_CLOSING` when a usable JSON response is present, matching the existing server test behavior.

Acceptance: a suite can wait for a condition, skip an optional case with its reason recorded, and continue after the known Inspector condition when its response is valid.

### Priority 2: Stateful Reusable Cases

- Add capture values from a case response, such as menu paths, reference IDs, positions, and inventory item identifiers.
- Resolve captured values into later case arguments, with missing captures reported as a clear case failure.
- Extend assertions with absence, item count, regular-expression, numeric range, and small JSON-schema checks.

Acceptance: a suite can fetch an actionable menu item or reference and use the captured identifier in a later action without hand-writing Inspector process handling.

### Priority 3: Read-Only Evidence

- Add a screenshot-save and screenshot-resource case pair that verifies MIME type and PNG/JPEG signature.
- Add a Memory debug-dump case with checks for generated files and expected document fields.
- Add payload-size comparison cases for reference detail levels when profiling serialization changes.

Acceptance: a suite can retain visual and Memory evidence without relying on ad hoc scripts.

### Priority 4: Input and Interaction Cases

- Add wrappers for `mw-menu-action`, `mw-player-action`, `mw-player-look`, and `mw-player-navigate` after capture/context support exists.
- Add suite-specific inventory, container, dialogue, merchant, and item-drop probes. These remain opt-in because their prerequisites and state changes vary by save.

Acceptance: input suites require foreground activation, record before/after state, and leave a clear cleanup or expected-state contract.

### Priority 5: Lifecycle Diagnostics

- Attempt supported shutdown when server launch reports an unexpected error, then record whether the runner had started or found an existing process.
- Record `mwse_log.state = missing` with a warning when no log is copied.
- Add an optional stateful Streamable HTTP client only when a suite needs one persistent MCP session, subscriptions, or SSE verification. The current Inspector-per-case execution remains appropriate for stateless cases.

Acceptance: every terminal run records shutdown and MWSE-log outcomes, and session-dependent tests do not rely on the stateless Inspector adapter.
