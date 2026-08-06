local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")

--- Memory index for observations without a stable domain subject.
---@class MCP.Resources.Memory.Unattributed: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
local this = {}
setmetatable(this, { __index = base })

local descriptor = document.Descriptor(
    "memory/unattributed/index.json",
    "Unattributed Memory",
    "Observations that do not have a stable domain subject."
)
this.uri = descriptor.uri
this.link = document.Link(document.linkRel.unattributed, descriptor.uri, descriptor.title, descriptor.description)

--- Create the unattributed observation index after a loaded-game context exists.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Unattributed
function this.new(params)
    params.publishOnLoaded = true
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_unattributed" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Unattributed
    instance.entry = document.LiveEntry(descriptor, function()
        return instance:BuildDocument()
    end)
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ this.link })
    return instance
end

--- Build the traversal index for currently published unattributed observations.
---@return MCP.MemoryDocument
function this:BuildDocument()
    local links = self.manager:GetLinksForParent(descriptor.uri)
    return document.Document(
        document.documentType.index,
        document.dataType.unattributedObservations,
        descriptor.title,
        jsonrpc.object({ observation_count = table.size(links) }),
        {
            subject = document.Subject("memory_category", "unattributed", descriptor.title),
            scope = self.manager:GetScope(),
            links = links,
            source = document.Source(document.sourceKind.liveState, nil, nil, descriptor.description),
        }
    )
end

--- Refresh this index only when a direct child changes its published visibility.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
    if module.parentUri == descriptor.uri then
        self:MarkDirty()
    end
end

return this