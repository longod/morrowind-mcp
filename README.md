# Morrowind Model Context Protocol Server (Morrowind MCP)

Morrowind Model Context Protocol Server (Morrowind MCP) connects Morrowind to external LLM AIs (such as ChatGPT, Claude, Copilot, or Gemini) using MCP standard.

This allows the AI to learn about the world of Morrowind and interact with it.

## Features

[FEATURES.md](FEATURES.md)

## MCP Configuration

### VS Code
- `.vscode/mcp.json`

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

## Development

### Shared root config

Precedence: `env > local > default`.
- Environment variables can be used to override values in `mwmcp.local.json` for CI or other purposes. For example, `MWMCP_SERVER_ADDRESS` can override the `server.address` value.
- Local development overrides can be placed in [mwmcp.local.json](mwmcp.local.json).
- The default values live in [mwmcp.defaults.json](mwmcp.defaults.json).

Environment variables:

| Variable | Overrides | Meaning |
|---|---|---|
| `MWMCP_SERVER_ADDRESS` | `server.address` | MCP server host name or IP address |
| `MWMCP_SERVER_PORT` | `server.port` | MCP server TCP port |
| `MWMCP_MO2_EXE_FILE` | `paths.mo2ExeFile` | ModOrganizer2 executable file path |
| `MWMCP_MO2_APPLICATION` | `paths.mo2Application` | ModOrganizer2 application name to launch |
| `MWMCP_MO2_PROFILE` | `paths.mo2Profile` | ModOrganizer2 profile name |
| `MWMCP_MORROWIND_INSTALL_DIR` | `paths.morrowindInstallDir` | Morrowind install directory path |
| `MWMCP_MWSE_CONFIG_DIR` | `paths.mwseConfigDir` | MWSE config directory path |

### Test scripts

- [tests/unit_test.ps1](tests/unit_test.ps1): Run Lua unit tests for MWSE mod modules
- [tests/server_test.ps1](tests/server_test.ps1): Start Morrowind/MWSE server, run integration tests, and stop the server
- [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1): Launch ModOrganizer2 to start Morrowind with MWSE and the MCP server
- [tests/stop_server.ps1](tests/stop_server.ps1): Stop the currently running MCP server
- [tests/mwmcp_config.ps1](tests/mwmcp_config.ps1): Resolve configuration precedence (env > local > default) and provide paths for tests

### MCP Inspector

Run [tests/start_inspector.ps1](tests/start_inspector.ps1) to launch the MCP Inspector UI:

```powershell
.\tests\start_inspector.ps1
```

This automatically resolves the server configuration and opens the Inspector at the configured connection URL.

