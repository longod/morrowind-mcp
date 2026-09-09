# MCP Client and Notification Watcher Proposal

This document is non-normative. It proposes a future small MCP client for
long-lived notification observation during Morrowind progression exploration.
It does not change the current MCP contract or implement a persistent watcher.

## Purpose

Progression exploration needs current `tools/list`, `resources/list`, and
`prompts/list` data as the game moves between states. A player agent can start
the existing bounded discovery watcher before a state-changing operation, but
the watcher exits after `-WatchSeconds` and is controlled by the agent.

The proposed client would keep one dedicated Streamable HTTP MCP session open
for the lifetime of an exploration run. It would receive server notifications,
refresh the affected list, and persist the evidence without taking gameplay
actions. The player agent would remain responsible for observing game state,
choosing actions, and deciding whether a progression milestone was achieved.

## Current State

| Surface | Current behavior | Limitation |
|---|---|---|
| [tests/mcp_discover.ps1](../tests/mcp_discover.ps1) | Creates an independent session, captures initial lists, and optionally keeps a session-scoped SSE stream open. | `-WatchSeconds` is bounded; records are written when the process exits; no reconnect loop. |
| [tests/game_progression/run.py](../tests/game_progression/run.py) | Replays recorded MCP operations and assertions. | Does not open an SSE stream or insert discovery operations after state changes. |
| [tests/start_server_mo2.ps1](../tests/start_server_mo2.ps1) | Starts Morrowind through MO2 and optionally waits for TCP reachability. | Does not perform MCP discovery or notification monitoring. |
| [game-progression-probe skill](../.agents/skills/game-progression-probe/SKILL.md) | Instructs the agent to use initial discovery, bounded watchers, and fresh discovery fallbacks. | The agent must start the watcher and choose the observation window. |
| [Morrowind MCP Player agent](../.github/agents/mwmcp-player.agent.md) | Uses current live Memory, UI, player, world, and capability evidence for decisions. | It is not a resident MCP transport client. |

The existing discovery script already implements the core notification path:
after receiving a `*_list_changed` notification, it requests the corresponding
list again and stores the refreshed response. The proposal is primarily about
making that lifecycle durable and independently observable.

## Goals

The future watcher should:

1. Keep a dedicated MCP session and notification stream open for one exploration
   run.
2. Refresh `tools/list`, `resources/list`, or `prompts/list` when the matching
   `*_list_changed` notification arrives.
3. Reconnect after an SSE disconnect, server restart, or expired MCP session.
4. Save notifications, refreshed lists, connection transitions, and errors
   incrementally so an interrupted run retains evidence.
5. Expose a small status or latest-snapshot file that the player agent can
   inspect without parsing an active process.
6. Shut down cleanly and delete its MCP session when the run ends.
7. Use the repository configuration helper instead of hard-coded host, port, or
   output paths.

## Non-Goals

The watcher should not:

- send keyboard, mouse, menu, navigation, or other gameplay actions;
- decide which candidate action the player agent should choose;
- declare a progression milestone or completion goal achieved;
- replace the deterministic replay behavior of `run.py`;
- read every Memory document automatically;
- change the MCP notification contract or introduce a second server protocol.

## Proposed Architecture

Keep server lifecycle, gameplay decisions, and notification observation as
separate responsibilities:

```text
start_server_mo2.ps1
  └─ launch Morrowind and wait for TCP reachability

mcp client / watcher
  ├─ maintain one MCP session
  ├─ keep the SSE notification stream open
  ├─ refresh changed catalogues
  └─ persist snapshots and status

Morrowind MCP Player agent
  ├─ inspect current UI, Memory, player, world, and capabilities
  ├─ choose and execute gameplay actions
  └─ assess milestones and terminal state

game_progression/run.py
  └─ replay an already recorded procedure deterministically
```

