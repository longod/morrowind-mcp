---
name: servertest-run
user-invocable: true
description: |
  Morrowind MCP のサーバーのテストを行う。出力と MWSE.log を確認してテストの成否を検証する。
---

# servertest-run

## Purpose
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
