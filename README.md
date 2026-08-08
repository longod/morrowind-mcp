# Morrowind Model Context Protocol Server (Morrowind MCP)

Morrowind Model Context Protocol Server (Morrowind MCP) connects Morrowind to external LLM AIs (such as ChatGPT, Claude, Copilot, or Gemini) using MCP standard.

This mod allows the AI to learn about the world of Morrowind and interact with it.

**This mod contains source code generated or assisted by AI. and all code has been manually reviewed, refactored and verified by a senior software engineer.**

## How to use

1. Install Morrowind full expansion, MGE XE, MWSE, MCP, and optionally MO2 and MGE XE UF.
1. Install this mod into Morrowind's `Data Files` folder or using MO2.
1. Setup `mcp.json` or client specific file for an AI agent configuration. See [MCP Configuration](#mcp-configuration) for details.
1. Start Morrowind with MWSE and this mod.
1. Connect to this MCP server using `mcp.json`
1. Use or Chat an AI agent tools, prompts and resources to interact with Morrowind world.

### Requirements
- Morrowind full expansion
- [Morrowind Graphics Extender XE](https://www.nexusmods.com/morrowind/mods/41102) (MGE XE): Due to contains MWSE. And it extends Morrowind's graphics.
- **[Morrowind Script Extender](https://github.com/MWSE/MWSE) (MWSE)**: Run MWSE-Update.exe for getting the latest version. It is required for this MCP server mod.
- [Morrowind Script Extender Community Patch](https://www.nexusmods.com/morrowind/mods/19510) (MCP) or [MCP Beta](https://www.nexusmods.com/morrowind/mods/26348) : Run Morrowind Code Patch.exe. it fixes many bugs in Morrowind.
- (Optional) [Mod Organizer 2](https://www.nexusmods.com/skyrimspecialedition/mods/6194) (MO2): for managing mods. Also useful for development and testing.
- (Optional) [MGE XE UF](https://www.nexusmods.com/morrowind/mods/57200): It is unofficial update for MGE XE.

## MCP Configuration

| Client | Project config file | User config file | Sample | Notes |
|---|---|---|---|---|
| VSCode | .vscode/mcp.json | %APPDATA%/Code/User/mcp.json | [sample](#vscode) | [MCP configuration reference](https://code.visualstudio.com/docs/agents/reference/mcp-configuration) |
| Claude Desktop | .mcp.json | %APPDATA%/Claude/claude_desktop_config.json | [sample](#claude-desktop) | [Connect to local MCP servers](https://modelcontextprotocol.io/docs/develop/connect-local-servers) |
| Claude Code | .mcp.json | %USERPROFILE%/.claude.json | [sample](#claude-code) | [Connect to MCP servers](https://code.claude.com/docs/en/mcp-quickstart) |
| Cursor | .cursor/mcp.json | %USERPROFILE%/.cursor/mcp.json | [sample](#claude-code) | [Model Context Protocol (MCP)](https://cursor.com/docs/mcp) |
| ChatGPT Codex | .config.toml | %USERPROFILE%/.codex/config.toml | [sample](#chatgpt-codex) | [Advanced Configuration](https://learn.chatgpt.com/docs/config-file/config-advanced) |
| Antigravity | .agents/mcp_config.json | %USERPROFILE%/.gemini/config/mcp_config.json | [sample](#antigravity) | [Model Context Protocol (MCP)](https://antigravity.google/docs/mcp) |


### VSCode

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

### Claude Desktop

Requires [Node.js](https://nodejs.org/ja/download)

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

### Claude Code

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

### ChatGPT Codex

```toml
[mcp_servers.morrowind-mcp]
enabled = true
url = "http://localhost:33427"
```

### Antigravity

```json
{
  "mcpServers": {
    "morrowind-mcp": {
      "serverUrl": "http://localhost:33427"
    }
  }
}
```

## Features

This MCP server does not modify the game or generate and execute new code; it only performs actions that are possible within the game itself.

[FEATURES.md](FEATURES.md)

### Runtime Availability

Tools and prompts remain listed while their runtime prerequisites are unavailable. The tool catalog is fixed when the server starts; tools excluded by startup configuration are not registered. Call `mw-capabilities-fetch` to read each published tool's general `conditions`; this is guidance rather than a current-state guarantee. Each `tools/call` and `prompts/get` validates the normalized arguments and current game state immediately before execution. Runtime tool failures return `isError: true` with a machine-readable reason and recovery guidance.

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
| `MWMCP_DATAFILES_OVERWRITE_DIR` | `paths.datafilesOverwriteDir` | Data Files overwrite directory path; Lua runtime mod data writes resolve to `<datafilesOverwriteDir>/MWSE/mods/morrowind-mcp`; MWSE config resolves to `<datafilesOverwriteDir>/MWSE/config` |

Server-generated Lua output data can be inspected under `<paths.datafilesOverwriteDir>/MWSE/mods/morrowind-mcp`. The shared config helper exposes this physical path as `Paths.modDataDir`; script-created sentinel files are not considered server output data.

### Test scripts

- [tests/unit_test.ps1](tests/unit_test.ps1): Run Lua unit tests for MWSE mod modules. Pass test file names to run only those files.
- [tests/server_test.ps1](tests/server_test.ps1): Start Morrowind/MWSE server, run integration tests, and stop the server
  - By default, after connectivity is confirmed, it attempts to bring Morrowind to the foreground. This is required for tests that use keyboard key or mouse button input, because those inputs are not sent while Morrowind is in the background.
  - For tests that do not require input sending, run with `-NoForeground` to skip foreground activation and the capture click.
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

#### MCP Discovery

Run [tests/mcp_discover.ps1](tests/mcp_discover.ps1) to create an independent Streamable HTTP session and write the current `initialize`, `tools/list`, `resources/list`, and `prompts/list` results:

```powershell
.\tests\mcp_discover.ps1 -OutputPath .\tests\logs\mcp_discovery\initial.json
```

Use `-WatchSeconds` to keep its session-scoped SSE connection open. On a `*_list_changed` notification it automatically refreshes the corresponding list and appends the evidence to the JSON record:

```powershell
.\tests\mcp_discover.ps1 -WatchSeconds 60 -OutputPath .\tests\logs\mcp_discovery\watch.json
```

The script connects to an already running server and deletes its independent session when it exits; it does not launch or stop Morrowind.

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
| `completion/complete` | `No` |
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
| `resources/templates/list` | `No` |
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

- OpenMW is not supported yet. I'd like to do it, but it's simply because I don't know much about modding with OpenMW.

## License

[MIT License](LICENSE)


## Disclaimer

Disclaimer Version: 1

### 1. Limitation of Liability for AI Malfunctions
This software is designed to operate in conjunction with Large Language Models (LLMs) and other Artificial Intelligence technologies ("AI"). Due to the inherent nature of AI and automation, it may produce inaccurate outputs, unexpected commands, or malfunctions (including, but not limited to, hallucinations). The developer shall not be liable for any direct, indirect, incidental, or consequential damages, data loss, system failures, or other disadvantages arising from operations performed under AI direction or from reliance on AI-generated output (such as data modification, deletion, external communication, or system configuration changes). Users are solely responsible for reviewing, managing, and monitoring connected AI services, prompts, instructions, and execution results.

### 2. External AI Services and Data Transmission
This software runs locally, but it is intended to be used with external AI clients and/or LLM services through the Model Context Protocol (MCP). When so used, data exposed through the MCP interface, including file contents, logs, and system information, may be transmitted to and processed by third-party services selected by the user. By accepting the in-game disclaimer and enabling the MCP server, you acknowledge and agree that such data may be transmitted to and processed by those services. The handling, confidentiality, and privacy of transmitted data are governed by the terms, privacy policies, and security practices of the respective providers, as well as by the configuration choices made by the user. If you do not accept this disclaimer, the MCP server will not start. Do not use this software with confidential, sensitive, or personally identifiable information unless you fully understand and accept those risks.

### 3. No Warranty (Provided "As-Is")
This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.