The watcher should be a separate process from
[tests/start_server_mo2.ps1](../tests/start_server_mo2.ps1). This allows it to
survive individual discovery calls and prevents game shutdown logic from being
coupled to notification observation.

The existing PowerShell script is a useful prototype. A long-lived
implementation may remain PowerShell or use a small Python client. The
decision should be made after measuring reconnect behavior and the desired
artifact format rather than by duplicating both implementations.

## MCP Session and SSE Lifecycle

The proposed client should use the current Streamable HTTP contract and MCP
protocol version `2025-11-25`:

1. Resolve the endpoint through `tests/mwmcp_config.ps1`.
2. Send `initialize` and retain the returned `MCP-Session-Id`.
3. Send `notifications/initialized` on that session.
4. Open one `GET` request with:
   - `MCP-Session-Id`;
   - `Accept: text/event-stream`.
5. Keep the SSE response open while the exploration is active.
6. Send list requests through `POST` using the same session ID.
7. On graceful shutdown, close the stream and delete the session.

The project contract treats notifications as session-scoped SSE traffic. The
watcher must therefore maintain exactly one active stream for its session.
Overlapping reconnect attempts must not create competing streams. If the
server replaces an older SSE stream for the same session, the watcher must
cancel the older reader before installing the new one.

To reduce the race between the initial catalogue and stream startup, the
implementation should define one ordering and test it. The preferred ordering
is:

```text
initialize
  ↓
notifications/initialized
  ↓
open SSE stream
  ↓
capture baseline tools/resources/prompts lists
```

The baseline is a snapshot, not proof that no notification occurred before the
session was created. A reconnect must always obtain a fresh baseline.

## Notification Handling

The mapping is direct:

| Notification | Follow-up request |
|---|---|
| `notifications/tools/list_changed` | `tools/list` |
| `notifications/resources/list_changed` | `resources/list` |
| `notifications/prompts/list_changed` | `prompts/list` |

Each notification record should include:

- observation timestamp;
- notification JSON;
- MCP session identifier or a redacted session reference;
- refresh request identifier;
- refreshed response or an explicit refresh error;
- connection generation, so reconnect gaps are visible.

The watcher must not infer that a list is unchanged merely because no
notification arrived. Notifications are invalidation signals, not a
replacement for a current snapshot. The player agent should use the latest
snapshot while the watcher is healthy and request a one-shot fresh discovery
when the watcher is unavailable, expired, or behind a relevant state boundary.

## Reconnect and Failure Policy

The watcher should distinguish these conditions:

| Condition | Required behavior |
|---|---|
| SSE stream closes unexpectedly | Record the disconnect, retry with bounded backoff, and expose a degraded status while disconnected. |
| MCP session is rejected or expired | Create a new session, reinitialize, open a new SSE stream, and capture fresh baseline lists. |
| Server is unreachable | Retry while the run is active; do not report a missing list as an empty list. |
| Notification JSON is malformed | Record the raw event safely, report an explicit parse error, and keep the stream if possible. |
| Refresh request fails | Record the notification and refresh error; retry or require a fresh snapshot before the agent follows a new link. |
| Output cannot be written | Surface the failure and mark evidence persistence as degraded; do not silently continue as if evidence were saved. |
| Graceful stop requested | Stop accepting new work, close the stream, persist final status, and delete the session. |

Backoff, retry count, and maximum disconnected time should be configurable and
recorded in the run artifact. A reconnect gap must remain visible in the
evidence; the watcher must not claim continuous coverage across it.

## Persistence and Agent Coordination

The watcher should write append-only event records during the run and maintain
a separately replaceable latest-snapshot document. This avoids losing all
evidence when a long-running process is interrupted and avoids concurrent
writers corrupting one large JSON document.

One possible layout is:

```text
<run-directory>\
  watcher-events.jsonl
  watcher-latest.json
  watcher-status.json
```

`watcher-status.json` should expose at least:

