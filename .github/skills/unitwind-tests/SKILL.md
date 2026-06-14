---
name: unitwind-tests
user-invocable: true
summary: このプロジェクトの UnitWind で Lua 単体テストを作成または拡張します。
description: |
  このスキルは、Morrowind MCP リポジトリ内で `unitwind` を使用した Lua 単体テストを追加・更新する際に使います。
  適切なテストファイルを探し、既存の UnitWind スタイルを維持しつつ、対象関数に対する集中したテストケースを追加します。
  
  対象は `MWSE/mods/morrowind-mcp` 配下の Lua テストファイルです。
  
  "unit testはunitwindを使用する" や "UnitWind のテストを追加" といった指示で有効です。
  
  このスキルは `unitwind` を前提としており、別のテストフレームワークは導入しません。
applyTo:
  - "MWSE/mods/morrowind-mcp/tests/**/*.lua"
  - "MWSE/mods/morrowind-mcp/**/*.lua"
---

# `unitwind-tests` スキル

## 使う場面
- `MWSE/mods/morrowind-mcp/tests/` に Lua 単体テストを追加・拡張するとき
- 既存の `unitwind` の書式に沿ったテストを作成するとき
- 単一の関数やモジュールに絞ったテストを追加するとき

## このスキルで行うこと
1. 関連するテストファイルを特定し、必要なら新規作成します。
2. 既存の `unitwind` テスト構造を読み取ります。
3. `unitwind:test(...)` ブロックを追加または更新します。
4. `unitwind:expect(...)` を使い、別のフレームワークは導入しません。
5. 関連のないコードは変更しません。

## 例となるプロンプト
- "unit testはunitwindを使用する"
- "`SomeMethod` のテストを追加してください"
- "`some.lua` の関数を UnitWind でテストする"

## 注意点
- 既存の `RunTest()` や `UnitWind.new()` 構造の中にテストを追加することを優先します。
- 新しいテストフレームワークは導入しません。
- リポジトリ固有の規約は `.github/instructions/mwse.instructions.md` に従います。
