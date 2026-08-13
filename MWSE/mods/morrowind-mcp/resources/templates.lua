local mcp = require("morrowind-mcp.core.mcp")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

--- Static MCP resource-template definitions and their stable URI contracts.
local this = {}

this.memoryEntity = jsonrpc.ResourceTemplate({
	name = "memory-entity",
	title = "Memory Entity",
	uriTemplate = "morrowind://memory/{collection}/{entity_id}/{document}.json",
	description = "Read a published dynamic Memory entity document; player and unattributed documents are listed resources.",
	mimeType = mcp.mimeType.application_json,
	annotations = jsonrpc.Annotations({ "assistant" }),
})

this.screenshot = jsonrpc.ResourceTemplate({
	name = "screenshot",
	title = "Screenshot",
	uriTemplate = "morrowind://screenshot/{file}",
	description = "Read a published JPEG or PNG screenshot.",
	annotations = jsonrpc.Annotations({ "assistant" }),
})

--- Keep template listing order stable for deterministic client discovery.
---@type MCP.ResourceTemplate[]
this.definitions = {
	this.memoryEntity,
	this.screenshot,
}

return this
