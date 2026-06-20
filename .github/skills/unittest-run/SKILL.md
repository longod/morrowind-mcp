---
name: unittest-run
user-invocable: true
description: Morrowind MCP の単体テストを実行し、 MWSE.log を確認してテストの成否を検証する。
---

# unittest-run

## 目的
- `tests/unittest.ps1` を使って単体テストを実行する。
- `MWSE.log` でテスト結果を検証する。

## 使用タイミング
- 単体テストスクリプトの実行を求められたとき。

## 手順
1. ワークスペースのルートから実行する。

```powershell
pwsh -File tests/unittest.ps1
```

2. `MWSE.log` を確認する。

3. `MWSE.log` からテスト結果を抽出する。

## Notes
- ログの `[UnitWind]` で始まる行が単体テストの出力である。

