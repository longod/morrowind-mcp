---
name: servertest-run
user-invocable: true
description: |
  Morrowind MCP のサーバーのテストを行う。出力と MWSE.log を確認してテストの成否を検証する。
---

# servertest-run

## Purpose
- `tests/server_test.ps1` は integration test として扱う。
- リポジトリのルートからワークスペースのテストスクリプトを実行し、サーバーのテストを行う。
- 出力からテストの結果を検証する。
- `MWSE.log` でサーバー側の結果を検証する。

## How to run
ワークスペースのルートから以下を実行する。相対パスを使うため、カレントディレクトリの移動は不要です。

```powershell
.\tests\server_test.ps1
```

2. 出力を確認する。

3. 出力からテスト結果を抽出する。

4. `MWSE.log` を確認する。

5. `MWSE.log` からサーバー側の挙動を検査する。

## Notes
- Inspector v0.22.0 では、`Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 94` が必ず発生する。
- 既知の問題: [Issue #1334](https://github.com/modelcontextprotocol/inspector/issues/1334), [PR #1337](https://github.com/modelcontextprotocol/inspector/pull/1337)
- サーバー側のログは `MWSE.log` で確認できる。
- `start_server_mo2.ps1` は exit code 1 でも Morrowind が起動している場合があるため、プロセスと `MWSE.log` で確認する
- `tests/server_test.ps1` の exit code 1 だけで失敗と断定しない。標準出力、Inspector の既知エラー、MCP 応答、`MWSE.log` を突き合わせて判定する
- `fetch failed` / connection refused / timeout が出た場合は、古いサーバープロセスや半端な起動状態を疑い、`tests/stop_server.ps1` の実行後に再実行する
- `tools/list` は prefixed name（例: `mw_...`）と prefixed title/description を確認し、`tools/call` も公開後の prefixed name で呼び出す
- screenshot resource の検証では巨大な blob 全体をログに出さず、mimeType / blob length / PNG signature だけ確認する
- 正常な PNG blob は base64 先頭が `iVBORw0KGgoA` で始まる
