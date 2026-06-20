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
| MWMCP_MORROWIND_INSTALL_DIR   | Morrowind installed directory     | C:/Morrowind |
| MWMCP_MO2_EXE_FILE            | ModOrganizer2 application path    | C:/Modding/MO2/ModOrganizer.exe |
| MWMCP_MO2_APPLICATION         | MO2 Morrowind application name    | Morrowind |
| MWMCP_MO2_MWSE_PROFILE        | MO2 Morrowind profile name        | Portable |
| MWMCP_DEFAULT_SERVER_HOST     | Default server host name          | localhost |
| MWMCP_DEFAULT_SERVER_PORT     | Default server port number        | 33427 |

## ディレクトリ構成

| ファイル/ディレクトリ | 目的 |
|---|---|
| [${workspaceFolder:morrowind-mcp}/MWSE/mods/morrowind-mcp/](${workspaceFolder:morrowind-mcp}/MWSE/mods/morrowind-mcp) | modのソースコードディレクトリ |
| [${workspaceFolder:MWSE}/core/](${workspaceFolder:MWSE}/core/) | MWSEライブラリディレクトリ |
| [${env.MWMCP_MORROWIND_INSTALL_DIR}/MWSE.log](${env.MWMCP_MORROWIND_INSTALL_DIR}/MWSE.log) | `${env.MWMCP_MORROWIND_INSTALL_DIR}` 直下の `MWSE.log` ログファイル |

## 開発規約

利用可能なイベントは MWSE ドキュメントを参照してください。

## MCP Server

- luaSocket を使用した実装
- Streamable HTTPを使用する
- SSE は対応しない
- 単一クライアント接続のみを想定する。マルチクライアント、Multi Round-Trip Requestsは努力目標。

## 参考リンク

- [README](README.md)
- [MWSE Documentation](https://mwse.github.io/MWSE/)
- [MWSE GitHub](https://github.com/MWSE/MWSE)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [luaSocket](https://lunarmodules.github.io/luasocket/index.html)
- [Morrowind MCP GitHub](https://github.com/longod/morrowind-mcp)

