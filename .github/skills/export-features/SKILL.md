---
name: export-features
user-invocable: true
description: |
  Lua実装から MCP の */list で実行可能な機能を抽出し、prompts/resources/tools ごとに Markdown へ整理する。
  「余計な情報を書かない」「Name, Description の一覧のみ」に限定した出力が必要なときに使う。
  トリガー例: "*/list だけ調べる", "prompts/resources/tools を分けて Name/Description 一覧化", "LuaからMCP機能を抽出して最小表で出力"。
---

# export-features

## 使う場面
- Lua実装を根拠に、MCPクライアントで実行可能な `*/list` 機能だけを報告するとき
- `prompts` / `resources` / `tools` を分けて一覧化するとき
- 出力を `Name`, `Description` のみへ厳密に絞るとき

## 手順
1. サーバー起動経路を確認し、実際に使われるサーバー実装ファイルを特定する。
2. サーバー実装から `methodHandlers` を確認し、実行可能な `*/list` メソッドのみ抽出する。
3. `prompts`, `resources`, `tools` のロード元を確認し、実ファイルから `definition.name`, `definition.description` を収集する。
4. Markdownを3セクションに分けて出力する。
- Prompts:`prompts/list`
- Resources:`resources/list`
- Tools:`tools/list`
5. 各セクションは、要素がある場合のみ表形式で `Name`, `Description` を書く。

## 分岐ルール
- `mcp.lua` などの定義ファイルにメソッド名があっても、サーバーの `methodHandlers` に未登録なら除外する。
- `definition.description` が無い場合は空欄にする。推測で補完しない。
- 対象カテゴリに要素が無ければ、見出しのみを出力し、表は出さない。

## 完了条件
- `prompts/resources/tools` の3区分で整理されている。
- 記載項目は `Name` と `Description` のみ。
- 取得できた実データのみ記載され、実装説明・補足・推測が混ざっていない。

## 例プロンプト
- LuaからMCPの `*/list` で実行できる機能だけ抽出して、prompts/resources/tools ごとに `Name`, `Description` 表でまとめて。
- 余計な説明なしで、`tools/list` の実データを `Name`, `Description` 一覧にして。
