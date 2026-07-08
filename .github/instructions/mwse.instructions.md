---
description: lua programming guidelines.
applyTo: MWSE/mods/morrowind-mcp/**/*.lua
---

## 開発規約

- クラス名と関数は先頭大文字 `CamelCase` で命名すること
- 変数は先頭小文字`camelCase`か`snake_case`で命名すること。使い分けは状況次第。
- pattern matchingやregular expressionを必要とする処理は、使用しない方が高速と思われる場合は使用しない
- `table` 型のサイズを取得する場合、`#table` を使用するのではなく、`table.size()` を使用する
- `logger` に外部入力や URI を渡す場合は `logger:debug("%s", value)` のように format を明示する
- `require` と `include` は完全修飾モジュール名を使用する（例: `require("morrowind-mcp.core.strutil")`）
- 文字列はテストケースで使用する場合を除き、英語で書く
- [core/](../../MWSE/mods/morrowind-mcp/core/) は MWSE に依存しないコアライブラリにする

### Comment

- コメントは、実装の意図や非自明な判断が読み手に伝わるように書く
- 関数全体の目的、契約、前提条件は関数コメントで説明する
- 分岐、例外処理、エッジケース、ログ出力など局所的な理由は、その処理の直前にコメントを書く
- 一部の分岐やログ出力にだけ関係する説明は、関数全体ではなく該当箇所に書く
- 簡単な行や1行ごとの説明コメントは書かない
- コメントは必ず英語で書く
- 英語以外のコメントを検出した場合は、英語に置き換えて報告する

## Lua/MWSE

- LuaJIT を使用している
- Morrowind Script Extender (MWSE) を使用している
- MWSEに関する情報は `MWSE Documentation` or `MWSE GitHub` を参照する
- エントリポイント: [main.lua](../../MWSE/mods/morrowind-mcp/main.lua)
- loggerを使用することで `MWSE.log` にログを出力できる
- `MWSE.log` を確認することで、サーバー側の挙動を検査できるようにする
- luaSocket を使用したTCP通信

## HTTP

- 送受信に使用するヘッダやメソッド、コードは、`http.lua` の定義を使用して即値はしようしないようにする。定義が存在しない場合は、`http.lua` に定義を追加する。

## MCP

### MCP Resource URI

- MCP resource URI は物理パスではなく論理 URI として扱う: `morrowind://`
- `settings.uriScheme` のルートは `settings.resourceRootDir` を表す
- `resources/read` は URI prefix 以降を `settings.resourceRootDir` 相対パスとして解決する
- リソース URI/パス変換は `pathutil.lua` の helper を使用する
- `string.sub` や `string.gsub` による URI/パス変換の直書き実装は新規に追加しない
- MO2/USVFS の物理 Overwrite パスは Lua から解決しようとしない
- 生成ファイルを VFS 対象にしたい場合は `settings.dataFiles` 配下に保存する

### MCP feature definitions

- `prompts/list`, `resources/list`, `tools/list` で公開される `name`, `title`, `description` は `jsonrpc` の generator 関数経由の最終値を正とする
- Tool は `jsonrpc.Tool(...)` で定義し、公開名は generator が `settings.name_prefix` を付与する。定義ファイル側で `mw-` を直書きしない
- Tool の `title` と `description` も generator が `settings.title_prefix`, `settings.description_prefix` を付与する。定義ファイル側で `[Morrowind] ` を直書きしない
- `tools/call` は公開後の prefixed name を受け取るため、テストやドキュメントでは `mw-` 付きの名前を使う

### MCP schema generators

- `mcp.lua` の `---@class MCP.*Schema` は型注釈であり、実際の schema table 生成は [jsonrpc.lua](../../MWSE/mods/morrowind-mcp/server/jsonrpc.lua) の generator 関数で行う
- MCP schema class を追加・変更した場合は、対応する generator と UnitWind テストを合わせて更新する
- enum や default などの配列フィールドは `jsonrpc.array()` 経由で JSON array として扱える形にする


## Tests

- コードの変更後は、[tests/unit_test.ps1](../../tests/unit_test.ps1) を実行して、正しく動作することを確認する（スキル /unittest_run）
- MCP Serverに関するコードの変更後は、[tests/server_test.ps1](../../tests/server_test.ps1) を実行して、MCP Server が正しく動作することを確認する（/servertest_run）

## 参考リンク

- [MWSE Documentation](https://mwse.github.io/MWSE/)
- [MWSE GitHub](https://github.com/MWSE/MWSE)
- [luaSocket](https://lunarmodules.github.io/luasocket/index.html)
