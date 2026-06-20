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
npx @modelcontextprotocol/inspector --config tests/mcp.json
```

https://github.com/modelcontextprotocol/inspector

- Streamable HTTP
- http://localhost:33427
- Via Proxy

