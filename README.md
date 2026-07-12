# Morrowind Model Context Protocol Server (Morrowind MCP)

Morrowind Model Context Protocol Server (Morrowind MCP) connects Morrowind to external LLM AIs (such as ChatGPT, Claude, Copilot, or Gemini) using MCP standard.

This mod allows the AI to learn about the world of Morrowind and interact with it.

**This mod contains source code generated or assisted by AI. and all code has been manually reviewed, refactored and verified by a senior software engineer.**

## How to use

1. Install Morrowind full expansion, MGE XE, MWSE, MCP, and optionally MO2 and MGE XE UF.
1. Install this mod into Morrowind's `Data Files` folder or using MO2.
1. Setup `mcp.json` for an AI agent configuration. See [MCP Configuration](#mcp-configuration) for details.
1. Start Morrowind with MWSE and this mod.
1. Connect to this MCP server using `mcp.json`
1. Use or Chat an AI agent tools and prompts to interact with Morrowind world.

### Requirements
- Morrowind full expansion
- [Morrowind Graphics Extender XE](https://www.nexusmods.com/morrowind/mods/41102) (MGE XE): Due to contains MWSE. And it extends Morrowind's graphics.
- **[Morrowind Script Extender](https://github.com/MWSE/MWSE) (MWSE)**: Run MWSE-Update.exe for getting the latest version. It is required for this MCP server mod.
- [Morrowind Script Extender Community Patch](https://www.nexusmods.com/morrowind/mods/19510) (MCP) or [MCP Beta](https://www.nexusmods.com/morrowind/mods/26348) : Run Morrowind Code Patch.exe. it fixes many bugs in Morrowind.
- (Optional) [Mod Organizer 2](https://www.nexusmods.com/skyrimspecialedition/mods/6194) (MO2): for managing mods. Also useful for development and testing.
- (Optional) [MGE XE UF](https://www.nexusmods.com/morrowind/mods/57200): It is unofficial update for MGE XE.

## Features

[FEATURES.md](FEATURES.md)

## MCP Configuration

### Copilot with VS Code

**.vscode/mcp.json**

```json
{
  "servers": {
    "morrowind-mcp": {
      "type": "http",
      "url": "http://localhost:33427"
    }
  }
}
```

https://code.visualstudio.com/docs/agents/reference/mcp-configuration

### ChatGPT Codex

**./config.toml** (global)

```toml
[mcp_servers.morrowind-mcp]
enabled = true
url = "http://localhost:33427"
```


### Claude Desktop

**./claude_desktop_config.json** (global)

```json
{
  "mcpServers": {
    "morrowind-mcp": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:33427"
      ]
    }
  }
}
```

https://modelcontextprotocol.io/docs/develop/connect-local-servers

### Antigravity CLI and Antigravity IDE

**.agents/mcp_config.json** (local)
**~/.gemini/config/mcp_config.json** (global)

```json
{
  "mcpServers": {
    "morrowind-mcp": {
      "serverUrl": "http://localhost:33427"
    }
  }
}
```

https://antigravity.google/docs/mcp

### Others

- Cursor: `.cursor/mcp.json`
- Others: `.mcp.json`

```json
{
  "mcpServers": {
    "morrowind-mcp": {
      "type": "streamable-http",
      "url": "http://localhost:33427"
    }
  }
}
```

https://code.claude.com/docs/en/mcp-quickstart



## Development

### Naming Convention
#### Prompts, Tools

- Prompts and Tools name must be in `kebab-case`.
- (mcp prefix)-(object)-(action)
    - mcp prefix: `mw` (Morrowind)
    - Example: `mw-menu-fetch`, `mw-screenshot-save`

#### Arguments

- Arguments name must be in `snake_case`.

### Shared root config

This configuration system is designed to handle differences between user environments, such as Morrowind install locations, Mod Organizer 2 setup, and profile-specific paths. By layering `default`, `local`, and `env` values, the project can run consistently across personal setups, test machines, and CI.

Precedence: `env > local > default`.
- Environment variables can be used to override values in `mwmcp.local.json` for CI or other purposes. For example, `MWMCP_SERVER_ADDRESS` can override the `server.address` value.
- Local development overrides can be placed in [mwmcp.local.json](mwmcp.local.json).
- The default values live in [mwmcp.defaults.json](mwmcp.defaults.json).

Environment variables:

| Variable | Overrides | Meaning |
|---|---|---|
| `MWMCP_SERVER_ADDRESS` | `server.address` | This server host name or IP address |
| `MWMCP_SERVER_PORT` | `server.port` | This server TCP port |
| `MWMCP_MO2_EXE_FILE` | `paths.mo2ExeFile` | Mod Organizer 2 executable file path |
| `MWMCP_MO2_APPLICATION` | `paths.mo2Application` | Mod Organizer 2 application name to launch |
| `MWMCP_MO2_PROFILE` | `paths.mo2Profile` | Mod Organizer 2 profile name |
| `MWMCP_MORROWIND_INSTALL_DIR` | `paths.morrowindInstallDir` | Morrowind install directory path |
| `MWMCP_MWSE_CONFIG_DIR` | `paths.mwseConfigDir` | MWSE config directory path |

### Test scripts

- [tests/unit_test.ps1](tests/unit_test.ps1): Run Lua unit tests for MWSE mod modules
- [tests/server_test.ps1](tests/server_test.ps1): Start Morrowind/MWSE server, run integration tests, and stop the server
- [tests/sse_test.ps1](tests/sse_test.ps1): Start Morrowind/MWSE server, open an SSE stream, verify a server-to-client notification
- [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1): Launch Mod Organizer 2 to start Morrowind with MWSE and the MCP server
- [tests/stop_server.ps1](tests/stop_server.ps1): Stop the currently running Morrowind
- [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1): Resolve configuration precedence (env > local > default) and provide paths for tests

#### MCP Inspector

Run [tests/start_inspector.ps1](tests/start_inspector.ps1) to launch the MCP Inspector UI:

```powershell
.\tests\start_inspector.ps1
```

This automatically resolves the server configuration and opens the Inspector at the configured connection URL.

### Transport behavior

| HTTP Method | Behavior | Notes |
|---|---|---|
| `POST` | Client-to-server JSON-RPC requests and notifications | Uses JSON payloads |
| `GET` | Opens the session-scoped SSE stream for server-to-client notifications | Requires `Accept: text/event-stream` |
| `DELETE` | Ends the Streamable HTTP session | Uses `MCP-Session-Id` |
| `OPTIONS` | Handles CORS preflight requests | Allows `POST`, `GET`, `DELETE`, and `OPTIONS` |

The server returns `MCP-Session-Id` on `initialize`; clients must send it on subsequent `POST` and `GET` requests for that session.
If the same session opens another SSE `GET`, the server replaces the previous SSE stream with the newest one.

### MCP Features

| MCP Method | Supported |
|---|---|
| `completion/complete` | No (undecided) |
| `elicitation/create` | No (undecided) |
| `initialize` | Yes |
| `logging/setLevel` | Yes |
| `notifications/cancelled` | Yes |
| `notifications/initialized` | Yes |
| `notifications/tasks/status` | No (undecided) |
| `notifications/message` | Yes |
| `notifications/progress` | Yes |
| `notifications/prompts/list_changed` | Yes |
| `notifications/resources/list_changed` | Yes |
| `notifications/resources/updated` | Yes |
| `notifications/roots/list_changed` | No (undecided) |
| `notifications/tools/list_changed` | Yes |
| `notifications/elicitation/complete` | No (undecided) |
| `ping` | Yes |
| `tasks/get` | No (undecided) |
| `tasks/result` | No (undecided) |
| `tasks/list` | No (undecided) |
| `tasks/cancel` | No (undecided) |
| `prompts/get` | Yes |
| `prompts/list` | Yes |
| `resources/list` | Yes |
| `resources/read` | Yes |
| `resources/subscribe` | Yes |
| `resources/templates/list` | Yes |
| `resources/unsubscribe` | Yes |
| `roots/list` | No (undecided) |
| `sampling/createMessage` | No (undecided) |
| `tools/call` | Yes |
| `tools/list` | Yes |

`Pagination` is not supported yet. All lists are returned in a single response.

## SDK

- [base64.lua](./MWSE/mods/morrowind-mcp/core/base64.lua) from [lbase64](https://github.com/iskolbin/lbase64): MIT License or Public Domain

## Known Issues

- During Bink movie playback, MWSE execution can pause completely. While a movie is playing, this server may stop responding to MCP requests until the movie ends.
- Impact: `tools/call` requests that trigger movie playback (for example, starting a new game from the main menu) can appear to hang, and a response may not be returned until playback finishes.
- Current workaround: replace movie files under `Data Files/Video` with dummy files to prevent movie playback. **Keep backups of original files and restore them when needed.**

## TODO

- OpenMW is not supported yet.

## License

[MIT License](LICENSE)
