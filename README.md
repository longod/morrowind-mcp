# Morrowind Model Context Protocol Server (Morrowind MCP)

Morrowind Model Context Protocol Server (Morrowind MCP) connects Morrowind to external LLM AIs (such as ChatGPT, Claude, Copilot, or Gemini) using MCP standard.

This allows the AI to learn about the world of Morrowind and interact with it.

## MCP configuration

### VS Code
.vscode/mcp.json

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

### Shared root config

Tests and agent-oriented tooling resolve host/port from [mwmcp.defaults.json](mwmcp.defaults.json), [mwmcp.local.json](mwmcp.local.json), and `MWMCP_SERVER_*` environment variables.

Local development overrides can be placed in [mwmcp.local.json](mwmcp.local.json). The default values live in [mwmcp.defaults.json](mwmcp.defaults.json).

### Others

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

```sh
npx @modelcontextprotocol/inspector --cli http://localhost:33427 --transport http
```

Test scripts are located under [tests/](tests/) and use [tests/start_server_mo2.ps1](tests/start_server_mo2.ps1) and [tests/stop_server.ps1](tests/stop_server.ps1).

https://github.com/modelcontextprotocol/inspector

- Streamable HTTP
- http://localhost:33427
- Via Proxy

