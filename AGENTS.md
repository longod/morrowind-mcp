# AGENTS instructions

## プロジェクト概要

**Morrowind MCP** は The Elder Scrolls III: Morrowind 向けの Model Context Protocol (MCP) サーバー実装です。
Morrowind Script Extender (MWSE) の Lua mod として動作し、TCP ソケットを介して Morrowind のゲーム内情報の公開やゲームの操作を行います。

- **言語**: Lua (LuaJIT)
- **依存関係**: Morrowind Script Extender (MWSE), luaSocket, JSON
- **エントリポイント**: [main.lua](MWSE/mods/morrowind-mcp/main.lua)
- **ソースコードディレクトリ**: [MWSE/mods/morrowind-mcp](MWSE/mods/morrowind-mcp)

---

## 環境変数

|Name|Description|Example|
|---|---|---|
| `MWMCP_MORROWIND_INSTALL_DIR` | Morrowind installed directory     | `C:/Morrowind` |
| `MWMCP_MO2_EXE_FILE`          | ModOrganizer2 (MO2) application   | `C:/Modding/MO2/ModOrganizer.exe` |
| `MWMCP_MO2_APPLICATION`       | MO2 Morrowind application         | `Morrowind` |
| `MWMCP_MO2_MWSE_PROFILE`      | MO2 Morrowind profile             | `Portable` |
| `MWMCP_MWSE_CONFIG_DIR`       | MWSE config directory             | `C:/Modding/Morrowind/overwrite/MWSE/config` (ModOrganizer2) or `${env:MWMCP_MORROWIND_INSTALL_DIR}/Data Files/MWSE/config` (Default) |
| `MWMCP_SERVER_ADDRESS`        | MCP server host                   | `localhost` |
| `MWMCP_SERVER_PORT`           | MCP server port                   | `33427` |

## 設定ファイル

| ファイル | 目的 |
|---|---|
| [mwmcp.defaults.json](mwmcp.defaults.json) | 開発用の既定設定 |
| [mwmcp.local.json](mwmcp.local.json) | 個人環境の上書き設定。`gitignore` 対象 |

## 設定優先順位

- host/port を含む設定は `local > env > default` の順で解決する
- `test.*` 系の試行回数や待機時間は config 対象外で、スクリプト内ハードコードを維持する

## ディレクトリ構成

| ファイル/ディレクトリ | 目的 |
|---|---|
| [MWSE/mods/morrowind-mcp/](MWSE/mods/morrowind-mcp/) | modのソースコードディレクトリ |
| `${env:MWMCP_MORROWIND_INSTALL_DIR}/Data Files/MWSE/core/` | MWSEライブラリディレクトリ |
| `${env:MWMCP_MORROWIND_INSTALL_DIR}/MWSE.log` | MWSE.log ログファイル |

## 開発規約

利用可能なイベントは MWSE ドキュメントを参照してください。

## MCP Server

- luaSocket を使用した実装
- Streamable HTTPを使用する
- SSE は対応しない
- 単一クライアント接続のみを想定する。マルチクライアント、Multi Round-Trip Requestsは努力目標。

## 開発スクリプト

- [tests/test.ps1](tests/test.ps1) は [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1) と [tests/stop_server.ps1](tests/stop_server.ps1) を呼び出す
- [tests/unittest.ps1](tests/unittest.ps1) も同じ PS1 スクリプトを使用する
- [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1) がルート設定（defaults/local/env）を読み込み、テスト/agent 用のパス解決を行う

## 参考リンク

- [README](README.md)
- [MWSE Documentation](https://mwse.github.io/MWSE/)
- [MWSE GitHub](https://github.com/MWSE/MWSE)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [luaSocket](https://lunarmodules.github.io/luasocket/index.html)
- [Morrowind MCP GitHub](https://github.com/longod/morrowind-mcp)

