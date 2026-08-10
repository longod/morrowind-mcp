---
name: ssetest-run
user-invocable: true
description: Morrowind MCP の SSE/Streamable HTTP 通知テストを tests/sse_test.ps1 で実行し、SSE test log と MWSE.log を確認して成否を検証する。
---

# ssetest-run

## Purpose
- `tests/sse_test.ps1` は Streamable HTTP / SSE の integration test として扱う。
- リポジトリのルートからワークスペースのテストスクリプトを実行し、MCP session と SSE server-to-client notification 経路を検証する。
- Test Runner Agent の共通手順で `sse_test` summary を一次根拠として判定する。

## How to run
ワークスペースのルートから以下を実行する。相対パスを使うため、カレントディレクトリの移動は不要です。

```powershell
.\tests\sse_test.ps1
```

既にサーバーを起動済みで停止したくない場合のみ、必要に応じて以下を使う。

```powershell
.\tests\sse_test.ps1 -NoStart -NoStop
```

## Suite-specific follow-up
- summary は `sse_<timestamp>.log` の `notifications/message` pass marker と `[FAILED]` / `[ERROR]` を判定する。
- `failed` / `inconclusive` の場合だけ summary evidence の保存済み SSE/MWSE artifact を読み、session、SSE stream、notification、DELETE 後の `404` を切り分ける。ライブ `MWSE.log` は読まない。

## Expected Coverage
- `initialize` response が Streamable HTTP session id を返す。
- initialize capabilities に以下が含まれる。
  - `prompts.listChanged = false`
  - `resources.subscribe = true`
  - `resources.listChanged = true`
  - `tools.listChanged = false`
- `ping` は initialize 応答後、`notifications/initialized` 前でも HTTP `200 OK` と空 result を返す。
- Client-to-server notification は POST で受け付けられ、HTTP `202 Accepted` no body になる。
- `notifications/cancelled` は client-to-server notification として受け付けられ、対象 request id と reason が記録される。
- Server-to-client notification は session-scoped SSE stream に流れる。
- `resources/subscribe` / `resources/unsubscribe` が HTTP `200 OK` で処理される。
- Session DELETE が HTTP `204 No Content` で処理され、削除済み session の SSE GET は HTTP `404 Not Found` になる。

## Failure Triage
1. `Failed to connect to the server` / connection refused / timeout
   - 古い Morrowind プロセスや半端な起動状態を疑う。
   - `tests/stop_server.ps1` を実行してから再試行する。

2. `Initialize failed`
   - `mwse_<timestamp>.log` でサーバー起動、protocol version、POST content negotiation を確認する。

3. Capability assertion failure
   - `OnInitialize` の `result.capabilities` を確認する。
   - prompts/resources/tools の `listChanged` や `resources.subscribe` を変更した直後なら、仕様と実装の整合を確認する。

4. `Initialized notification returned a body`
   - JSON-RPC notification に `id` がない場合、HTTP のみで ack し、JSON-RPC result body を返していないか確認する。

5. `ping failed` / `ping response result should be an empty object`
   - `ping` が `methodHandlers` に登録されているか確認する。
   - JSON-RPC result が `{}` になっているか確認する。

6. `Cancelled notification failed` / `Cancelled notification returned a body`
   - `notifications/cancelled` が `methodHandlers` に登録されているか確認する。
   - JSON-RPC notification として `id` を含めず、HTTP `202 Accepted` no body で処理されているか確認する。

7. `SSE GET failed` / unexpected SSE content type
   - GET request の `Accept: text/event-stream` と `MCP-Session-Id` を確認する。
   - duplicate GET の latest-stream-wins 処理や session timeout を確認する。

8. Unexpected SSE notification method
   - `logging/setLevel` が `notifications/message` を enqueue しているか確認する。
   - `notificationQueue` の重複排除や SSE flush の順序を確認する。

9. DELETE / deleted session GET failure
   - `OnDELETE`, `DeleteSession`, `ValidateTransportRequest` の session lookup と close 処理を確認する。

## Notes
- このテストは Morrowind/MWSE を起動するため、`unit_test.ps1` より重い integration test として扱う。
- `server_test.ps1` と同時に実行しない。どちらも同じ Morrowind/MCP server を起動・停止するため競合しやすい。
- `-NoStart -NoStop` は手動起動中のサーバーに対する確認用であり、通常は使わない。
