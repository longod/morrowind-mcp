local this = {}

this.version = 1
this.header = "Morrowind MCP Disclaimer"

this.text = table.concat({
    "This mod exposes Morrowind data and actions through MCP.",
    "When you connect it to an external AI client or LLM service, data exposed through the MCP interface, including file contents, logs, and system information, may be transmitted to third-party services selected by you.",
    "AI-guided actions may be inaccurate, unexpected, or unsafe. You are responsible for reviewing connected services, prompts, and results.",
    "If you do not accept this disclaimer, the MCP server will remain disabled and you will be asked again next time.",
}, "\n\n")

return this
