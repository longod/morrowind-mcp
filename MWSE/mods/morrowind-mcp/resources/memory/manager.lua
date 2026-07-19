local base = require("morrowind-mcp.core.imemory")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local modules = require("morrowind-mcp.resources.memory.modules")
local document = require("morrowind-mcp.resources.memory.document")
local settings = require("morrowind-mcp.settings")

--- Memory runtime architecture:
--- The resource manager owns the public MCP resource table, while this manager owns Memory coordination.
--- Static modules are registered once at startup and represent feature areas, not individual game objects.
--- Dynamic instance features, such as observed NPCs, publish their instance entries from inside one module.
--- The manager provides shared loaded-game scope, parent URI link aggregation, and visibility notifications.
--- Content refreshes dirty module caches; visibility changes additionally dirty related index resources.

--- Registry and scope coordinator for all Memory modules.
---@class MCP.Resources.MemoryManager: MCP.Resources.IMemory
---@field logger mwseLogger
---@field generation integer
---@field modules MCP.Resources.MemoryModule[]
---@field loadedCallback fun(e : loadedEventData)?
local this = {}
setmetatable(this, { __index = base })

-- Run before module loaded callbacks so scope generation is current when modules publish.
local loadedEventPriority = 100

--- Create every static Memory module; modules may manage dynamic resource entries internally.
---@param params table?
---@return MCP.Resources.MemoryManager
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.MemoryManager
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory" })
    instance.generation = 0
    instance.modules = jsonrpc.array()
    for _, module in ipairs(modules) do
        table.insert(instance.modules, module.new({ manager = instance, resource = instance.resource }))
    end
    instance.logger:debug("Memory manager created: modules=%d", table.size(instance.modules))
    return instance
end

--- Return the current loaded-game Memory scope.
---@return MCP.MemoryScope
function this:GetScope()
    return document.Scope(self.generation)
end

--- Collect links that all modules expose under a specific parent resource URI.
---@param parentUri MCP.ResourceUri?
---@return MCP.MemoryLink[]
function this:GetLinksForParent(parentUri)
    local links = jsonrpc.array()
    for _, module in ipairs(self.modules) do
        for _, link in ipairs(module:GetLinksForParent(parentUri)) do
            table.insert(links, link)
        end
    end
    return links
end

--- Collect top-level Memory links for the root Memory index.
---@return MCP.MemoryLink[]
function this:GetRootLinks()
    return self:GetLinksForParent(nil)
end

--- Invalidate every Memory module after broad state changes.
function this:MarkAllDirty()
    for _, module in ipairs(self.modules) do
        module:MarkDirty()
    end
end

--- Publish modules that explicitly expose resources as soon as Memory events are registered.
function this:PublishOnRegisterModules()
    local published = 0
    for _, module in ipairs(self.modules) do
        if module.publishOnRegister then
            module:Publish()
            published = published + 1
        end
    end
    self.logger:debug("Memory publish-on-register completed: published_modules=%d total_modules=%d", published, table.size(self.modules))
end

--- Save all current Memory entries to debug JSON files without publishing those files as resources.
---@param rootDir string?
---@return MCP.MemoryDebugSaveResult[]
function this:SaveDebugDocuments(rootDir)
    local saveRootDir = rootDir or settings.memoryDebugDumpDir
    local saved = jsonrpc.array()
    local seen = {}
    for _, module in ipairs(self.modules) do
        for _, entry in ipairs(module.entries or {}) do
            local uri = entry.descriptor and entry.descriptor.uri
            if uri and not seen[uri] then
                seen[uri] = true
                local result = document.SaveEntry(entry, saveRootDir)
                if result then
                    table.insert(saved, result)
                    self.logger:trace("Saved Memory debug document: uri=%s file=%s bytes=%d", result.uri, result.file_path, result.bytes)
                else
                    self.logger:warn("Failed to save Memory debug document: %s", uri)
                end
            end
        end
    end
    self.logger:debug("Saved Memory debug documents: count=%d dir=%s", table.size(saved), saveRootDir)
    return saved
end

--- Notify modules when another module becomes visible or hidden.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
    self.logger:debug("Memory module visibility changed: published=%s parent_uri=%s", tostring(module.published), tostring(module.parentUri))
    for _, candidate in ipairs(self.modules) do
        if candidate ~= module then
            candidate:OnModuleVisibilityChanged(module)
        end
    end
end

--- Advance scope generation for each loaded-game transition.
---@param e loadedEventData
function this:OnLoaded(e)
    self.generation = self.generation + 1
    self.logger:debug("Memory scope generation advanced after game load: generation=%d", self.generation)
end

--- Register manager and module event handlers, then publish startup-visible modules.
function this:RegisterEvent()
    if not self.loadedCallback then
        self.loadedCallback = function(e)
            self:OnLoaded(e)
        end
        -- The manager must advance scope generation before modules publish documents for the same load event.
        event.register(tes3.event.loaded, self.loadedCallback, { priority = loadedEventPriority })
    end

    for _, module in ipairs(self.modules) do
        module:RegisterEvent()
    end

    self:PublishOnRegisterModules()
    self.logger:debug("Memory event handlers registered")
end

--- Unregister module and manager event handlers during resource manager release.
function this:UnregisterEvent()
    for _, module in ipairs(self.modules) do
        module:UnregisterEvent()
    end

    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end
    self.logger:debug("Memory event handlers unregistered")
end

return this
