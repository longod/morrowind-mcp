---
name: unittest-run
user-invocable: true
description: Morrowind MCP の単体テストを実行し、 MWSE.log を確認してテストの成否を検証する。
---

# unittest-run

## 目的
- `tests/unit_test.ps1` を使って単体テストを実行する。
- Test Runner Agent の共通手順で `unit_test` summary を一次根拠として判定する。

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

## Suite-specific follow-up
- summary は `unitwind_<timestamp>.log` の `FAILED` と suite pass evidence を判定する。`failed` / `inconclusive` のときだけ、summary evidence の抽出結果と `mwse_<timestamp>.log` を読む。
- UnitWind の mock が通常ランタイムを壊していないことを確認する変更では、全 suite に `-VerifyRuntimeAfterTests` を付ける。個別 target とは併用できない。
- `start_server_mo2.ps1` の non-zero が最終終了コードへ影響し得るため、終了コードだけで失敗と断定しない。

