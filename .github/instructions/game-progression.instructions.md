---
description: Game progression exploration, replay, and scenario guidelines.
applyTo: "{tests/game_progression/**,tests/logs/game_progression/**,docs/game-progression-testing.md}"
---

## Game Progression Testing

- Game progression code, scenarios, generated recordings, and documentation follow [game-progression-testing.md](../../docs/game-progression-testing.md).
- Before changing `tests/game_progression/**`, a scenario contract, termination behavior, diagnostics, or replay behavior, read the relevant specification section. Update the specification in the same change when the observable workflow, schema contract, or policy changes.
- Keep `scenario.schema.json` and the stricter validation in `scenario.py` consistent. When a new field requires semantic validation, enforce it in `scenario.py` and add focused tests under `tests/game_progression/unit/`.
- Preserve the NEW GAME bootstrap contract. Do not replace observed UI discovery with saved-game loading, `skipMainMenu`, stale selectors, or previously assumed wait conditions.
- Treat tools, resources, and prompts as state-dependent capability surfaces. Do not assume a capability observed in an earlier state is still available; record unavailable capabilities as evidence and avoid repeating the same unconfirmed invocation.
- A wait condition must assert the expected effect of its operation, such as a menu transition, dialogue completion, player control, target, or world-state change. An unchanged menu during an animation, load, or NPC speech is not sufficient evidence of a stall.
- A `stalled` outcome requires repeated observations without the expected milestone, no newly available capability, and no reasonable recorded candidate action. Capture terminal evidence and a final assessment before stopping the server.
- Keep recorded `observed`, `assessment`, and `notes` diagnostic. Do not turn volatile values such as timestamps or transient IDs into replay assertions.
- Use the existing PowerShell lifecycle scripts for launch and shutdown. Resolve host, port, and paths through `tests/mwmcp_config.ps1`; do not hard-code local machine settings.

## Validation

- After changing scenario parsing or validation, run the focused Python unit tests and `tests/game_progression/run.py --validate-only` for an affected scenario when one exists.
- After changing replay, launch, shutdown, or live MCP behavior, run the relevant game progression replay and inspect its generated `run.json` and copied `MWSE.log` when available.
- Documentation-only changes do not require a live game run, but the documented contract must agree with the schema and runner behavior.