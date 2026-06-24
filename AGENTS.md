# AGENTS instructions

## プロジェクト概要

**Morrowind MCP** は The Elder Scrolls III: Morrowind 向けの Model Context Protocol (MCP) サーバー実装です。
Morrowind Script Extender (MWSE) の Lua mod として動作し、TCP ソケットを介して Morrowind のゲーム内情報の公開やゲームの操作を行います。

- **言語**: Lua (LuaJIT)
- **依存関係**: Morrowind Script Extender (MWSE), luaSocket, JSON
- **エントリポイント**: [main.lua](MWSE/mods/morrowind-mcp/main.lua)
- **ソースコードディレクトリ**: [MWSE/mods/morrowind-mcp](MWSE/mods/morrowind-mcp)

---

## 設定ファイル

| ファイル | 目的 |
|---|---|
| [mwmcp.defaults.json](mwmcp.defaults.json) | 開発用の既定設定 |
| [mwmcp.local.json](mwmcp.local.json) | 個人環境の上書き設定。`gitignore` 対象 |

- host/port を含む設定は `env > local > default` の順で解決する

## ディレクトリ構成

| Variable | Overrides | Meaning |
|---|---|---|
| `MWMCP_SERVER_ADDRESS` | `server.address` | MCP server host name or IP address |
| `MWMCP_SERVER_PORT` | `server.port` | MCP server TCP port |
| `MWMCP_MO2_EXE_FILE` | `paths.mo2ExeFile` | ModOrganizer2 executable file path |
| `MWMCP_MO2_APPLICATION` | `paths.mo2Application` | ModOrganizer2 application name to launch |
| `MWMCP_MO2_PROFILE` | `paths.mo2Profile` | ModOrganizer2 profile name |
| `MWMCP_MORROWIND_INSTALL_DIR` | `paths.morrowindInstallDir` | Morrowind install directory path |
| `MWMCP_MWSE_CONFIG_DIR` | `paths.mwseConfigDir` | MWSE config directory path |


| ファイル/ディレクトリ | 目的 |
|---|---|
| [MWSE/mods/morrowind-mcp/](MWSE/mods/morrowind-mcp/) | modのソースコードディレクトリ |
| `<paths.morrowindInstallDir>/Data Files/MWSE/core/` | MWSEライブラリディレクトリ（env/local/default から解決） |
| `<paths.morrowindInstallDir>/MWSE.log` | MWSE.log ログファイル（env/local/default から解決） |

## 開発規約

利用可能なイベントは MWSE ドキュメントを参照してください。

## MCP Server

- luaSocket を使用した実装
- Streamable HTTPを使用する
- SSE は対応しない
- 単一クライアント接続のみを想定する。マルチクライアント、Multi Round-Trip Requestsは努力目標。
- `MWSE.log` を確認することで、サーバー側の挙動を検査できるようにする

### MCP Resource URI
- MCP resource URI は物理パスではなく論理 URI として扱う: `morrowind-mcp://`
- `settings.resourceUriPrefix` は `Data Files` 直下を表す: `morrowind-mcp://data-files/`
- `resources/read` は URI prefix 以降を `Data Files` 相対パスとして解決する
- MO2/USVFS の物理 Overwrite パスは Lua から解決しようとしない
- 生成ファイルを VFS 対象にしたい場合は `settings.dataFiles` 配下に保存する

### MCP feature definitions
- `prompts/list`, `resources/list`, `tools/list` で公開される `name`, `title`, `description` は generator 経由の最終値を正とする
- Tool は `jsonrpc.Tool(...)` で定義し、公開名は generator が `settings.name_prefix` を付与する。定義ファイル側で `mw_` を直書きしない
- Tool の `title` と `description` も generator が `settings.title_prefix`, `settings.description_prefix` を付与する。定義ファイル側で `[Morrowind] ` を直書きしない
- `tools/call` は公開後の prefixed name を受け取るため、テストやドキュメントでは `mw_` 付きの名前を使う

### MCP schema generators
- `mcp.lua` の `---@class MCP.*Schema` は型注釈であり、実際の schema table 生成は [jsonrpc.lua](MWSE/mods/morrowind-mcp/server/jsonrpc.lua) の generator 関数で行う
- MCP schema class を追加・変更した場合は、対応する generator と UnitWind テストを合わせて更新する
- enum や default などの配列フィールドは `jsonrpc.array()` 経由で JSON array として扱える形にする

## 開発スクリプト

Windows上での開発のため、以下の運用ルールを必須とする。

- Bash/Unix 系コマンドを使用しない（例: `bash`, `sh`, `rg`, `grep`, `sed`, `awk`, `cat`, `ls`, `find`, `xargs`）。
- スクリプト実行は PowerShell のみを使用する（`.ps1` と PowerShell cmdlet）。
- 検索は VS Code の検索ツールを優先する（`grep_search`, `file_search`, `semantic_search`）。
- ターミナルで検索が必要な場合は PowerShell cmdlet を使う（例: `Get-ChildItem`, `Select-String`）。
- 代替手段が無い場合は、実行前にユーザー確認を取る。

- [tests/server_test.ps1](tests/server_test.ps1): MCP サーバーの起動・停止・通信をテストします
- [tests/unit_test.ps1](tests/unit_test.ps1): Lua モジュールの単体テストを実行します
- [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1): ModOrganizer2 経由で Morrowind と MWSE を起動してサーバーを実行します
- [tests/stop_server.ps1](tests/stop_server.ps1): 実行中のサーバーを停止します
- [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1): 設定優先順位（env > local > default）を解決し、テスト/エージェント用のパス設定を提供します

## 参考リンク

- [README](README.md)
- [MWSE Documentation](https://mwse.github.io/MWSE/)
- [MWSE GitHub](https://github.com/MWSE/MWSE)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [luaSocket](https://lunarmodules.github.io/luasocket/index.html)
- [Morrowind MCP GitHub](https://github.com/longod/morrowind-mcp)

