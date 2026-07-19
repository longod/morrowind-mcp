local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local document = require("morrowind-mcp.resources.memory.document")

--- Construction options shared by all Memory modules.
---@class MCP.Resources.MemoryModuleParams
---@field manager MCP.Resources.MemoryManager?
---@field resource MCP.IResourceManager
---@field publishOnRegister boolean?
---@field publishOnLoaded boolean?
---@field parentUri MCP.ResourceUri?
---@field logger mwseLogger?

--- Base class for one Memory publishing unit, which may own one entry or many dynamic entries.
---@class MCP.Resources.MemoryModule
---@field manager MCP.Resources.MemoryManager
---@field resource MCP.IResourceManager
---@field entries MCP.MemoryResourceEntry[]
---@field links MCP.MemoryLink[]
---@field published boolean
---@field publishOnRegister boolean
---@field publishOnLoaded boolean
---@field parentUri MCP.ResourceUri?
---@field loadedCallback fun(e : loadedEventData)?
---@field logger mwseLogger?
local this = {}

--- Create a Memory module with no resources, no links, and explicit publish policy flags.
---@param params MCP.Resources.MemoryModuleParams?
---@return MCP.Resources.MemoryModule
function this.new(params)
    params = params or {}
    local instance = {
        manager = params.manager,
        resource = params.resource,
        entries = jsonrpc.array(),
        links = jsonrpc.array(),
        published = false,
        publishOnRegister = params.publishOnRegister == true,
        publishOnLoaded = params.publishOnLoaded == true,
        parentUri = params.parentUri,
        logger = params.logger,
    }
    setmetatable(instance, { __index = this })
    return instance
end

--- Return links exposed by this module only while it is visible to clients.
---@return MCP.MemoryLink[]
function this:GetLinks()
    if not self.published then
        return jsonrpc.array()
    end
    return self.links or jsonrpc.array()
end

--- Return links that this module contributes under the requested parent resource URI.
---@param parentUri MCP.ResourceUri?
---@return MCP.MemoryLink[]
function this:GetLinksForParent(parentUri)
    if self.parentUri ~= parentUri then
        return jsonrpc.array()
    end
    return self:GetLinks()
end

--- Invalidate all Memory entries owned by this module.
function this:MarkDirty()
    local count = 0
    for _, entry in ipairs(self.entries or {}) do
        document.MarkDirty(entry)
        count = count + 1
    end
    if self.logger then
        self.logger:debug("Memory module marked dirty: entries=%d", count)
    end
end

--- React to another module becoming visible or hidden; subclasses dirty parent indexes here.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
end

--- Publish current entries and invalidate cached Memory content for the next read.
function this:Publish()
    local wasPublished = self.published
    self:MarkDirty()
    local count = 0
    for _, entry in ipairs(self.entries or {}) do
        self.resource:PublishResource(entry)
        count = count + 1
    end
    self.published = true
    if self.logger then
        self.logger:debug("Memory module published: entries=%d was_published=%s", count, tostring(wasPublished))
    end
    if self.manager and not wasPublished then
        self.manager:OnModuleVisibilityChanged(self)
    end
end

--- Unpublish current entries and invalidate cached Memory content before the next publish.
function this:Unpublish()
    local wasPublished = self.published
    self:MarkDirty()
    local count = 0
    for _, entry in ipairs(self.entries or {}) do
        self.resource:UnpublishResource(entry.descriptor.uri)
        count = count + 1
    end
    self.published = false
    if self.logger then
        self.logger:debug("Memory module unpublished: entries=%d was_published=%s", count, tostring(wasPublished))
    end
    if self.manager and wasPublished then
        self.manager:OnModuleVisibilityChanged(self)
    end
end

--- Register events common to every Memory module.
function this:RegisterEvent()
    if self.loadedCallback then
        return
    end

    self.loadedCallback = function(e)
        self:OnLoaded(e)
    end
    event.register(tes3.event.loaded, self.loadedCallback)
    if self.logger then
        self.logger:debug("Memory module loaded handler registered: publish_on_loaded=%s", tostring(self.publishOnLoaded))
    end
end

--- Unregister events common to every Memory module.
function this:UnregisterEvent()
    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
        if self.logger then
            self.logger:debug("Memory module loaded handler unregistered")
        end
    end
end

--- Publish or hide this module after a game load according to its publish policy.
---@param e loadedEventData
function this:OnLoaded(e)
    if self.logger then
        self.logger:debug("Memory module loaded event: publish_on_loaded=%s new_game=%s", tostring(self.publishOnLoaded), tostring(e and e.newGame == true))
    end
    if self.publishOnLoaded then
        self:Publish()
        return
    end

    self:Unpublish()
end

return this
