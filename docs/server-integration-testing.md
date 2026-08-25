# Server Integration Testing

`tests/server_integration` runs ordered Inspector cases after Morrowind reaches either the main menu or a selected saved game.

Set `paths.morrowindProfileDir` in `mwmcp.local.json`, or set `MWMCP_MORROWIND_PROFILE_DIR`. The runner lists `saves/*.ess`; save names use the file stem. `quicksave` is never accepted.

```powershell
.\tests\server_integration_test.ps1 -ListSuites
.\tests\server_integration_test.ps1 -ListSaves
.\tests\server_integration_test.ps1 -Suite main-menu
```

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
