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

2. `MWSE.log` を確認する。

3. `MWSE.log` からテスト結果を抽出する。

4. 抽出結果ファイルと `MWSE.log` コピーを確認する。
	- 抽出結果: `tests/logs/unit_test/unitwind_YYYYMMDD_HHMMSS.log`
	- `MWSE.log` コピー: `tests/logs/unit_test/mwse_YYYYMMDD_HHMMSS.log`

## Notes
- ログの `[UnitWind]` で始まる行が単体テストの出力である。
- `MORROWIND-MCP.JSONRPC PASSED` / `MORROWIND-MCP.HTTP PASSED` / `MORROWIND-MCP.STRUTIL PASSED` のような suite 単位の PASS 行を確認する。
- 抽出対象パターンは `\[UnitWind\]|MORROWIND-MCP\..*(PASSED|FAILED)` である。
- `FAILED` 行が抽出されると、`tests/unit_test.ps1` は non-zero を返す。
- ただし、`start_server_mo2.ps1` が non-zero の場合も最終終了コードは non-zero になる。
- MCP schema generator を追加・変更した場合は、`StringSchema`, `NumberSchema`, `BooleanSchema`, `ConstTitle`, enum schema, multi-select schema の UnitWind テストが `MWSE.log` に PASS として出ていることを確認する。
- Tool prefix 処理を変更した場合は、`Tool generator applies configured primitive prefixes` と `Tool generator keeps nil title and description with prefixes` の PASS を確認する。

