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
- 実行後に保存される `tests/logs/server_test` 配下のアーティファクト（Inspector 集約ログ、MWSE.log コピー）を確認する。

## How to run
ワークスペースのルートから以下を実行する。相対パスを使うため、カレントディレクトリの移動は不要です。

```powershell
.\tests\server_test.ps1
```

引数で foreground 制御を切り替えられる。

```powershell
# 既定: サーバー接続確認後に Morrowind を foreground 化する
.\tests\server_test.ps1

# 従来挙動: foreground 化を行わない
.\tests\server_test.ps1 -NoForeground
```

`-NoForeground` を指定すると、接続確認後のフォアグラウンド化ステップをスキップする。
バックグラウンドではキーボードのキー入力やマウスのボタン入力（mw-player-action など）が送られないため、入力を使う検証ではフォアグラウンド化する必要がある。入力送信が不要な検証では `-NoForeground` で実行してよい。
自動 foreground 化は best effort であり、ロードされるセーブ内容や実際のウィンドウ状態に依存するため、`tests/server_test.ps1` は target/activate/MenuDialog への到達を必須にしない。会話 actor まで到達したかは、実行後の `MWSE.log` と `tests/validate_memory_dump.ps1` の `conversationActors` 集計で判断する。

2. 出力を確認する。

3. 出力からテスト結果を抽出する。

4. 実行完了時に表示される保存先を確認する。
  - `[INFO] Inspector logs: ...\\tests\\logs\\server_test\\inspector_<timestamp>.log`
  - `[INFO] MWSE log copy: ...\\tests\\logs\\server_test\\mwse_<timestamp>.log`

5. `mwse_<timestamp>.log` を確認する（必要に応じて元の `MWSE.log` も確認する）。

6. `MWSE.log` からサーバー側の挙動を検査する。

7. Memory dump を検査する。
  - `tests/server_test.ps1` が `mw-debug-action action=memory:SaveDebugDocuments` を実行した後、`tests/validate_memory_dump.ps1` を実行する。
  - 出力の `conversationActors` は、debug dump 成果物上で `target -> activate -> MenuDialog` まで到達した actor 数を表す。セーブ内容や foreground 状態に依存するため、通常の server test 合否とは分けて読む。

## Notes
- Inspector v0.22.0 では、`Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), file src\win\async.c, line 94` が必ず発生する。
- 既知の問題: [Issue #1334](https://github.com/modelcontextprotocol/inspector/issues/1334), [PR #1337](https://github.com/modelcontextprotocol/inspector/pull/1337)
- サーバー側のログは `MWSE.log` で確認できる。
- `start_server_mo2.ps1` は exit code 1 でも Morrowind が起動している場合があるため、プロセスと `MWSE.log` で確認する
- `tests/server_test.ps1` の exit code 1 だけで失敗と断定しない。標準出力、Inspector の既知エラー、MCP 応答、`MWSE.log` を突き合わせて判定する
- `fetch failed` / connection refused / timeout が出た場合は、古いサーバープロセスや半端な起動状態を疑い、`tests/stop_server.ps1` の実行後に再実行する
- `tests/server_test.ps1` は Inspector の詳細をコンソールへ全量表示しない。詳細は `inspector_<timestamp>.log` に集約保存される。
- `tests/server_test.ps1` は実行終了時に `MWSE.log` を `mwse_<timestamp>.log` としてコピー保存する。サーバー側検証はこのコピーを優先利用できる。
- `tests/server_test.ps1` の既定動作では接続確認後に foreground 化を試行する。バックグラウンドではキーボードのキー入力やマウスのボタン入力が送られないため、入力を使う検証では foreground 化が必要。入力送信が不要な検証は `-NoForeground` を使ってよい。
- `tools/list` は prefixed name（例: `mw_...`）と prefixed title/description を確認し、`tools/call` も公開後の prefixed name で呼び出す
- screenshot resource の検証では巨大な blob 全体をログに出さず、mimeType / blob length / PNG signature だけ確認する
- 正常な PNG blob は base64 先頭が `iVBORw0KGgoA` で始まる

## Failure Triage
失敗時は次の順で確認する。

1. コンソール要約
  - `[FAILED]` の直後に表示されるエラー要点を確認する。
  - `fetch failed` / connection refused / timeout の場合は `tests/stop_server.ps1` 実行後に再試行する。

2. Inspector 集約ログ（`inspector_<timestamp>.log`）
  - 該当 `[RUN] ...` ブロックの `[EXIT]`、`--- STDERR ---`、`--- STDOUT ---` を確認する。
  - `Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)` と `Failed with exit code: 3221226505` のみで、STDOUT が有効 JSON なら既知ノイズとして扱う。

3. MWSE ログコピー（`mwse_<timestamp>.log`）
  - `handle method:` と HTTP status（`success: 200` / `json error: 400` など）でサーバー側処理を照合する。
  - `tools/list` の公開名が `mw_` プレフィックス付きで返っているか確認する。

4. screenshot 検証
  - 画像 blob は全量を読まず、`mimeType`、blob の長さ、base64 先頭シグネチャを確認する。
  - PNG の正常系シグネチャは `iVBORw0KGgoA`。
