---
name: export-features
user-invocable: true
description: |
  Lua実装から MCP の */list で実行可能な機能を抽出し、prompts/resources/tools ごとに Markdown へ整理する。
  トリガー例: "*/list だけ調べる", "prompts/resources/tools を分けて Name/Title/Description 一覧化", "LuaからMCP機能を抽出して最小表で出力"。
---

# export-features

## 使う場面
- Lua実装を根拠に、MCPクライアントで実行可能な `*/list` 機能だけを報告するとき
- `prompts` / `resources` / `tools` を分けて一覧化するとき

## 手順
1. サーバー起動経路を確認し、実際に使われるサーバー実装ファイルを特定する。
2. サーバー実装から `methodHandlers` を確認し、実行可能な `*/list` メソッドのみ抽出する。
3. `prompts`, `resources`, `tools` のロード元を確認し、実ファイルから `definition.name`, `definition.title`, `definition.description` を収集する。
 - `resources` は `resources/list` の結果に加えて、`PublishResource` で登録されるリソースを列挙対象に含める。
 - `resources` は `uri` も収集する。
 - `definition` が generator 経由（例: `jsonrpc.Tool(...)`）の場合は、generator 内の変換処理と事前設定（例: `SetPrimitivePrefix`）を追跡し、`Name` は最終公開値を採用する。
 - `Title`, `Description` は常に prefix 適用前の値を採用する（例: `[Morrowind] ` を除去する）。
4. [FEATURES.md](../../../FEATURES.md) にMarkdownを3セクションに分けて出力する。
- `prompts/list` -> `Prompts`
- `resources/list` -> `Resources`
- `tools/list` -> `Tools`
5. 各セクションは、要素がある場合のみ表形式で以下の列を追加する。
- `Prompts`: `Name`, `Title`, `Description`
- `Resources`: `Name`, `URI`, `Title`, `Description`
- `Tools`: `Name`, `Title`, `Description`, `Input`, `Output`, `Annotations`
6. 表の `Name` 値は必ずインラインコード（バッククォート）で囲む。
7. `Input`, `Output`, `Annotations` を出す場合は、各テーブルセル内をリスト形式（`<ul><li>...</li></ul>`）で書く。

## 分岐ルール
- `mcp.lua` などの定義ファイルにメソッド名があっても、サーバーの `methodHandlers` に未登録なら除外する。
- `definition.title`, `definition.description` が無い場合は空欄にする。推測で補完しない。
- `Name` 列は必ず `` `name_value` `` の形式で出力する。
- `Resources` の `URI` は必ず実装から取得した値を記載する。推測で補完しない。
- `Title`, `Description` は常に `[Morrowind] ` などの prefix を除去して出力する。
- 対象カテゴリに要素が無ければ、見出しのみを出力し、表は出さない。
- `Input` は `inputSchema` を指す。`inputSchema` が実質空（例: `additionalProperties=false` だけ）なら空欄にする。
- `Input` の required/optional は `inputSchema.required` を反映する。
- `Output` は `outputSchema` を指す。未定義または空なら空欄にする。
- `Annotations` は true の項目のみ出力し、false は出力しない。
- `Resources` では `Input`, `Output`, `Annotations` を出力しない。

## 完了条件
- `prompts/resources/tools` の3区分で整理されている。
- 記載項目は `Prompts` が `Name`, `Title`, `Description`、`Resources` が `Name`, `URI`, `Title`, `Description`、`Tools` が `Name`, `Title`, `Description`（拡張列指定時は `Input`, `Output`, `Annotations` を追加）である。
- `Name` 列の全値がインラインコード表記になっている。
- 取得できた実データのみ記載され、実装説明・補足・推測が混ざっていない。

### 拡張列を要求された場合の完了条件
- `Input`, `Output`, `Annotations` の定義がそれぞれ schema/annotation を根拠に記載されている。
- 空の `Input`/`Output` は空欄になっている。
- `Annotations` は true の項目のみ記載されている。
- `Input`, `Output`, `Annotations` の各セルがリスト形式になっている。
- ただし `Resources` は拡張列要求時でも `URI` を含め、`Input`, `Output`, `Annotations` は追加しない。

## 例プロンプト
- LuaからMCPの `*/list` で実行できる機能だけ抽出して、prompts/resources/tools ごとに `Name`, `Title`, `Description` 表でまとめて。`Name` はバッククォートで囲んで。
- 余計な説明なしで、`tools/list` の実データを `Name`, `Title`, `Description` 一覧にして。
