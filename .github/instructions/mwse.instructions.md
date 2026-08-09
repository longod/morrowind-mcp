---
description: lua programming guidelines.
applyTo: MWSE/mods/morrowind-mcp/**/*.lua
---

## 開発規約

- クラス名と関数は先頭大文字 `CamelCase` で命名すること
- 変数は先頭小文字`camelCase`か`snake_case`で命名すること。使い分けは状況次第。
- pattern matchingやregular expressionを必要とする処理は、使用しない方が高速と思われる場合は使用しない
- `table` 型のサイズを取得する場合、非配列または要素に穴がある可能性がある場合は `table.size()` を使用する。1 から始まる連続した配列であることを不変条件として保証できる場合に限り、`#table` を使用してよい
- 要素数の上限を既存の入力値や定数から根拠付きで求められる配列・ハッシュは、`table.new(narray, nhash)` で事前確保する。実使用数とかけ離れた上限、追加走査、またはMWSEプロパティの再取得を要する場合は使用しない
- `logger` に外部入力や URI を渡す場合は `logger:debug("%s", value)` のように format を明示する
- `require` と `include` は完全修飾モジュール名を使用する（例: `require("morrowind-mcp.core.strutil")`）
- 文字列はテストケースで使用する場合を除き、英語で書く
- [core/](../../MWSE/mods/morrowind-mcp/core/) は MWSE に依存しないコアライブラリにする

### Comment

- コメントは、実装の意図や非自明な判断が読み手に伝わるように**必ず**書く
- Lua Annotaton を積極的に使用して、引数や戻り値の型や制約を明示する
- Lua Annotation の前にコメントを書く場合は、`--- ` を使用してコメントアウトする
- 関数全体の目的、契約、前提条件は関数コメントで説明する
- 分岐、例外処理、エッジケース、ログ出力など局所的な理由は、その処理の直前にコメントを書く
- 一部の分岐やログ出力にだけ関係する説明は、関数全体ではなく該当箇所に書く
- 簡単な行や1行ごとの説明コメントは書かない
- コメントは必ず英語で書く
- 英語以外のコメントを検出した場合は、英語に置き換えて報告する

## Lua/MWSE

- LuaJIT を使用している
- Morrowind Script Extender (MWSE) を使用している
- MWSEに関する情報はローカルのソースコードとメタ情報を確認し、内部実装を調べたい場合は [MWSE GitHub](https://github.com/MWSE/MWSE) を調べる
- エントリポイント: [main.lua](../../MWSE/mods/morrowind-mcp/main.lua)
- loggerを使用することで `MWSE.log` にログを出力できる
- `MWSE.log` を確認することで、サーバー側の挙動を検査できるようにする
- luaSocket を使用したTCP通信

### MCP.MWSEConfig

- MCP.MWSEConfig はこのMCPサーバー利用者が変更可能な設定値である
- MCP.MWSEConfig には、開発時に調整する内部の設定を絶対に含めてはならない
- [mcm.lua](../../MWSE/mods/morrowind-mcp/mcm.lua) で Mod Configuration Menu (MCM) からGUIで設定できる
- `mcm` にも、開発時に調整する内部の設定を絶対に含めてはならない
- `<datafilesOverwriteDir>/MWSE/config/morrowind-mcp.json` に保存される

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

### Memory system

- Memory 関連の Lua ファイルを追加・変更する場合は、[memory-system.md](../../docs/memory-system.md) の仕様も確認し、内部仕様変更があれば同時に更新する
- MCP clientから観測できるMemory resourceの追加・削除・URI・`data_type`・link relation・公開条件・payload field・意味を変更する場合は、[memory-resources.md](../../docs/memory-resources.md) も同時に更新する


## Tests

- 単体テストやサーバーテストが必要な場合は、原則として Morrowind MCP Test Runner に委任して実行する。
- 親エージェントや通常の作業エージェントは、テスト実行が必要だと判断した時点でこの子エージェントを呼び出す。
- UnitWind テストで `event`、`timer`、`tes3` などの共有 MWSE API を mock する場合、各テスト後に `unitwind.afterEach` で `clearMocks()` と `clearSpies()` を呼び、必ず復元する。
- 同じ共有 API の field を連続するテストで mock する場合、テストごとの cleanup を省略してはならない。UnitWind は mock 済みの値を次の復元先として記録するため、最後の cleanup だけでは元の MWSE API へ復元できなくなる。
- 単体テスト対象になっているファイルのコードの変更後は、[tests/unit_test.ps1](../../tests/unit_test.ps1) を実行して、正しく動作することを確認する（スキル /unittest_run）。必要なら引数で対象ファイルを指定できる。
- MCP Server の公開 surface や runtime 統合に影響する変更後は、[tests/server_test.ps1](../../tests/server_test.ps1) を実行する（/servertest_run）。対象例: `resources/list` / `resources/read` に出る resource の追加・削除・URI 変更、`prompts/list` / `tools/list` / `tools/call` の公開内容変更、`server/**` の protocol / HTTP / routing 変更、Memory module の登録・公開 entry・debug dump 出力変更、`settings` / `config` / path 解決の変更。
- UnitWind テストで共有 MWSE API を mock する追加・変更後は、通常の unit test と必要な server test が成功した後の最後の検証として、[tests/unit_test.ps1](../../tests/unit_test.ps1) に `-VerifyRuntimeAfterTests` を付けて実行する。この opt-in 検証は全 UnitWind 実行後に通常 runtime へ遷移できることを確認するため、通常のテスト実行ごとには実行しない。
- [tests/server_test.ps1](../../tests/server_test.ps1) は実行に時間を要するので、純粋な内部 helper、局所的な Lua 単体ロジック、既存 resource 内の表示文言だけの変更、ドキュメント・テストだけの変更では必須にしない。迷う場合は、変更が MCP client から観測できる公開 resource / prompt / tool / server 挙動を変えるかで判断する。

### 単体テスト (UnitWind テスト) を作成してはいけない対象

- [http_server.lua](../../MWSE/mods/morrowind-mcp/server/http_server.lua) 
- [resource.lua](../../MWSE/mods/morrowind-mcp/resources/resource.lua) 
- [prompts/*](../../MWSE/mods/morrowind-mcp/prompts/) 
- [tools/*](../../MWSE/mods/morrowind-mcp/tools/) 

これらは、サーバーテストで統合的に検証するため、単体テストを作成しない。

## 参考リンク

- [MWSE Documentation](https://mwse.github.io/MWSE/)
- [MWSE GitHub](https://github.com/MWSE/MWSE)
- [luaSocket](https://lunarmodules.github.io/luasocket/index.html)
