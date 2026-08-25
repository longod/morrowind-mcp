---
name: server-integration-run
user-invocable: true
description: "Run saved-game or main-menu Morrowind MCP Inspector integration suites and inspect retained status and summary evidence."
---

# Server Integration Run

Use this skill for `tests/server_integration` suites. Each suite is one Python file under `tests/server_integration/suites/`; it declares either a save stem or `None` for main-menu testing.

## Commands

```powershell
.\tests\server_integration_test.ps1 -ListSuites
.\tests\server_integration_test.ps1 -ListSaves
.\tests\server_integration_test.ps1 -Suite main-menu
```

Saved-game suites require `paths.morrowindProfileDir` or `MWMCP_MORROWIND_PROFILE_DIR`; saves are read from its `saves` child directory. `quicksave` is excluded.

`main-menu-read-only` covers discovery and menu-safe cases. Put prompts and tools that require an active loaded game, including `mw-role`, in a saved-game suite such as `initial-read-only`.

## Evidence

- `tests/logs/server_integration/inspector_<timestamp>.log`
- `tests/logs/server_integration/result_<timestamp>.json`
- `tests/logs/server_integration/mwse_<timestamp>.log`
- `tests/logs/server_integration/summary_<timestamp>.json`
- `<Paths.modDataDir>/tests/server-integration-status.json` remains after cleanup as the loaded-event readiness record.

Judge summary `status` first. For failures inspect the result artifact, matching Inspector `[RUN]` / `[EXIT]` blocks, retained status, then MWSE log.