- `state`: `starting`, `connected`, `degraded`, or `stopped`;
- current endpoint and connection generation;
- session start and last-event timestamps;
- last notification method;
- last successful refresh method and timestamp;
- last error, if any;
- output paths.

The player agent should treat a stale or degraded snapshot as diagnostic
evidence, not as proof that a resource is unavailable. For progression
exploration, the coordination policy should be:

1. Start the watcher after the server is reachable and before a state-changing
   operation.
2. Use the watcher output after NEW GAME, loading, dialogue, menu, and other
   state boundaries.
3. Before following a player or Memory link, confirm that the latest catalogue
   is connected and newer than the relevant boundary. If not, run a one-shot
   fresh discovery.
4. Continue to read `morrowind://memory/index.json` and its published links
   live; a catalogue refresh does not replace the agent's state verification.
5. Stop the watcher only after terminal evidence and the final assessment have
   been recorded.

The watcher does not need to understand `character_generation`,
`ready`, `finished`, or any other scenario-specific field. Those remain
completion evidence interpreted by the active scenario and player agent.

## Proposed Command Surface

The exact command name is open, but the future interface should support
operations equivalent to:

```powershell
# Start a long-lived watcher for one run.
.\tests\mcp_watch.ps1 `
  -OutputDirectory .\tests\logs\game_progression\<run-id> `
  -Reconnect

# Request a graceful stop from another process.
.\tests\mcp_watch.ps1 -Stop `
  -StatusPath .\tests\logs\game_progression\<run-id>\watcher-status.json
```

The existing `mcp_discover.ps1 -WatchSeconds` behavior should remain available
for bounded, one-shot discovery. A persistent mode should not silently change
the meaning of that existing command.

## Security and Resource Limits

- Bind to the configured local endpoint; do not add a public listener.
- Do not write credentials or arbitrary request bodies to watcher artifacts.
- Bound event and response sizes to avoid unbounded memory growth.
- Rotate or cap event logs for very long sessions.
- Redact session identifiers in user-facing summaries if they are treated as
  sensitive, while retaining a stable internal correlation value.
- Do not allow the watcher to execute arbitrary MCP tools.

## Validation Plan

Before adopting a persistent watcher, add focused tests for:

1. SSE event framing, including multiline `data:` fields and blank-line
   delimiters.
2. Notification-to-list mapping for all three `*_list_changed` methods.
3. Incremental event and snapshot persistence.
4. Stream disconnect and reconnect with a fresh baseline.
5. Expired-session recovery through initialize.
6. Refresh failures that remain visible without becoming empty-list success.
7. Graceful stop and session deletion.
8. A live notification run using the existing
   [tests/sse_test.ps1](../tests/sse_test.ps1).

Progression validation should also confirm that the watcher artifact records a
resource becoming available after a NEW GAME transition, while the player
agent independently verifies the live Memory state and scenario completion
assertions.

## Open Decisions

| ID | Decision | Evidence needed |
|---|---|---|
| MCW-01 | Keep the long-lived implementation in PowerShell or add a Python client. | Reconnect reliability, incremental JSON performance, and ease of lifecycle control on Windows. |
| MCW-02 | Use one watcher per progression run or a shared process with multiple sessions. | Isolation requirements and concurrent test runs. |
| MCW-03 | Define the exact event and latest-snapshot schemas. | Agent consumption needs and compatibility with existing discovery artifacts. |
| MCW-04 | Choose reconnect backoff and maximum disconnected duration. | Server restart timings and acceptable progression evidence gaps. |
| MCW-05 | Define how the player agent discovers the watcher status path. | Agent tool limitations and run-directory ownership. |
| MCW-06 | Confirm notification delivery to an independent watcher session for every catalogue change. | Live SSE evidence across main-menu, NEW GAME, loading, and in-game transitions. |

Until these decisions are resolved and the implementation is validated, the
current bounded watcher plus fresh-discovery fallback remains the supported
workflow.
