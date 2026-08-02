---
name: game-progression-probe
user-invocable: true
description: "Start Morrowind from NEW GAME, discover how far current Morrowind MCP tools and resources can progress it, and emit an agent-readable, replayable JSON procedure. Use for game progression exploration, NEW GAME tool capability probes, or generating replay scenarios."
---

# Game Progression Probe

Use the full contract in [game progression testing](../../../docs/game-progression-testing.md).

## Procedure

1. Use the Morrowind MCP Player at autonomy level 4 in progression exploration mode. Start through `tests/start_server_mo2.ps1 -WaitForServer`. Do not issue MCP operations until this command reports that the configured TCP endpoint is responding; treat its timeout as a launch failure, not an attempted game operation.
2. Discover the current capabilities through `initialize`, `tools/list`, `resources/list`, `prompts/list`, and read-only state/UI tools. Do not rely on selectors or waits from older runs. Treat the currently observed public surface as evidence: do not assume state-dependent tools, resources, or prompts remain available, and refresh the relevant list before invoking an unconfirmed capability. Refresh `tools/list` after `notifications/tools/list_changed`, `resources/list` after `notifications/resources/list_changed`, and `prompts/list` after `notifications/prompts/list_changed` when the client receives the corresponding notification. A previously observed list remains usable within the same session until evidence of a capability change appears. If discovery is unavailable, record an unavailable capability result as evidence and do not repeatedly invoke the same unconfirmed capability.
3. Find and invoke NEW GAME from the observed menu. Do not load a save before NEW GAME is complete.
4. Capture a screenshot after meaningful state changes and before risky or ambiguous actions. Prefer `mw-screenshot-save capture_with_ui=true` when UI state matters; avoid redundant captures during unchanged polling.
5. Iterate: observe state, write an assessment of the situation, evidence, remaining candidate actions, and decision, make one justified tool operation, wait only using an observed readiness condition, then observe state again. Choose that condition from the operation's expected effect, such as a menu change, player-control change, target/world change, or dialogue completion; do not use a generic menu-appearance condition. During animation, loading, or NPC speech, an unchanged observation is intermediate evidence until the action-specific wait expires. Consider `stalled` only after repeated observations show no expected milestone, no newly available capability, and no reasonable recorded candidate action.
6. Save every successful step in a schema version 1 JSON file under `tests/logs/game_progression/`. Include `intent`, operation, assertions, waits, observed summary, assessment, screenshot resource URIs, and notes so another agent can adapt to a changed UI.
7. Immediately before reporting `stalled` or `failed`, capture an evidence screenshot. The replay runner records up to two related read-only probes automatically: menu action uses menu/player state, player action uses player/target state, and player navigation uses player/world state. Record any additional observed probe responses, the final assessment, and all remaining or rejected candidates, then stop the server.
8. Validate the generated file with `tests/game_progression/run.py --validate-only`.
9. Report `completed`, `stalled`, or `failed`. For stalled, report the final assessment, screenshot URI, unchanged observations, attempted operations, remaining capabilities, and the policy values that led to the result. Stop the server for terminal failure and stalled outcomes.

## Replay

Use `tests/game_progression/run.py --scenario <scenario.json>` for deterministic replay. The runner executes the recorded operations and assertions; it does not rediscover the bootstrap path. If agent exploration succeeds but replay fails, improve the scenario contract or runner rather than weakening the observed test condition.

