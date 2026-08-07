local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")

--- Memory module that owns the root Memory index resource.
---@class MCP.Resources.Memory.Index: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field mainMenuActivatedCallback fun(e: uiActivatedEventData)?
---@field charGenFinishedCallback fun(e: table)?
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

--- Resolve the exclusive lifecycle state that determines how clients can use Memory resources.
---@return MCP.MemoryGameState
function this:GetGameState()
    if tes3.onMainMenu() then
        return document.gameState.mainMenu
    end
    if tes3.isCharGenRunning() then
        return document.gameState.characterGeneration
    end
    return document.gameState.inGame
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
            game_state = self:GetGameState(),
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

--- Mark the root index dirty when character generation reaches normal in-game state.
---@param e table?
function this:OnCharGenFinished(e)
    self:MarkDirty()
end

--- Mark the root index dirty when the title-screen menu becomes active.
---@param e uiActivatedEventData?
function this:OnMainMenuActivated(e)
    self:MarkDirty()
end

--- Register root-index lifecycle invalidators after the shared loaded-game handler.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if self.mainMenuActivatedCallback then
        return
    end
    self.mainMenuActivatedCallback = function(e) self:OnMainMenuActivated(e) end
    self.charGenFinishedCallback = function(e) self:OnCharGenFinished(e) end
    event.register(tes3.event.uiActivated, self.mainMenuActivatedCallback, { filter = "MenuMain" })
    event.register(tes3.event.charGenFinished, self.charGenFinishedCallback)
end

--- Unregister root-index lifecycle invalidators before releasing the Memory module.
function this:UnregisterEvent()
    if self.mainMenuActivatedCallback then
        event.unregister(tes3.event.uiActivated, self.mainMenuActivatedCallback, { filter = "MenuMain" })
        self.mainMenuActivatedCallback = nil
    end
    if self.charGenFinishedCallback then
        event.unregister(tes3.event.charGenFinished, self.charGenFinishedCallback)
        self.charGenFinishedCallback = nil
    end
    base.UnregisterEvent(self)
end

return this
