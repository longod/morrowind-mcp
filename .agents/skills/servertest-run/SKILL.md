---
name: servertest-run
user-invocable: true
description: |
  Morrowind MCP のサーバーのテストを行う。出力と MWSE.log を確認してテストの成否を検証する。
---

# servertest-run

## Purpose
- `tests/server_test.ps1` は integration test として扱う。
- Test Runner Agent の共通手順で `server_test` summary を一次根拠として判定する。

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

# Inspector集約ログのJSONを整形しない
.\tests\server_test.ps1 -Unpretty
```

`-NoForeground` を指定すると、接続確認後のフォアグラウンド化ステップをスキップする。
バックグラウンドではキーボードのキー入力やマウスのボタン入力（mw-player-action など）が送られないため、入力を使う検証ではフォアグラウンド化する必要がある。入力送信が不要な検証では `-NoForeground` で実行してよい。
Inspector集約ログのJSONは既定でpretty-printされる。エージェントが機械的にログを処理する必要がある場合のみ、`-Unpretty` を指定してInspectorの1行JSONを保存してよい。
自動 foreground 化は best effort であり、ロードされるセーブ内容や実際のウィンドウ状態に依存するため、`tests/server_test.ps1` は target/activate/MenuDialog への到達を必須にしない。会話 actor まで到達したかは、実行後の `MWSE.log` と `tests/validate_memory_dump.ps1` の `conversationActors` 集計で判断する。

## Suite-specific follow-up
- summary の `skipped` case は失敗ではない。counts と case 名を報告し、想定外の skip の場合だけ evidence の Inspector/MWSE コピーで状態依存か回帰かを調べる。
- Memory schema、リンク、debug dump、actor interaction を変更した場合だけ、`./tests/validate_memory_dump.ps1` を追加実行する。通常の server test 合否とは別に報告する。
  - `tests/server_test.ps1` は `mw-debug-action action=memory:SaveDebugDocuments` を実行するが、`tests/validate_memory_dump.ps1` は自動実行しない。
  - 出力の `conversationActors` は、debug dump 成果物上で `target -> activate -> MenuDialog` まで到達した actor 数を表す。セーブ内容や foreground 状態に依存するため、通常の server test 合否とは分けて読む。

## Notes
- `tests/server_test.ps1` は最新版の `@modelcontextprotocol/inspector` を使用し、起動時に解決したInspector versionが2以上であることを確認してコンソールと集約ログへ出力する。Inspector v2はNode.js 22.19.0以上を必要とする。
- `tests/server_test.ps1` は Inspector の応答を保存し、終了時に `MWSE.log` を同じ timestamp のコピーとして保存する。ライブ `MWSE.log` は読まない。
- `start_server_mo2.ps1` が non-zero でも Morrowind が起動済みの場合がある。connection refused / timeout は `tests/stop_server.ps1` 後の再実行で切り分ける。

## Failure Triage
失敗時は次の順で確認する。

1. コンソール要約
  - `[FAILED]` の直後に表示されるエラー要点を確認する。
  - `fetch failed` / connection refused / timeout の場合は `tests/stop_server.ps1` 実行後に再試行する。

2. summary evidence の Inspector 集約ログ
  - 該当 `[RUN] ...` ブロックの `[EXIT]`、`--- STDERR ---`、`--- STDOUT ---` を確認する。
  - blobを含む画像resource応答は、URI / MIME type / blob lengthの要約として保存される。

3. summary evidence の MWSE ログコピー
  - `handle method:` と HTTP status（`success: 200` / `json error: 400` など）でサーバー側処理を照合する。

4. screenshot 検証
  - 画像 blob は全量を読まず、`mimeType`、blob の長さ、base64 先頭シグネチャを確認する。
  - PNG の正常系シグネチャは `iVBORw0KGgoA`。
