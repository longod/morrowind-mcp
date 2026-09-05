---
name: terrain-benchmark-run
user-invocable: true
description: |
  Morrowind MCP の terrain grid height source ベンチマークを tests/terrain_benchmark.ps1 で反復実行し、中央値 JSON、Inspector log、MWSE.log を確認する。"terrain benchmark", "terrain grid benchmark", "地形ベンチマーク", "任意の場所で terrain を計測" で使用する。
---

# terrain-benchmark-run

## Purpose

- `tests/terrain_benchmark.ps1` は terrain sampler の実装と layout を比較する実機ベンチマークである。既定ケースは mesh sampler の `64-64-aos/soa`、`128-128-aos/soa`、`256-128-aos/soa` と、production の heightfield sampler の `64-heightfield`、`128-heightfield`、`256-heightfield` である。`aos` は temporary vertices と completed triangles の両方を AoS、`soa` は両方を SoA とする。`heightfield` は land record の 65x65 height grid を直接参照し、triangle と bucket を構築しない。face-normal calculation は scalar に固定する。
- heightfield case の `sampler.triangle_count` と `bucket_*` は 0 になる。性能比較には `sampler.construction_elapsed_milliseconds` を使う。
- 既定では 1 回の warmup を除外し、同一 exterior cell で 5 回測定して中央値を出力する。
- 既定では Morrowind と server の起動、メインメニューの Continue、屋外セルでの測定、server 停止までをスクリプトが所有する。
- `-UseRunningServer` は、すでに起動済みのゲームでプレイヤーを任意の屋外地点へ移動した後に、ゲーム状態を変更せず測定するための明示的なモードである。
- 実行は Morrowind MCP Test Runner に委譲する。親エージェントは直接 PowerShell コマンドを実行しない。

## Default Run

リポジトリのルートから Test Runner に以下を実行させる。

```powershell
.\tests\terrain_benchmark.ps1
```

既定モードの確認事項:

1. Morrowind/server が未起動であること。起動済み server または server を公開していない Morrowind process が検出された場合、スクリプトは既存のゲームを停止しないため失敗する。
2. `start_server_mo2.ps1` により server が開始されること。
3. `mw-menu-action` で `Pete_ContinueButton` が操作され、保存済みゲームがロードされること。
4. player cell が exterior になること。
5. 全 benchmark case に samples、height metrics、sampler construction metrics が返ること。
6. 測定後、スクリプトが起動した Morrowind/server が `stop_server.ps1` により停止されること。

## Existing Server Run

プレイヤーを計測対象の屋外地点へ移動してから、ゲームを停止・操作しないで測定する場合のみ使う。

```powershell
.\tests\terrain_benchmark.ps1 -UseRunningServer
```

- このモードは server の起動、メインメニューの操作、foreground 化、停止を行わない。
- caller は Morrowind/server を起動済みにする。スクリプトは timeout まで active exterior cell を待機する。
- 測定後も Morrowind と server は実行中のままなので、必要なら caller が `tests/stop_server.ps1` を実行する。
- foreground 化が必要な入力は送らないため、`-NoForeground` は既定 lifecycle モードでのみ意味を持つ。

## Verification
テストスクリプトが生成する `terrain_benchmark` summary を一次根拠として判定する。summary は `result_<timestamp>.json` の `ready` state、全 benchmark case の `samples` と `height`、Inspector の non-zero exit を判定する。

共通のartifactとMWSE severityの規約は [test-run-summaries.md](../../../docs/test-run-summaries.md) を参照する。

`failed` / `inconclusive` の場合だけ、summary evidence の保存済み result/Inspector/MWSE artifact を読んで切り分ける。ライブ `MWSE.log` は読まない。

## Failure Triage

### Existing server is reachable

- 既定モードは既存ゲームを保護するため失敗する。
- 現在のゲーム位置を測定する意図なら `-UseRunningServer` を指定する。
- 新規の既定 lifecycle 実行が必要なら `tests/stop_server.ps1` で停止してから再実行する。

### Active exterior cell is required

- player が interior、メインメニュー、またはロード途中にいる。
- 両モードとも timeout まで exterior cell を待機する。保存地点が interior の場合は、屋外のセーブを使うか、待機中に屋外へ移動する。

### `mw-menu-action` is not published

- メインメニューの UI がまだ初期化されていないか、server がロード途中である。
- Inspector log と MWSE log を確認し、開始からの待機と tools/list の結果を確認する。

### Missing benchmark case result

- `terrain:GetQualityStatus` の失敗状態、timeout、case key の run 間不一致、または terrain source の runtime error を確認する。
- Inspector log の該当 `tools/call` 応答と MWSE log の `Terrain grid build stopped`、`Terrain quality comparison`、Lua traceback を確認する。

### Nonzero Inspector exit

- Inspector log の該当 `[RUN]` ブロックで stderr と JSON response を確認する。
- connection refused や timeout は `tests/stop_server.ps1` 後に再実行する。

## Measurement Notes

- 結果は地点依存である。異なる場所の比較では `cell_id`、測定日時、保存された JSON を必ず併記する。測定中に `cell_id` が変わる場合は benchmark が失敗する。
- `-RepeatCount` と `-WarmupCount` で測定回数を調整できる。中央値は `median`、全 run の生データは `runs` に保存される。
- `sampler.construction_elapsed_milliseconds` と総 `elapsed_milliseconds` を主な性能比較に用いる。heap delta は GC により負になり得るため補助指標である。
- `64-64` の height result は temporary reference surface との自己比較を含む。最終的な interval 決定には、独立した land-root ray reference と route-quality metrics が必要である。
- `elapsed_milliseconds` は builder の Step 作業時間の累積であり、フレーム間の待機時間を含まない。
- `memory_delta_kilobytes` は signed heap snapshot difference のため、garbage collection により負になり得る診断値である。
