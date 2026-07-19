local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")

--- Memory module that owns the root Memory index resource.
---@class MCP.Resources.Memory.Index: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/index.json",
    "Memory Index",
    "Root index of Morrowind memory resources."
)

--- Create the root index module; it is visible from startup as the Memory entry point.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Index
function this.new(params)
    params.publishOnRegister = true
    params.publishOnLoaded = true
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_index" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Index
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    return instance
end

--- Build the root Memory index with links only to published Memory resources.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local links = self.manager:GetRootLinks()
    return document.Document(
        document.documentType.index,
        document.dataType.memoryRoots,
        descriptor.title,
        jsonrpc.object({
            root_count = table.size(links),
        }),
        {
            scope = self.manager:GetScope(),
            links = links,
            source = document.Source(document.sourceKind.liveState, nil, nil, "Memory resource registry."),
        }
    )
end

--- Root links change only when a top-level Memory module becomes visible or hidden.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
    if module.parentUri == nil then
        self:MarkDirty()
    end
end

return this
