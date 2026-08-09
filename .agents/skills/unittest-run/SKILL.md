---
name: unittest-run
user-invocable: true
description: Morrowind MCP の単体テストを実行し、 MWSE.log を確認してテストの成否を検証する。
---

# unittest-run

## 目的
- `tests/unit_test.ps1` を使って単体テストを実行する。
- `MWSE.log` でテスト結果を検証する。

## 使用タイミング
- 単体テストスクリプトの実行を求められたとき。

## 手順
1. ワークスペースのルートから以下を実行する。相対パスを使うため、カレントディレクトリの移動は不要です。

```powershell
.\tests\unit_test.ps1
```

2. 個別のテストファイルだけを実行したい場合は、ファイル名を引数で渡す。

```powershell
.\tests\unit_test.ps1 test_jsonrpc.lua test_http.lua
```

3. 引数で指定したファイル名は `.unit-test-targets` に書き込まれ、そのファイルだけが実行される。

4. 引数を付けずに実行した場合は、`.unit-test-targets` は空になり、全テストが実行される。

5. UnitWind の共有 API mock が通常ランタイムを壊していないことを確認する場合だけ、次を実行する。この opt-in mode は sentinel を作らず、全テスト後に MCP server の起動を待機してから Morrowind を停止するため、通常の単体テストより時間がかかる。

```powershell
.\tests\unit_test.ps1 -VerifyRuntimeAfterTests
```

6. 実行直後に保存先の timestamp を取り、次を実行する。

```powershell
.\tests\summarize_test_runs.ps1 -TestType unit_test -RunTimestamp YYYYMMDD_HHMMSS
```

7. `tests/logs/unit_test/summary_<timestamp>.json` の `status` を主な結果として報告する。`passed` は suite pass と UnitWind evidence、`failed` は `FAILED`、証拠不足は `inconclusive` である。

8. `failed` / `inconclusive` のときだけ summary の `evidence` が示す抽出結果と同 timestamp の `mwse_<timestamp>.log` を確認する。ライブ `MWSE.log` は読まない。

9. 必要なら追加規則を明示 source 付きで加える。例: `-RequirePattern 'primary:MORROWIND-MCP\\.JSONRPC' -ForbidPattern 'mwse:traceback'`。規則は加算のみで、既定の failed/inconclusive を passed にしない。

10. 抽出結果ファイルと `MWSE.log` コピーの命名は次のとおり。
	- 抽出結果: `tests/logs/unit_test/unitwind_YYYYMMDD_HHMMSS.log`
	- `MWSE.log` コピー: `tests/logs/unit_test/mwse_YYYYMMDD_HHMMSS.log`

## Notes
- ログの `[UnitWind]` で始まる行が単体テストの出力である。
- `MORROWIND-MCP.JSONRPC PASSED` / `MORROWIND-MCP.HTTP PASSED` / `MORROWIND-MCP.STRUTIL PASSED` のような suite 単位の PASS 行を確認する。
- UnitWind は `unitwind:finish()` の内部で `reset()` を呼び、`testsPassed/testsFailed` を 0 に戻す。
- そのため各 `test_*.lua` では、`finish()` の前に `testsPassed/testsFailed` をローカル変数へ退避して返す。
- 新規テスト追加時も同じパターンを使う。
- `unittest.lua` は各テストモジュールの戻り値を集計するため、`Unit test <file> passed: tests_passed=<n> tests_failed=<n>` の行で件数が正しく出ていることを確認する。
- `tests_passed=0 tests_failed=0` が並ぶ場合は、`test_*.lua` 側が `finish()` 後の値を直接返していないか確認する。
- 回帰切り分けのために `test_*.lua` の UnitWind 設定を `enabled = false` にした場合も `tests_passed=0 tests_failed=0` になる。意図した一時無効化か、値の退避漏れかを区別して確認する。
- 抽出対象パターンは `\[UnitWind\]|MORROWIND-MCP\..*(PASSED|FAILED)` である。
- `FAILED` 行が抽出されると、`tests/unit_test.ps1` は non-zero を返す。
- ただし、`start_server_mo2.ps1` が non-zero の場合も最終終了コードは non-zero になる。
- MCP schema generator を追加・変更した場合は、`StringSchema`, `NumberSchema`, `BooleanSchema`, `ConstTitle`, enum schema, multi-select schema の UnitWind テストが `MWSE.log` に PASS として出ていることを確認する。
- Tool prefix 処理を変更した場合は、`Tool generator applies configured primitive prefixes` と `Tool generator keeps nil title and description with prefixes` の PASS を確認する。

