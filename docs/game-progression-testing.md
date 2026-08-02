# Game Progression Testing

## Purpose

This workflow records how far an agent can progress from a NEW GAME using only the currently exposed Morrowind MCP tools and resources. A successful recording is replayed by `tests/game_progression/run.py` without asking an agent to rediscover the UI.

## Exploration

1. Start the game through `tests/start_server_mo2.ps1`.
2. Inspect `tools/list`, `resources/list`, `prompts/list`, and the current menu/state before choosing an operation.
3. Discover the NEW GAME action from the observed UI. Do not use `skipMainMenu`, a selector from an earlier recording, or a preselected wait condition.
4. After every state-changing operation, inspect the resulting menu and game state. Record only operations that succeeded and their observed readiness condition, except for one intentional terminal MCP tool error recorded with `expected_error`.
5. Do not load a save until NEW GAME has completed. A later load is a separately recorded action.
6. Write the recording under `tests/logs/game_progression/`. Copy only stable recordings into a tracked scenario location when one is introduced.

## Scenario Contract

The schema is `tests/game_progression/scenario.schema.json`; the runner performs the stricter validation in `scenario.py`.

- `schema_version` is `1`.
- `bootstrap.start_mode` is always `new_game`.
- Every step has an `id`, an agent-readable `intent`, and a replayable MCP `operation`.
- `assertions` use RFC 6901 `pointer` with `exists`, `equals`, or `contains`.
- `wait_until` repeats an observed operation until its assertions pass. It records `timeout_seconds` and `interval_seconds` instead of hard-coding them into the runner.
- `expected_error.message_contains` records an intentional MCP tool error. Replay treats the matching `isError` result as verified behavior instead of an infrastructure failure.
- `observed` and `notes` retain state summaries and reasoning for agent-guided reproduction. They do not make volatile IDs or timestamps into strict assertions.
- `assessment` records the agent's `situation`, observed `evidence`, remaining `candidate_actions`, and `decision`. This is diagnostic context, not a replay assertion.
- `screenshots` records MCP screenshot resource URIs with a `purpose`. Take screenshots after meaningful state changes, before risky or ambiguous actions, and immediately before a `stalled` or `failed` terminal outcome. Use `mw-screenshot-save` with `capture_with_ui=true` for UI diagnosis; capture without UI only when the 3D world state is also relevant. Before a terminal outcome, the runner records at most two related read-only probes: menu action selects menu and player state; player action selects player and target state; player navigation selects player and world state. Probe responses or their errors are saved in `run.json` under `diagnostic_probes`.

## Termination Policy

`termination_policy` controls these values:

- `max_elapsed_seconds`: total scenario time limit.
- `max_stalled_cycles`: maximum repeated observations without a milestone.
- `final_wait_seconds`: final action-specific readiness wait.
- `max_retries_per_step`: retry limit for one recorded operation.
- `stop_server_on_stalled`: whether to stop Morrowind after a stalled outcome.

Precedence is CLI override, scenario value, then runner default.

A stalled outcome requires all of the following:

- The operation did not return an error.
- Repeated observations show no milestone or observable state change.
- No new capability became available.
- No reasonable recorded candidate action remains.

Before ending, capture an evidence screenshot and write the final assessment with the observed blockage and rejected candidates. These criteria are intentionally adjustable in JSON.

## Replay

Validate a recording without launching the game:

```powershell
& "$HOME\.local\bin\python3.14.exe" .\tests\game_progression\run.py --scenario <scenario.json> --validate-only
```

Replay launches through the existing PowerShell entry point, resolves configuration through `mwmcp_config.ps1`, and stops Morrowind with `stop_server.ps1` unless `--no-stop` is specified. A scenario whose recorded `outcome` is `failed` can still return success when its terminal `expected_error` is observed. Run artifacts, including `run.json` and an `MWSE.log` copy when available, are saved below `tests/logs/game_progression/`.
