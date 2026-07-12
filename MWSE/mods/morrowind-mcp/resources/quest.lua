local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local pathutil = require("morrowind-mcp.core.pathutil")
local mcp = require("morrowind-mcp.core.mcp")
local settings = require("morrowind-mcp.settings")

local this = {}

---@param quest tes3quest
---@param isStarted boolean
---@param isActive boolean
---@param isFinished boolean
---@return boolean
local function Fileter(quest, isStarted, isActive, isFinished)
    if isStarted ~= nil and quest.isStarted ~= isStarted then
        return false
    end
    if isActive ~= nil and quest.isActive ~= isActive then
        return false
    end
    if isFinished ~= nil and quest.isFinished ~= isFinished then
        return false
    end
    return true
end


---@param isStarted boolean?
---@param isActive boolean?
---@param isFinished boolean?
---@return MCP.AnyMap[]?
function this.FindQuests(isStarted, isActive, isFinished)
    if tes3.onMainMenu() then
        return nil
    end

    if not tes3.worldController then
        return nil
    end

    local quests = tes3.worldController.quests
    if not quests then
        return nil
    end
    local array = jsonrpc.array(table.size(quests))
    for _, quest in ipairs(quests) do
        if quest:isValid() then
            if Fileter(quest, isStarted, isActive, isFinished) then
                local o = obj.tes3quest(quest)
                if o then
                    table.insert(array, o)
                end
            end
        end
    end
    return array
end

---@param desc MCP.Resource
---@return MCP.ResourceContent[]
function this.GetContents(desc, isStarted, isActive, isFinished)
    local entries = this.FindQuests(isStarted, isActive, isFinished)
    local content = jsonrpc.TextResourceContents(desc.uri, json.encode(entries, { indent = false }), desc.mimeType)
    return { content }
end

local started_uri = pathutil.ToUri("game/started_quest.json", settings.uriScheme)
local active_uri = pathutil.ToUri("game/active_quest.json", settings.uriScheme)
local finished_uri = pathutil.ToUri("game/finished_quest.json", settings.uriScheme)

-- TODO with handler?
---@type MCP.ResourceEntry[]
this.entries = {
    {
        descriptor = {
            name = "started_quest.json",
            title = "Started Quests",
            uri = started_uri,
            description = "Current player's started quest entries.",
            mimeType = mcp.mimeType.application_json,
            annotations = jsonrpc.Annotations(nil, nil, nil),
        },
        handler = function (desc)
            return this.GetContents(desc, true, nil, nil)
        end,
    },
    {
        descriptor = {
            name = "active_quest.json",
            title = "Active Quests",
            uri = active_uri,
            description = "Current player's active quest entries.",
            mimeType = mcp.mimeType.application_json,
            annotations = jsonrpc.Annotations(nil, nil, nil),
        },
        handler = function (desc)
            return this.GetContents(desc, nil, true, nil)
        end,
    },
    {
        descriptor = {
            name = "finished_quest.json",
            title = "Finished Quests",
            uri = finished_uri,
            description = "Current player's finished quest entries.",
            mimeType = mcp.mimeType.application_json,
            annotations = jsonrpc.Annotations(nil, nil, nil),
        },
        handler = function (desc)
            return this.GetContents(desc, nil, nil, true)
        end,
    },
}

return this
