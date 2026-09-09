---
name: game-progression-probe
user-invocable: true
description: "Start Morrowind from NEW GAME, discover how far current Morrowind MCP tools and resources can progress it, and emit an agent-readable, replayable JSON procedure. Use for game progression exploration, NEW GAME tool capability probes, or generating replay scenarios."
---

# Game Progression Probe

[ゲーム進行テスト](../../../docs/game-progression-testing.md) の契約に従う。

## Active Scenario Completion Contract

探索開始時に有効な scenario を一つ決める。明示的な scenario が指定されていない場合は、`tests/game_progression/unit/fixtures/scenario.json` を使用し、明示指定がある場合はその scenario を使用する。有効な scenario の `completion_goal`、完了に必要な全 milestone、各 milestone の `evidence`、および完了確認用 assertion を、この探索の受入条件として扱う。途中の場所到着、個別操作の成功、または一つの状態変化だけで completion goal を狭めない。`character_generation`、`ready`、`finished`、cell 名、特定の UI 文言などを skill や runner の共通条件として仮定せず、具体的な条件は有効な scenario から得る。

## Progression Exploration Mode

1. 自立レベル4のMorrowind MCP Playerを使用する。`tests/start_server_mo2.ps1 -WaitForServer` で起動し、タイムアウトは起動失敗とする。`tests/logs/game_progression/` に実行ディレクトリを作成する。
2. 最初のMCP操作前に、`tests/mcp_discover.ps1 -OutputPath <run-directory>/initial-discovery.json` を実行する。現在の `tools/list`、`resources/list`、UIを確認する。promptsは無視し、過去の実行で観測したselector、待機条件、capabilityを再利用しない。
3. 観測したメニューからNEW GAMEを選ぶ。saveをloadしない。利用可能なtoolまたはresourceを変え得る状態変更操作の前には、`-WatchSeconds` のdiscovery watcherを実行する。watcherが使えない場合は、操作後に新しいdiscovery snapshotを取得して記録する。
4. NEW GAMEでゲーム状態が生成されたら、現在のUIと状態を観測し、候補toolに対して `mw-capabilities-fetch` を呼び、`morrowind://memory/index.json` を読む。関連するplayer、journal、quest、actor、dialogue、notification、objectiveの `links` を辿る。根拠、指示、目的、候補、判断をassessmentに記録する。Memory、UI、状態、capabilityは相互に補う証拠として扱い、空または取得不能なMemoryも黙って無視せず記録する。
5. 観測、assessment、操作、再観測を一手ずつ繰り返す。各assessmentでは、現在の目的・進行状態・未達milestoneをSituation、観測事実と推論を分けた根拠をEvidence、現在観測できる対象・場所・公開toolに限った複数の候補をCandidate actions、選んだ候補と期待するmilestone・再観測条件をDecisionとして記録する。操作の待機条件は、その操作で期待する状態変化に対応させる。NPC発話、notification、questまたはcellの変化、曖昧な結果の後は、関連する証拠を再読する。notificationの`text`は意味のある根拠として扱うが、`source_menu`と`event`は出所情報としてのみ扱う。subscriptionが利用可能な場合は、現在必要なresourceだけを購読する。
	- プレイヤーをNPC、reference、または観測済み座標へ移動させる場合は、まず`mw-route-navigate`を候補にし、到達後の位置・距離・対象を再観測する。`mw-player-action`による前後左右移動を第一候補にしてはならない。
	- `mw-player-action`は、メニュー操作・activateなどの入力、`mw-route-navigate`が公開されていない場合、navigateが失敗または経路未解決になった場合、または最後の微調整に限定する。fallbackを選んだ理由をassessmentに記録する。
6. 状態変更操作の後は、操作結果だけで完了・失敗を判断せず、関連するfetch tool/resourceを再取得して操作前との差分と期待した状態変化を確認する。UI、notification、player、actor、reference、world、cell、inventory、journal、questなど、操作に関係する複数の観測を組み合わせる。
7. 意味のある状態変化後と、危険・曖昧・終端の操作前に `mw-screenshot-save capture_with_ui=true` を取得する。成功した操作を、intent、operation、assertions、wait、observations、assessment、screenshots、notesを含むschema version 1 JSONとして `tests/logs/game_progression/` に記録する。

## 終了前チェック

探索を終了または terminal state として記録する前に、次のチェックを順番に実施する。

1. 端末状態を決める前に、必ず有効な scenario の完了確認を実施する。Memory が公開されていれば index と完了判断に関係する公開 link を live read し、UI・player・world・reference など scenario が指定する read-only の検証操作を再取得する。各完了 assertion と各 milestone の evidence を現在の観測で照合し、前の step の成功応答や古い観測だけで代用しない。状態変更を伴う完了確認操作は再実行せず、現在の状態を読む操作へ置き換える。
2. 完了確認の結果を terminal gate として扱う。全ての必須 milestone と完了 assertion が成功した場合だけ `completed` を報告する。一つでも未確認、失敗、取得不能、または scenario と現在状態が矛盾する場合は `completed` にせず、未達条件と最終観測を記録して探索を継続する。
3. `stalled` または `failed` として終了する場合も、まず terminal gate の結果を記録し、未実行候補の除外理由と最終 assessment を残す。繰り返し観測しても milestone がなく、新しい capability がなく、合理的な candidate action がない場合だけ `stalled` とする。公開されていれば、`mw-debug-action` で `memory:SaveDebugDocuments` を一度だけ呼び、結果と `<Paths.modDataDir>\memory-dump` を記録してからサーバーを停止する。
4. `tests/game_progression/run.py --validate-only` で scenario の構造を検証する。これはゲーム進行の完了判定ではない。terminal gate の実行と completion goal の達成確認を別途行い、全条件が成功した場合だけ `completed` を報告する。scenario の条件を満たす前に進行条件を満たせなくなった場合は、前項の `stalled` 条件を満たすまで `stalled` と報告してはならない。最終報告には completion goal、達成済み milestone、未達 milestone、terminal gate の各結果、最終観測を含める。
5. 再生終了時は、ほかのテストと同じように Morrowind 停止後の `MWSE.log` を実行ディレクトリへコピーする。成果物は `run.json` と `MWSE.log` とし、ログが存在しない場合やコピーに失敗した場合は警告を記録する。

## 再生

決定的再生には `tests/game_progression/run.py --scenario <scenario.json>` を使用する。runnerは記録済みの操作とassertionを実行し、bootstrap経路を再探索しない。探索成功後に再生が失敗した場合は、観測条件を弱めずscenario contractまたはrunnerを改善する。

