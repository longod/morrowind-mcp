---
name: game-progression-probe
user-invocable: true
description: "Start Morrowind from NEW GAME, discover how far current Morrowind MCP tools and resources can progress it, and emit an agent-readable, replayable JSON procedure. Use for game progression exploration, NEW GAME tool capability probes, or generating replay scenarios."
---

# Game Progression Probe

[ゲーム進行テスト](../../../docs/game-progression-testing.md) の契約に従う。

## Progression Exploration Mode

1. 自立レベル4のMorrowind MCP Playerを使用する。`tests/start_server_mo2.ps1 -WaitForServer` で起動し、タイムアウトは起動失敗とする。`tests/logs/game_progression/` に実行ディレクトリを作成する。
2. 最初のMCP操作前に、`tests/mcp_discover.ps1 -OutputPath <run-directory>/initial-discovery.json` を実行する。現在の `tools/list`、`resources/list`、UIを確認する。promptsは無視し、過去の実行で観測したselector、待機条件、capabilityを再利用しない。
3. 観測したメニューからNEW GAMEを選ぶ。saveをloadしない。利用可能なtoolまたはresourceを変え得る状態変更操作の前には、`-WatchSeconds` のdiscovery watcherを実行する。watcherが使えない場合は、操作後に新しいdiscovery snapshotを取得して記録する。
4. NEW GAMEでゲーム状態が生成されたら、現在のUIと状態を観測し、候補toolに対して `mw-capabilities-fetch` を呼び、`morrowind://memory/index.json` を読む。関連するplayer、journal、quest、actor、dialogue、notification、objectiveの `links` を辿る。根拠、指示、目的、候補、判断をassessmentに記録する。Memory、UI、状態、capabilityは相互に補う証拠として扱い、空または取得不能なMemoryも黙って無視せず記録する。
5. 観測、assessment、操作、再観測を一手ずつ繰り返す。各assessmentでは、現在の目的・進行状態・未達milestoneをSituation、観測事実と推論を分けた根拠をEvidence、現在観測できる対象・場所・公開toolに限った複数の候補をCandidate actions、選んだ候補と期待するmilestone・再観測条件をDecisionとして記録する。操作の待機条件は、その操作で期待する状態変化に対応させる。NPC発話、notification、questまたはcellの変化、曖昧な結果の後は、関連する証拠を再読する。notificationの`text`は意味のある根拠として扱うが、`source_menu`と`event`は出所情報としてのみ扱う。subscriptionが利用可能な場合は、現在必要なresourceだけを購読する。
	- プレイヤーをNPC、reference、または観測済み座標へ移動させる場合は、まず`mw-player-navigate`を候補にし、到達後の位置・距離・対象を再観測する。`mw-player-action`による前後左右移動を第一候補にしてはならない。
	- `mw-player-action`は、メニュー操作・activateなどの入力、`mw-player-navigate`が公開されていない場合、navigateが失敗または経路未解決になった場合、または最後の微調整に限定する。fallbackを選んだ理由をassessmentに記録する。
6. 意味のある状態変化後と、危険・曖昧・終端の操作前に `mw-screenshot-save capture_with_ui=true` を取得する。成功した操作を、intent、operation、assertions、wait、observations、assessment、screenshots、notesを含むschema version 1 JSONとして `tests/logs/game_progression/` に記録する。
7. 繰り返し観測してもmilestoneがなく、新しいcapabilityがなく、SituationとEvidenceから導いた合理的なCandidate actionsを評価しても候補がない場合だけ `stalled` を報告する。`stalled` または `failed` の前に、未実行候補の除外理由を含む証拠と最終assessmentを記録する。公開されていれば、`mw-debug-action` で `memory:SaveDebugDocuments` を一度だけ呼び、結果と `<Paths.modDataDir>\memory-dump` を記録してからサーバーを停止する。
8. `completed` は、個別のtool操作やscenario JSONの構造検証が成功しただけでは報告しない。探索開始時にcompletion goalと、そこへ至る複数の必須milestoneを定義し、各milestoneについて操作後の観測assertionが成功した場合だけ達成済みとする。必須milestoneが一つでも未達なら `completed` と報告せず、探索を継続する。
9. `tests/game_progression/run.py --validate-only` でscenarioの構造を検証する。これはゲーム進行の完了判定ではない。必須milestoneの全assertion、最終状態の再観測、completion goalの達成を確認した場合だけ `completed` を報告する。全milestoneを達成する前に進行条件を満たせなくなった場合は、手順7の条件を満たすまで `stalled` と報告してはならない。最終報告にはcompletion goal、達成済みmilestone、未達milestone、最終観測を含める。

## 再生

決定的再生には `tests/game_progression/run.py --scenario <scenario.json>` を使用する。runnerは記録済みの操作とassertionを実行し、bootstrap経路を再探索しない。探索成功後に再生が失敗した場合は、観測条件を弱めずscenario contractまたはrunnerを改善する。

