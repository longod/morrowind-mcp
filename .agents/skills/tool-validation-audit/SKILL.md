---
name: tool-validation-audit
user-invocable: true
summary: Morrowind MCP の tool ごとに inputSchema 以外の追加 validation が必要か点検し、必要なら実装とテストを追加します。
description: |
  Morrowind MCP の `MWSE/mods/morrowind-mcp/tools/*.lua` を対象に、tool ごとに追加 validation が必要か検査し、必要なら `Validate`、共通 validator、UnitWind テストを追加するスキルです。

  inputSchema で判定できる type / required / enum / min/max / additionalProperties / default normalization と、schema だけでは判定できない cross-field 条件、sink safety、runtime state を切り分けます。

  トリガー例: "toolsごとに追加validationが必要か見て", "tool validation audit", "inputSchemaでは足りないvalidationを追加", "Execute前に弾くべきtool引数を確認して実装"。
applyTo:
  - "MWSE/mods/morrowind-mcp/tools/**/*.lua"
  - "MWSE/mods/morrowind-mcp/core/inputvalidator.lua"
  - "MWSE/mods/morrowind-mcp/tests/**/*.lua"
---

# tool-validation-audit

## 使う場面
- `tools/*.lua` の各 tool について、`inputSchema` だけで十分か確認するとき。
- `Execute` 内にある引数チェックを `Validate` に移せるか判断するとき。
- file name、resource URI、UI text、cross-field 条件など、tool 固有の追加 validation を追加するとき。
- schema default normalization 後の `Execute(arguments, context)` 前提で tool 実装を見直すとき。

## 必ず読むもの
1. `.github/instructions/mwse.instructions.md` を読み、Lua コメント、命名、PowerShell-only、core の MWSE 非依存ルールに従う。
2. validation を追加する場合は `MWSE/mods/morrowind-mcp/core/inputvalidator.lua` を読む。
3. tool のテストを追加・更新する場合は `unitwind-tests` スキルを使う。
4. テスト実行が必要な場合は `unittest-run` スキル、server 経路に影響する場合は `servertest-run` スキルを使う。

## 判定手順
1. 対象 tool を決める。指定がなければ `MWSE/mods/morrowind-mcp/tools/*.lua` を一覧し、各 tool の `inputSchema`、`Validate`、`Execute`、副作用先を確認する。
2. `inputSchema` で既に判定できるものを除外する。
   - object shape
   - required properties
   - unknown properties / `additionalProperties`
   - primitive type
   - enum / oneOf choices
   - string min/max length
   - number min/max
   - boolean type
   - schema `default` による top-level argument normalization
3. schema だけでは判定できず、`Validate` に追加すべきものを探す。
   - `menu_id` と `menu_name` のような排他、同時必須、条件付き必須などの cross-field 条件。
   - `action == "textInput"` のときだけ `text` が必要、などの conditional rule。
   - ファイル名、resource path / URI、UI text、log / response に入る user-controlled string などの sink safety。
   - 実行前に静的に判断でき、失敗時の副作用を避けられる constraint。
4. `Execute` に残すべきものを分離する。
   - 現在の UI tree、menu visibility / disabled、target existence。
   - keybinding lookup、input binding lookup。
   - file collision、runtime path creation、resource conversion failure。
   - `tes3` / `mge` / `lfs` など MWSE runtime 状態に依存する判定。
5. 追加 validation が必要な場合は、既存 helper を優先する。
   - `inputvalidator.ValidateSingleLineUiText`
   - `inputvalidator.ValidateFileName`
   - `inputvalidator.ValidateResourcePath`
   - `inputvalidator.ValidateResourceUri`
   - `base.Validate(self, params)`
6. 既存 helper で表現できない汎用 constraint は `core/inputvalidator.lua` に helper を追加する。ただし `core/` は MWSE に依存させない。
7. tool 固有の rule は該当 tool の `Validate` に追加し、まず `base.Validate(self, params)` の結果を確認してから追加エラーを積む。
8. `Execute` から重複する引数 validation を削除する。ただし runtime state check は削除しない。
9. `Execute` は `tools/call` 経由で normalize 済みの `arguments` を第一引数として受ける前提にする。直接 `Execute` 呼び出しをサポートするための `or {}` fallback は追加しない。

## 実装ルール
- `Validate` では `result.errors` に `{ path = "...", message = "..." }` を追加し、`result.valid = false` にする。
- tool の `Validate` は schema validation を再実装せず、必ず `base.Validate(self, params)` を使う。
- error message は英語で書く。
- user-controlled string を error/log/response に含める場合は、既存の escaping / formatting 方針を確認する。
- `inputSchema` で表現できる制約を tool 固有 `Validate` に重複実装しない。
- schema default で補完される値に対して `Execute` 側で `or defaultValue` を追加しない。
- コメントは非自明な判断、契約、sink safety、runtime check の理由に絞り、英語で書く。

## テスト方針
1. schema validator や共通 helper を変更した場合は `MWSE/mods/morrowind-mcp/tests/test_inputvalidator.lua` に UnitWind テストを追加する。
2. tool 固有 `Validate` を追加した場合は、該当 tool の validation path を UnitWind で確認する。既存の tool validation テストがある場合はそこへ追加する。
3. `tools/call` の normalize / validate / execute 順序に影響する場合は、HTTP server 経路のテストも確認する。
4. 変更後は `./tests/unit_test.ps1` を PowerShell で実行する。
5. MCP server の request/response や `tools/call` の挙動に影響する場合は `./tests/server_test.ps1` も実行する。

## 報告フォーマット
報告では次を簡潔にまとめる。
- 追加 validation が必要だった tool と理由。
- 追加しなかった tool と理由。特に「schema で判定済み」「nil が意味を持つ」「runtime check なので Execute に残す」を区別する。
- 変更したファイル。
- 実行したテストと結果。

## 完了条件
- 各対象 tool について、schema-covered / extra validation / runtime-only の切り分けができている。
- 必要な追加 validation が `Validate` または `core/inputvalidator.lua` に実装されている。
- 重複する `Execute` 引数 validation が残っていない。
- runtime state check は誤って削除されていない。
- UnitWind、必要に応じて server test が成功している。
