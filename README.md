# Morrowind Model Context Protocol Server (Morrowind MCP)


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

### Others (Claude, ChatGPT, Gemini...)

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
npx @modelcontextprotocol/inspector@latest
```

https://github.com/modelcontextprotocol/inspector

- Streamable HTTP
- http://localhost:33427
- Via Proxy
