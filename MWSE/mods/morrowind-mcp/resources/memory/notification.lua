local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local base = require("morrowind-mcp.resources.memory.imodule")
local document = require("morrowind-mcp.resources.memory.document")
local datetime = require("morrowind-mcp.util.datetime")
local mcpui = require("morrowind-mcp.util.mcpui")
local unattributed = require("morrowind-mcp.resources.memory.unattributed")

--- Memory module for transient notification UI that has no stable domain subject.
---@class MCP.Resources.Memory.Notification: MCP.Resources.MemoryModule
---@field entry MCP.MemoryResourceEntry
---@field data MCP.MemoryNotificationData
---@field observationIndex table<string, MCP.AnyMap>
---@field uiActivatedCallbacks table<string, fun(e: uiActivatedEventData)>
local this = {}
setmetatable(this, { __index = base })

local notifyMenus = {
    MenuNotify1 = true,
    MenuNotify2 = true,
    MenuNotify3 = true,
}
local notificationMessageId = tes3ui.registerID("MenuNotify_message")

local descriptor = document.Descriptor(
    "memory/unattributed/notifications.json",
    "Notification Memory",
    "Transient notification text observed without a stable domain subject."
)

local childLink = document.Link(
    document.linkRel.notifications,
    descriptor.uri,
    descriptor.title,
    descriptor.description
)

--- Return a compact observation timestamp for notification histories.
---@return MCP.MemoryObservationTimestamp
local function ObservationTimestamp()
    local timestamp = document.TimestampNow()
    return jsonrpc.object({
        system_time = timestamp.system_time,
        in_game_time_text = datetime.ToInGameShortText(timestamp.in_game_time),
    })
end

--- Build a collision-safe key for repeated notification observations.
---@param sourceMenu string
---@param text string
---@return string key
local function ObservationKey(sourceMenu, text)
    return string.format("%d:%s|%d:%s", string.len(sourceMenu), sourceMenu, string.len(text), text)
end

--- Create a notification module that becomes visible after its first captured notification.
---@param params MCP.Resources.MemoryModuleParams
---@return MCP.Resources.Memory.Notification
function this.new(params)
    params.parentUri = unattributed.uri
    params.logger = require("morrowind-mcp.logger").Get({ moduleName = "memory_notification" })
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.Resources.Memory.Notification
    instance:ClearData()
    instance.entry = document.SnapshotEntry(descriptor, instance:BuildDocument())
    instance.entries = jsonrpc.array({ instance.entry })
    instance.links = jsonrpc.array({ childLink })
    instance.uiActivatedCallbacks = {}
    return instance
end

--- Replace the exported snapshot with the current notification history.
---@return boolean captured
function this:CaptureSnapshot()
    return document.CaptureSnapshot(self.entry, self:BuildDocument())
end

--- Clear observations at the start of a new loaded-game scope.
function this:ClearData()
    self.observationIndex = {}
    self.data = jsonrpc.object({
        notification_count = 0,
        observations = jsonrpc.array(),
    })
    if self.entry then
        self:CaptureSnapshot()
    end
end

--- Record one visible non-MCP notification, aggregating repeated menu and text pairs.
---@param sourceMenu string
---@param text string
---@return boolean changed
function this:AddObservation(sourceMenu, text)
    local key = ObservationKey(sourceMenu, text)
    local duplicateObservation = self.observationIndex[key]
    local observedAt = ObservationTimestamp()
    if duplicateObservation then
        duplicateObservation.repeat_count = (duplicateObservation.repeat_count or 1) + 1
        duplicateObservation.last_observed_at = observedAt
        self:CaptureSnapshot()
        return false
    end

    local observation = jsonrpc.object({
        observed_at = observedAt,
        event = "ui_activated",
        source_menu = sourceMenu,
        text = text,
        repeat_count = 1,
    })
    self.data.notification_count = (self.data.notification_count or 0) + 1
    table.insert(self.data.observations, observation)
    self.observationIndex[key] = observation
    self:CaptureSnapshot()
    return true
end

--- Capture text from the three MWSE notification menus without inferring an actor or dialogue source.
---@param e uiActivatedEventData
function this:OnUiActivated(e)
    local sourceMenu = e and e.element and e.element.name
    if not sourceMenu or not notifyMenus[sourceMenu] then
        return
    end

    local messageElement = e.element:findChild(notificationMessageId)
    local text = messageElement and messageElement.text
    if not text or mcpui.isOwnNotify(text) then
        return
    end

    local changed = self:AddObservation(sourceMenu, text)
    if not self.published then
        self:Publish()
    end
    self.logger:debug(
        "Memory notification observed: notifications=%d changed=%s menu=%s",
        self.data.notification_count or 0,
        tostring(changed),
        sourceMenu
    )
end

--- Register one filtered callback for each MWSE notification menu.
function this:RegisterEvent()
    base.RegisterEvent(self)
    if table.size(self.uiActivatedCallbacks) > 0 then
        return
    end

    for menuName in pairs(notifyMenus) do
        local callback = function(e)
            self:OnUiActivated(e)
        end
        self.uiActivatedCallbacks[menuName] = callback
        event.register(tes3.event.uiActivated, callback, { filter = menuName })
    end
    self.logger:debug("Memory notification UI handlers registered")
end

--- Unregister every filtered notification menu callback.
function this:UnregisterEvent()
    for menuName, callback in pairs(self.uiActivatedCallbacks) do
        event.unregister(tes3.event.uiActivated, callback, { filter = menuName })
    end
    self.uiActivatedCallbacks = {}
    base.UnregisterEvent(self)
end

--- Reset notification history and keep the resource hidden until another notification is observed.
---@param e loadedEventData
function this:OnLoaded(e)
    self:ClearData()
    self:Unpublish()
end

--- Build the unattributed notification Memory document.
---@return MCP.MemoryDocument
function this:BuildDocument()
    return document.Document(
        document.documentType.observation,
        document.dataType.unattributedNotificationNotes,
        descriptor.title,
        self.data,
        {
            subject = document.Subject("unattributed", "notifications", descriptor.title),
            scope = self.manager:GetScope(),
            source = document.Source(document.sourceKind.event, nil, "uiActivated", descriptor.description),
        }
    )
end

return this