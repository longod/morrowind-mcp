local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local obj = require("morrowind-mcp.tes3.object")
local pathutil = require("morrowind-mcp.core.pathutil")
local mcp = require("morrowind-mcp.core.mcp")
local settings = require("morrowind-mcp.settings")
local logger = require("morrowind-mcp.logger").Get({ moduleName = "quest" })

local this = {}

-- TODO filter before current journal index

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

local started_relative = "game/started_quest.json"
local active_relative = "game/active_quest.json"
local finished_relative = "game/finished_quest.json"

local started_uri = pathutil.ToUri(started_relative, settings.uriScheme)
local active_uri = pathutil.ToUri(active_relative, settings.uriScheme)
local finished_uri = pathutil.ToUri(finished_relative, settings.uriScheme)

---@type MCP.ResourceEntry[]
local entries = {
    {
        descriptor = {
            name = started_relative,
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
            name = active_relative,
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
            name = finished_relative,
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

this.started_link = jsonrpc.ResourceLink(entries[1].descriptor.name, entries[1].descriptor.uri, entries[1].descriptor.title, entries[1].descriptor.description, entries[1].descriptor.mimeType)
this.active_link = jsonrpc.ResourceLink(entries[2].descriptor.name, entries[2].descriptor.uri, entries[2].descriptor.title, entries[1].descriptor.description, entries[2].descriptor.mimeType)
this.finished_link = jsonrpc.ResourceLink(entries[3].descriptor.name, entries[3].descriptor.uri, entries[3].descriptor.title, entries[3].descriptor.description, entries[3].descriptor.mimeType)

---@param e journalEventData
---@param resource MCP.ResourceManager
local function OnJournalUpdated(e, resource)
    local publishStarted = false
    local publishActive = false
    local publishFinished = false

    if e.new then
        publishStarted = true
        publishActive = true
        logger:debug("Quest publish by journal event: new")
    end

    if e.info then
        if e.info.isQuestFinished then
            publishActive = true
            publishFinished = true
            logger:debug("Quest publish by journal event: isQuestFinished")
        end
        if e.info.isQuestRestart then
            publishActive = true
            publishFinished = true
            logger:debug("Quest publish by journal event: isQuestRestart")
        end
    end

    if publishStarted then
        resource:PublishResource(entries[1])
    end
    if publishActive then
        resource:PublishResource(entries[2])
    end
    if publishFinished then
        resource:PublishResource(entries[3])
    end
end

---@param e scriptExecutedEventData
---@param resource MCP.ResourceManager
local function OnScriptExecuted(e, resource)

    if e.info and e.info.journalIndex ~= nil then
        local publishStarted = false
        local publishActive = false
        local publishFinished = false

        if e.info.journalIndex > 0 then
            publishStarted = true
            publishActive = true
            logger:debug("Quest publish by scriptExecuted event: journalIndex=%d", e.info.journalIndex)
        end

        if e.info.isQuestFinished then
            publishActive = true
            publishFinished = true
            logger:debug("Quest publish by scriptExecuted event: isQuestFinished")
        end
        if e.info.isQuestRestart then
            publishActive = true
            publishFinished = true
            logger:debug("Quest publish by scriptExecuted event: isQuestRestart")
        end

        if publishStarted then
            resource:PublishResource(entries[1])
        end
        if publishActive then
            resource:PublishResource(entries[2])
        end
        if publishFinished then
            resource:PublishResource(entries[3])
        end
    else
        -- logger:trace("Skip quest publish on scriptExecuted without journal info")
    end

end

---@param e loadedEventData
---@param resource MCP.ResourceManager
local function OnLoaded(e, resource)
    if e.newGame then
        -- unpublish all quest resources on new game.
        for _, entry in ipairs(entries) do
            resource:UnpublishResource(entry.descriptor.uri)
        end
        logger:debug("Quest resources unpublished for new game")
        return
    end

    -- re-publish all quest resources on game load.
    for _, entry in ipairs(entries) do
        resource:PublishResource(entry)
    end
    logger:debug("Quest resources republished after game load")
end

local journalCallback = nil ---@type fun(e : journalEventData)?
local scriptExecutedCallback = nil ---@type fun(e : scriptExecutedEventData)?
local loadedCallback = nil ---@type fun(e : loadedEventData)?

---@param resource MCP.ResourceManager
function this.RegisterEvent(resource)
    journalCallback = function(e)
        OnJournalUpdated(e, resource)
    end
    event.register(tes3.event.journal, journalCallback)
    scriptExecutedCallback = function(e)
        OnScriptExecuted(e, resource)
    end
    event.register(tes3.event.scriptExecuted, scriptExecutedCallback)
    loadedCallback = function(e)
        OnLoaded(e, resource)
    end
    event.register(tes3.event.loaded, loadedCallback)
    logger:debug("Quest event handlers registered")
end

function this.UnregisterEvent()
    if journalCallback then
        event.unregister(tes3.event.journal, journalCallback)
        journalCallback = nil
    end
    if scriptExecutedCallback then
        event.unregister(tes3.event.scriptExecuted, scriptExecutedCallback)
        scriptExecutedCallback = nil
    end
    if loadedCallback then
        event.unregister(tes3.event.loaded, loadedCallback)
        loadedCallback = nil
    end
    logger:debug("Quest event handlers unregistered")
end


return this
