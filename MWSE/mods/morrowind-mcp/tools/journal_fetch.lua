local base = require("morrowind-mcp.core.itool")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local datetime = require("morrowind-mcp.datetime")
local mcp = require("morrowind-mcp.core.mcp")
local pathutil = require("morrowind-mcp.core.pathutil")
local settings = require("morrowind-mcp.settings")
local journal = require("morrowind-mcp.resources.journal")

-- improving resource management then maybe no nessessary to fetch some data.
-- possibly too many tools cause dump AI decision.
-- but manual fetch is useful for debugging and testing.


---@class MCP.JournalFetch: MCP.ITool
---@field logger mwseLogger
---@field resource MCP.ResourceManager TODO use MCP.IResourceManager
---@field journalCallback fun(e : journalEventData)
---@field loadedCallback fun(e : loadedEventData)
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.JournalFetch
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.JournalFetch
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "journal_fetch" })
    instance.definition = jsonrpc.Tool({
        name = "journal-fetch",
        description =
        "Fetch active journal entries.",
        inputSchema = jsonrpc.InputSchema(
        -- active,
        -- finished, unfinished
        ),
        outputSchema = jsonrpc.OutputSchema(
            {
                entries = jsonrpc.JsonArraySchema(),
                current_time = jsonrpc.JsonObjectSchema(),
            }
        ),
        annotations = jsonrpc.ToolAnnotations(nil, true, false)
    })

    instance.journalCallback = function(e)
        instance:OnJournalUpdated(e)
    end
    event.register(tes3.event.journal, instance.journalCallback)
    instance.loadedCallback = function(e)
        instance:OnLoaded(e)
    end
    event.register(tes3.event.loaded, instance.loadedCallback)
    return instance
end

function this:Release()
    if self.journalCallback then
        event.unregister(tes3.event.journal, self.journalCallback)
        self.journalCallback = nil
    end
    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end
end


function this:CanExecute(params)
    if tes3.onMainMenu() then
        return false
    end
    -- exclude tutorial?
    return true
end

function this:Execute(params, context)
    -- load <Morrowind>/Journal.htm
    -- perphaps, we can not access to journal entries in a save data.
    -- "JOUR"  recourds in ess stores just html same as journal.htm.
    -- https://en.uesp.net/morrow/tech/mw_esm.txt

    -- https://pt.uesp.net/wiki/Morrowind_Mod:Text_Defines
    -- https://wiki.openmw.org/index.php?title=Research:Dialogue_and_Messages
    -- hyperlink (@*#): https://github.com/OpenMW/openmw/blob/master/apps/openmw/mwdialogue/keywordsearch.cpp#L140

    local entries = journal.ReadJournal()
    if not entries then
        local errorContent = jsonrpc.TextContent("Failed to read journal entries.")
        return jsonrpc.CallToolResult(errorContent, nil, true)
    end

    local currentTime = datetime.InGameNow()
    local structuredContent = jsonrpc.object({
        entries = entries,
        current_time = currentTime,
    })
    return jsonrpc.CallToolResult(nil, structuredContent)

end


---@param e journalEventData
function this:OnJournalUpdated(e)
    -- can execute?

    self.logger:debug("Journal updated")
    -- I considered journal.htm is not written yet. because event data has claim to be updated, be able to block.
    -- but journal.htm is already written. So I can read journal.htm now.

    --- resource descriptor
    ---@type MCP.Resource
    local r = {
        name = "journal.json",
        title = "Journal",
        uri = pathutil.ToUri("game/journal.json", settings.uriScheme),
        description = "Current player's journal entries.",
        mimeType = mcp.mimeType.application_json,
        annotations = jsonrpc.Annotations(nil, nil, datetime.UTCNow()),
        -- size = nil,
    }
    self.resource:PublishResource(
    r,
    journal.ContentHandler
    )
    --]]
end

---@param e loadedEventData
function this:OnLoaded(e)
    -- can execute?

    -- new game is not write journal.htm yet.
    if e.newGame then
        self.resource:UnpublishResource(pathutil.ToUri("game/journal.json", settings.uriScheme))
        return
    end

    self.logger:debug("Game loaded")
    --- resource descriptor
    ---@type MCP.Resource
    local r = {
        name = "journal.json",
        title = "Journal",
        uri = pathutil.ToUri("game/journal.json", settings.uriScheme), -- TODO wrapper?, injected scheme
        description = "Current player's journal entries.",
        mimeType = mcp.mimeType.application_json,
        annotations = jsonrpc.Annotations(nil, nil, datetime.UTCNow()),
        -- size = nil,
    }
    self.resource:PublishResource(
    r,
    journal.ContentHandler
    )
end

return this
