# AGENTS instructions

## プロジェクト概要

- **Morrowind MCP** は Morrowind 向けの Model Context Protocol Server mod
- Morrowind Script Extender (MWSE) の Lua mod として動作し、TCP ソケットを介して Morrowind のゲーム内情報の公開やゲームの操作を行う

---

## 設定ファイル

host/port を含む設定は [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1) を使用して `env > local > default` の順で解決する

| ファイル | 目的 |
|---|---|
| [mwmcp.defaults.json](mwmcp.defaults.json) | 開発用の既定設定 (`default`) |
| [mwmcp.local.json](mwmcp.local.json) | 個人環境の上書き設定 (`local`) |

環境変数 (`env`) と設定ファイルの対応表:

| Variable | Overrides | Meaning |
|---|---|---|
| `MWMCP_SERVER_ADDRESS` | `server.address` | MCP server host name or IP address |
| `MWMCP_SERVER_PORT` | `server.port` | MCP server TCP port |
| `MWMCP_MO2_EXE_FILE` | `paths.mo2ExeFile` | ModOrganizer2 executable file path |
| `MWMCP_MO2_APPLICATION` | `paths.mo2Application` | ModOrganizer2 application name to launch |
| `MWMCP_MO2_PROFILE` | `paths.mo2Profile` | ModOrganizer2 profile name |
| `MWMCP_MORROWIND_INSTALL_DIR` | `paths.morrowindInstallDir` | Morrowind install directory path |
| `MWMCP_MWSE_CONFIG_DIR` | `paths.mwseConfigDir` | MWSE config directory path |

## ディレクトリ構成

| ファイル/ディレクトリ | 目的 |
|---|---|
| [MWSE/mods/morrowind-mcp/](MWSE/mods/morrowind-mcp/) | modのソースコードディレクトリ |
| [MWSE/mods/morrowind-mcp/core/](MWSE/mods/morrowind-mcp/core) | MWSEに依存していないコアライブラリ |
| [MWSE/mods/morrowind-mcp/server/](MWSE/mods/morrowind-mcp/server) | MWSEを使用した MCP Server |
| [MWSE/mods/morrowind-mcp/prompts/](MWSE/mods/morrowind-mcp/prompts) | MCP Server Prompts |
| [MWSE/mods/morrowind-mcp/resources/](MWSE/mods/morrowind-mcp/resources) | MCP Server Resources |
| [MWSE/mods/morrowind-mcp/tools/](MWSE/mods/morrowind-mcp/tools) | MCP Server Tools |
| [MWSE/mods/morrowind-mcp/tests/](MWSE/mods/morrowind-mcp/tests) | Unit Tests |
| `<paths.morrowindInstallDir>/Data Files/MWSE/core/` | MWSEライブラリディレクトリ（env/local/default から解決） |
| `<paths.morrowindInstallDir>/MWSE.log` | MWSE.log ログファイル（env/local/default から解決） |

## 開発規約

## MCP Server

- MCP Protocol Version: `2025-11-25`
- Streamable HTTP を実装する
- SSE は対応しない

### MCP Prompts and Tools Naming Convention
- Prompts and Tools name must be in `kebab-case`.
- all prompts and tools name must be prefixed with `mw-` (Morrowind)
- Arguments name must be in `snake_case`.

## 開発スクリプト

Windows上での開発のため、以下の運用ルールを必須とする。

- Bash/Unix 系コマンドを使用しない（例: `bash`, `sh`, `rg`, `grep`, `sed`, `awk`, `cat`, `ls`, `find`, `xargs`）
- スクリプト実行は PowerShell のみを使用する（`.ps1` と PowerShell cmdlet）
- 検索は VS Code の検索ツールを優先する（`grep_search`, `file_search`, `semantic_search`）
- ターミナルで検索が必要な場合は PowerShell cmdlet を使う（例: `Get-ChildItem`, `Select-String`）
- 代替手段が無い場合は、実行前にユーザー確認を取る

- [tests/server_test.ps1](tests/server_test.ps1): Morrowindを起動してMCP サーバーの実行・停止・通信をテストする
- [tests/unit_test.ps1](tests/unit_test.ps1): Lua モジュールの単体テストを実行する
- [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1): Mod Organizer 2 経由で Morrowind を起動してサーバーを実行する
- [tests/stop_server.ps1](tests/stop_server.ps1): Morrowindを終了して、実行中のサーバーを停止する
- [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1): 設定優先順位（env > local > default）を解決し、テスト/エージェント用のパス設定を提供する

## 参考リンク

- [README](README.md)
- [Model Context Protocol](https://modelcontextprotocol.io/specification/2025-11-25)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
