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

5. `MWSE.log` を確認する。

6. `MWSE.log` からテスト結果を抽出する。

7. 抽出結果ファイルと `MWSE.log` コピーを確認する。
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
- 抽出対象パターンは `\[UnitWind\]|MORROWIND-MCP\..*(PASSED|FAILED)` である。
- `FAILED` 行が抽出されると、`tests/unit_test.ps1` は non-zero を返す。
- ただし、`start_server_mo2.ps1` が non-zero の場合も最終終了コードは non-zero になる。
- MCP schema generator を追加・変更した場合は、`StringSchema`, `NumberSchema`, `BooleanSchema`, `ConstTitle`, enum schema, multi-select schema の UnitWind テストが `MWSE.log` に PASS として出ていることを確認する。
- Tool prefix 処理を変更した場合は、`Tool generator applies configured primitive prefixes` と `Tool generator keeps nil title and description with prefixes` の PASS を確認する。

