# Morrowind Model Context Protocol Server (Morrowind MCP)


## MCP configuration

### VS Code
.vscode/mcp.json

```json
{
  "servers": {
    "morrowind-mcp": {
      "type": "http",
      "url": "http://localhost:53427"
    }
  }
}
```

https://code.visualstudio.com/docs/agents/reference/mcp-configuration

### Others (Claude, ChatGPT, Gemini...)

## Development

```sh
npx @modelcontextprotocol/inspector@latest
```
