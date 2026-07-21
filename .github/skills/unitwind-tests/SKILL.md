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
4. 必要に応じて `unitwind:spy()` や `unitwind:mock()` を使用します。
5. `unitwind:expect(...)` を使い、別のフレームワークは導入しません。
6. 関連のないコードは変更しません。

## 例となるプロンプト
- "unit testはunitwindを使用する"
- "`SomeMethod` のテストを追加してください"
- "`some.lua` の関数を UnitWind でテストする"

## 注意点
- テスト対象のファイルと同名が `test_` の後にあるテストファイルがあれば、そこにテストを追加することを優先します。
- テストファイルは `dofile` で呼び出されてテストされるため、`function this.Test()` 関数内に追加・更新します。
- 戻り値は `---@return MCP.UnitWindResult` で、 `return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }` を返すようにします。
- 新しいテストフレームワークは導入しません。
- リポジトリ固有の規約は `.github/instructions/mwse.instructions.md` に従います。

## Mock 方針（UnitWind）
- MUST: 依存の差し替えは対象テーブルのメンバーに対して `unitwind:mock(table, member, value_or_fn)` を使う。
- MUST: すべての mock は同一テスト内で `unitwind:unmock(table, member)` まで行う。
- NEVER: 初手で `_G` 全体差し替えを選ばない。
- `_G` 差し替えは最終手段。メンバー単位 mock が不可能な場合のみ許可する。
- 手動代入・手動復元（`tes3 = ...` / `tes3 = originalTes3`）は使わない。

### 実装前チェック（必須）
- メンバー単位 mock で実現できるか確認した。
- 追加するすべての mock に対応する unmock を書いた。
- `_G` 差し替えが必要な場合は理由をテストコメントに1行で残した。
