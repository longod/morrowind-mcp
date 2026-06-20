---
name: test-server
user-invocable: true
summary: サーバーのテストを実行する
description: |
  ワークスペースのルートから `tests/test.ps1` を実行し、サーバーのテストを行う。
  `pwsh -File tests/test.ps1`
---

# test-server

## Purpose
- リポジトリのルートからワークスペースのテストスクリプトを実行し、サーバーのテストを行う。

## How to run
ワークスペースのルートから、次のどちらかを使う。

```powershell
pwsh -File tests/test.ps1
```

ルートディレクトリにいるなら、こちらでも同じ。

```powershell
.\tests\test.ps1
```

## Notes
- Inspector v0.22.0 では、`Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 94` が必ず発生する。
- 既知の問題: [Issue #1334](https://github.com/modelcontextprotocol/inspector/issues/1334), [PR #1337](https://github.com/modelcontextprotocol/inspector/pull/1337)
- サーバー側のログは `MWSE.log` で確認できる。
