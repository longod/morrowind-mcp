local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local obj = require("morrowind-mcp.tes3.object")
local document = require("morrowind-mcp.resources.memory.document")

--- Memory module for the single current player entity.
---@class MCP.Resources.Memory.Player: MCP.Resources.MemoryModule
---@field playerEntry MCP.MemoryResourceEntry
local this = {}
setmetatable(this, { __index = base })

local playerDescriptor = document.Descriptor(
    "memory/player/index.json",
    "Player Memory",
    "Memory entity for the current player."
)

this.link = document.Link(document.linkRel.player, playerDescriptor.uri, playerDescriptor.title, playerDescriptor.description)

--- Read fragile TES3 fields without letting menu or load-state errors break the Memory response.
---@param callback fun(): any
---@return any
local function ReadValue(callback)
    local ok, result = pcall(callback)
    if ok then
        return result
    end
    return nil
end

--- Create the player entity module; it appears after game load and owns player child links.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Player
function this.new(params)
    params.publishOnLoaded = true
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Player
    instance.playerEntry = document.LiveEntry(playerDescriptor, function()
        return instance:BuildPlayerDocument()
    end)
    instance.entries = jsonrpc.array({
        instance.playerEntry,
    })
    instance.links = jsonrpc.array({ this.link })
    return instance
end

--- Build a compact player Memory entity without embedding large linked collections.
---@return MCP.MemoryDocument
function this:BuildPlayerDocument()
    local playerObject = ReadValue(function() return tes3.player end)
    local mobilePlayer = ReadValue(function() return tes3.mobilePlayer end)
    local race = ReadValue(function() return playerObject and playerObject["race"] end)
    local class = ReadValue(function() return playerObject and playerObject["class"] end)
    local subjectType = document.SubjectTypeFromObject(playerObject)
    local data = jsonrpc.object({
        available = not tes3.onMainMenu() and mobilePlayer ~= nil,
        name = ReadValue(function() return playerObject and playerObject["name"] end),
        race = ReadValue(function() return race and race["name"] end),
        class = ReadValue(function() return class and class["name"] end),
        level = ReadValue(function() return mobilePlayer and mobilePlayer["level"] end),
        health = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer["health"] end)),
        magicka = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer["magicka"] end)),
        fatigue = obj.tes3statistic(ReadValue(function() return mobilePlayer and mobilePlayer["fatigue"] end)),
    })
    local links = self.manager:GetLinksForParent(playerDescriptor.uri)

    return document.Document(
        document.documentType.entity,
        document.dataType.playerSummary,
        playerDescriptor.title,
        data,
        {
            subject = subjectType and document.Subject(subjectType, document.subjectId.player, "Player") or nil,
            scope = self.manager:GetScope(),
            links = links,
            source = document.Source(document.sourceKind.liveState, nil, nil, "Current player state summary."),
        }
    )
end

--- Player links change only when a child module under the player resource becomes visible or hidden.
---@param module MCP.Resources.MemoryModule
function this:OnModuleVisibilityChanged(module)
    if module.parentUri == playerDescriptor.uri then
        self:MarkDirty()
    end
end

return this