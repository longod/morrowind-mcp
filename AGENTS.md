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

## 開発スクリプト

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

