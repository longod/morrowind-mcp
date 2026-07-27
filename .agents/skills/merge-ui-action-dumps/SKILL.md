---
name: merge-ui-action-dumps
user-invocable: true
description: |
  MWSE.log や tests/logs から `Observed UI action hints for static list:` の dump を探し、`MWSE/mods/morrowind-mcp/util/ui_action.lua` の `staticHints` に重複なくマージする。
  トリガー例: "ui_action dumpをstaticHintsにマージ", "ログからObserved UI action hintsを取り込む", "FormatObservedHintsForStaticListの出力を反映"。
---

# merge-ui-action-dumps

## 使う場面
- `MWSE.log` に出力された `Observed UI action hints for static list:` を `staticHints` に取り込むとき
- `tests/logs/server_test` や `tests/logs/unit_test` のログコピーから UI action hint dump を回収するとき
- `FormatObservedHintsForStaticList()` の出力を手作業ではなく、既存リストと照合して安全にマージするとき

## 対象ファイル
- dump 探索元:
  - ユーザーが指定した `MWSE.log`
  - [tests/logs/server_test](../../../tests/logs/server_test)
  - [tests/logs/unit_test](../../../tests/logs/unit_test)
- 反映先:
  - [MWSE/mods/morrowind-mcp/util/ui_action.lua](../../../MWSE/mods/morrowind-mcp/util/ui_action.lua)

## 手順
1. 最新の [MWSE/mods/morrowind-mcp/util/ui_action.lua](../../../MWSE/mods/morrowind-mcp/util/ui_action.lua) を読む。
   - ユーザーや formatter が直前に編集している可能性があるため、編集前に必ず現在内容を確認する。
2. dump 探索元を決める。
   - ユーザーがログファイルを添付または指定している場合はそれを優先する。
   - 指定がない場合は `tests/logs/server_test` の新しい `mwse_*.log` を優先し、必要なら `tests/logs/unit_test` も確認する。
3. ログから次のヘッダーを探す。
   - `Observed UI action hints for static list:`
4. ヘッダー直後の Lua table row だけを抽出する。
   - 対象行の形式は原則として次の形:
     ```lua
     { path = "...", properties = { "mouseClick" }, name = "..." },
     ```
   - 次のログ行、空行、または別モジュールの `[morrowind-mcp ...]` 行に到達したら block 終了とみなす。
5. 抽出した row をレビューして、明らかなテスト用データを除外する。
   - `MenuCustom`, `MenuDump`, `Test`, `Dummy` など、UnitWind 用 fake path は `staticHints` に入れない。
   - `id`, `observed`, `type` は static hint に含めない。
   - `path`, `properties`, `name` だけを保持する。
6. 既存の `staticHints` と `path` で照合する。
   - 同じ `path` がない場合は新規 row として追加する。
   - 同じ `path` がある場合は `properties` を和集合にする。
   - 既存の `properties` の順序を優先し、dump 由来の新しい property は末尾へ追加する。
   - 同じ property を重複追加しない。
7. `staticHints` の並びは読みやすさを優先し、基本的に `path` の昇順または既存カテゴリの近くに置く。
   - 大量追加時は `path` 昇順にそろえる。
   - 小規模追加時は同じ menu root の近くに置く。
8. [MWSE/mods/morrowind-mcp/util/ui_action.lua](../../../MWSE/mods/morrowind-mcp/util/ui_action.lua) を `apply_patch` で編集する。
   - ログ dump をそのまま丸ごと貼らず、重複排除と property merge 後の row だけ反映する。
   - 関係ない整形やリファクタは行わない。
9. 検証する。
   - diagnostics で [MWSE/mods/morrowind-mcp/util/ui_action.lua](../../../MWSE/mods/morrowind-mcp/util/ui_action.lua) を確認する。
   - [tests/unit_test.ps1](../../../tests/unit_test.ps1) を実行し、`morrowind-mcp.util.ui_action` が PASS していることを確認する。
   - `unit_test.ps1` は MO2 起動戻り値により exit code 1 でも、抽出された UnitWind 結果が PASS の場合がある。ログ内容で判定する。

## マージルール
- 正とするキーは `path`。
- `name` は補助情報として保持するが、重複判定には使わない。
- `properties` は `tes3.uiProperty` の enum name 文字列配列として保持する。
- `mouseOver`, `mouseLeave`, `mouseDown` など、`ui_action.lua` 側で actionable から除外されている property は dump に通常出ない。見つかった場合は取り込む前に実装とログの整合性を確認する。
- `keyPress` など複数 property が見つかった場合は、同一 path の `properties` 配列に追加する。
- runtime ID は不安定なので絶対に保存しない。
- `observed = true` は runtime 状態なので static hint へは書かない。

## 注意点
- UnitWind の fake UI path は実プレイ用 static hint に混ぜない。
- dump は `development.debug` 時だけ出る想定なので、ログにない場合は設定と `menuExit` 発火タイミングを確認する。
- `FormatObservedHintsForStaticList()` の出力は候補であり、無条件に正とは扱わない。menu root と path が実 UI に由来することを確認する。
- `staticHints` を更新した後、テストで登録した observed hint が残らないように [test_util_ui_action.lua](../../../MWSE/mods/morrowind-mcp/tests/test_util_ui_action.lua) の `ClearObservedHints()` 呼び出しを維持する。

## 完了条件
- dump から有効な UI action hint が抽出されている。
- test-only/fake path が除外されている。
- `staticHints` は `path` 重複なしで更新されている。
- 既存 path の `properties` は重複なしでマージされている。
- diagnostics が通っている。
- UnitWind の `morrowind-mcp.util.ui_action` が PASS している。

## 例プロンプト
- `MWSE.log` の `Observed UI action hints for static list:` を探して `staticHints` にマージして。
- 最新の server_test ログから UI action dump を取り込んで。
- `FormatObservedHintsForStaticList` の出力を `ui_action.lua` に重複なしで反映して。
