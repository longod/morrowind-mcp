local base = require("morrowind-mcp.core.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")
local pathutil = require("morrowind-mcp.core.pathutil")
local inputvalidator = require("morrowind-mcp.core.input_validator")
local toolvalidator = require("morrowind-mcp.core.tool_validator")
local promptvalidator = require("morrowind-mcp.core.prompt_validator")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")
local resourceManager = require("morrowind-mcp.resources.resource")
local target = require("morrowind-mcp.util.target")
local pathfinding = require("morrowind-mcp.navigation.pathfinding")
local navigator = require("morrowind-mcp.navigation.navigator")
local mcpui = require("morrowind-mcp.util.mcpui")
local cellutil = require("morrowind-mcp.tes3.cell")
local terrainGridManager = require("morrowind-mcp.navigation.terrain.manager")
local debugGeometryProbe = require("morrowind-mcp.navigation.debug_geometry_probe")
local visualizerModule = require("morrowind-mcp.navigation.visualizer")
local ui_action = require("morrowind-mcp.util.ui_action")
local input_action = require("morrowind-mcp.util.input_action")

-- TODO split implementations, such as session manager?

---@type Socket.Module
local socket = require("socket")

local maxResponseLogLength = config.development.debug and 2048 or 256
local maxNotificationQueueSize = 128
local serverPingIntervalSeconds = 60
local serverPingTimeoutSeconds = 30
local sessionIdleTimeoutSeconds = 300
local protocolVersion = "2025-11-25"

---@param response string?
---@return string
local function FormatResponseForLog(response)
    if not response then
        return "nil"
    end

    if #response <= maxResponseLogLength then
        local r, _ = string.gsub(response, "\r", "")
        return r
    end

    local r, _ = string.gsub(string.sub(response, 1, maxResponseLogLength), "\r", "")
    return r .. "[...too long]"
end

---@param error MCP.Error?
---@return string
local function FormatJsonRpcError(error)
    if not error then
        return "nil"
    end
    return string.format("%s:%s", tostring(error.code), tostring(error.message))
end


local function spairs(t, order)
    local keys = table.new(table.size(t), 0)
    for k in pairs(t) do
        keys[#keys + 1] = k
    end

    if order then
        table.sort(keys, function(a, b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- use coroutine?
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end


---@class MCP.ClientRequest
---@field client Socket.TcpClient?
---@field http_request Http.Request
---@field json_request MCP.JSONRPCRequest|MCP.JSONRPCNotification?

---@class MCP.ServerResponse
---@field http_response Http.ResponseStatusCodes
---@field http_headers table<string, string>?
---@field json_result table?
---@field json_error MCP.Error?
---@field request_id MCP.RequestId?
---@field no_body boolean?
---@field keep_open boolean?
---@field response_sent boolean?

---@class MCP.MethodResult
---@field http_response Http.ResponseStatusCodes -- TODO simplify 200, 202, 400 or more?
---@field http_headers table<string, string>?
---@field result MCP.Result?
---@field error MCP.Error?

---@class MCP.HttpSession
---@field id string
---@field initialized boolean
---@field sseClient Socket.TcpClient?
---@field notificationQueue string[]
---@field pendingServerRequests table<string, MCP.PendingServerRequest>
---@field resourceSubscriptions table<string, boolean>
---@field nextEventId integer
---@field nextServerRequestId integer
---@field lastServerPingAt integer
---@field lastAccessedAt integer

---@class MCP.PendingServerRequest
---@field method MCP.Method|string
---@field createdAt integer

---@class MCP.MwseHttpServer : MCP.IServer
---@field logger mwseLogger
---@field server Socket.TcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field loadedCallback fun(e : loadedEventData)?
---@field debugKeyCallback fun(e : keyDownEventData)?
---@field debugNavigationKeyCallback fun(e : keyDownEventData)?
---@field hostname string
---@field port integer
---@field httpHeaders table<string, string> must headers
---@field requestHandlers table<string, fun(self: MCP.MwseHttpServer, request: MCP.ClientRequest): MCP.ServerResponse?>
---@field methodHandlers table<string, fun(self: MCP.MwseHttpServer, params: MCP.RequestParams, request: MCP.ClientRequest?): MCP.MethodResult>
---@field prompts table<string, MCP.IPrompt>
---@field tools table<string, MCP.ITool>
---@field resource MCP.ResourceManager
---@field sessions table<string, MCP.HttpSession>
---@field nextSessionIndex integer
---@field pathfinding MCP.Pathfinding
---@field activeNavigator MCP.Navigator?
---@field terrainGridManager MCP.TerrainGridManager
---@field visualizer MCP.NavigationVisualizer?
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.MwseHttpServer
function this.new(params)
    jsonrpc.SetPrimitivePrefix(settings.name_prefix, settings.title_prefix, settings.description_prefix)

    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.MwseHttpServer
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "http_server" })
    instance.hostname = instance.hostname or settings.defaultConfig.server.address
    instance.port = instance.port or settings.defaultConfig.server.port
    instance.httpHeaders = {}
    instance.resource = resourceManager.new()
    local function RequestVisualizationRefresh(layer, cellId)
        if instance.visualizer then
            instance.visualizer:RequestRefresh(layer, cellId)
        end
    end
    instance.pathfinding = pathfinding.new({ onChanged = RequestVisualizationRefresh })
    instance.terrainGridManager = terrainGridManager.new({ onChanged = RequestVisualizationRefresh })
    instance.activeNavigator = nil
    instance.sessions = {}
    instance.nextSessionIndex = 0
    instance.requestHandlers = {
        [http.method.POST] = instance.OnPOST,
        [http.method.GET] = instance.OnGET,
        [http.method.DELETE] = instance.OnDELETE,
        [http.method.OPTIONS] = instance.OnOPTIONS,
    }
    -- or split sub-category
    instance.methodHandlers = {
        [mcp.method.initialize] = instance.OnInitialize,
        [mcp.method.notifications_cancelled] = instance.OnCancelledNotification,
        [mcp.method.notifications_initialized] = instance.OnInitializedNotification,
        [mcp.method.ping] = instance.OnPing,
        [mcp.method.logging_setlevel] = instance.OnLoggingSetLevel,
        [mcp.method.prompts_list] = instance.OnPromptsList,
        [mcp.method.prompts_get] = instance.OnPromptsGet,
        [mcp.method.completion_complete] = instance.OnCompletionComplete,
        [mcp.method.resources_list] = instance.OnResourcesList,
        [mcp.method.resources_templates_list] = instance.OnResourcesTemplatesList,
        [mcp.method.resources_read] = instance.OnResourcesRead,
        [mcp.method.resources_subscribe] = instance.OnResourcesSubscribe,
        [mcp.method.resources_unsubscribe] = instance.OnResourcesUnsubscribe,
        [mcp.method.tools_list] = instance.OnToolsList,
        [mcp.method.tools_call] = instance.OnToolsCall,
    }
    instance:LoadPrompts()
    instance:LoadTools()
    return instance
end

--- Create the debug-only navigation visualizer when development debugging is enabled.
---@param self MCP.MwseHttpServer
function this:CreateNavigationVisualizer()
    if config.development.debug then
        self.visualizer = visualizerModule.new(self.pathfinding, self.terrainGridManager)
    end
end

--- Advance or refresh the optional debug-only navigation visualizer.
---@param self MCP.MwseHttpServer
---@param refresh boolean?
function this:UpdateNavigationVisualizer(refresh)
    if self.visualizer then
        if refresh then
            self.visualizer:Refresh()
        else
            self.visualizer:Tick()
        end
    end
end

--- Detach and release the optional debug-only navigation visualizer.
---@param self MCP.MwseHttpServer
function this:ReleaseNavigationVisualizer()
    if self.visualizer then
        self.visualizer:Remove()
        self.visualizer = nil
    end
end

--- Replace any active route and begin navigation through the shared pathfinding graph.
---@param destination MCP.PathfindingLocator
---@return boolean
---@return string?
---@return MCP.NavigatorStartResult?
function this:StartPlayerNavigation(destination)
    if self.activeNavigator then
        self.activeNavigator:Release()
        self.activeNavigator = nil
    end
    local instance = navigator.new({ pathfinding = self.pathfinding })
    local ok, message, navigation = instance:Start(destination)
    if not ok then
        instance:Release()
        return false, message
    end
    self.activeNavigator = instance
    return true, nil, navigation
end

--- Return whether the server currently owns a running player navigation route.
---@return boolean
function this:HasActivePlayerNavigation()
    return self.activeNavigator ~= nil and self.activeNavigator.isActive
end

--- Cancel the server-owned route and discard it so a later request starts from a clean state.
---@return boolean cancelled
function this:CancelPlayerNavigation()
    if not self:HasActivePlayerNavigation() then
        self.activeNavigator = nil
        return false
    end

    self.activeNavigator:Cancel("Cancelled by tool request.")
    self.activeNavigator = nil
    return true
end

---@return string
function this:GenerateSessionId()
    -- The MCP session id must be visible ASCII; uniqueness only needs to hold for this local process.
    self.nextSessionIndex = self.nextSessionIndex + 1
    local sessionId = string.format("mwmcp-%d-%d-%d", os.time(), math.random(0, 999999999), self.nextSessionIndex)
    while self.sessions[sessionId] do
        self.nextSessionIndex = self.nextSessionIndex + 1
        sessionId = string.format("mwmcp-%d-%d-%d", os.time(), math.random(0, 999999999), self.nextSessionIndex)
    end
    return sessionId
end

---@return integer
function this:CountSSEClients()
    local count = 0
    for _, session in pairs(self.sessions) do
        if session.sseClient then
            count = count + 1
        end
    end
    return count
end

---@return MCP.HttpSession
function this:CreateSession()
    -- Keep transport state separate from game state so sessions can be replaced without side effects.
    local sessionId = self:GenerateSessionId()
    ---@type MCP.HttpSession
    local session = {
        id = sessionId,
        initialized = false,
        sseClient = nil,
        notificationQueue = {},
        pendingServerRequests = {},
        resourceSubscriptions = {},
        nextEventId = 0,
        nextServerRequestId = 0,
        lastServerPingAt = os.time(),
        lastAccessedAt = os.time(),
    }
    self.sessions[sessionId] = session
    self.logger:debug("Session created: %s (sessions=%d, sseClients=%d)", sessionId, table.size(self.sessions),
        self:CountSSEClients())
    return session
end

---@param session MCP.HttpSession
function this:TouchSession(session)
    session.lastAccessedAt = os.time()
end

---@param session MCP.HttpSession
---@return boolean
function this:IsSessionExpired(session)
    return os.difftime(os.time(), session.lastAccessedAt) >= sessionIdleTimeoutSeconds
end

---@param sessionId string
---@return boolean
function this:DeleteSession(sessionId)
    local session = self.sessions[sessionId]
    if not session then
        return false
    end

    self:RemoveSSEClient(session)
    self.sessions[sessionId] = nil
    self.logger:debug("Session deleted: %s (sessions=%d, sseClients=%d)", sessionId, table.size(self.sessions),
        self:CountSSEClients())
    return true
end

function this:CloseExpiredSessions()
    for sessionId, session in pairs(self.sessions) do
        if self:IsSessionExpired(session) then
            self.logger:debug("Session expired: %s (idleSeconds=%d, queuedNotifications=%d, hasSseClient=%s)",
                sessionId, os.difftime(os.time(), session.lastAccessedAt), table.size(session.notificationQueue),
                tostring(session.sseClient ~= nil))
            self:DeleteSession(sessionId)
        end
    end
end

---@param request Http.Request
---@return string?
function this:GetSessionId(request)
    return request.headers[http.mcp_header.mcp_session_id]
end

--- Reject malformed session headers before looking them up as opaque session identifiers.
---@param request Http.Request
---@return boolean
function this:HasValidSessionId(request)
    local sessionId = self:GetSessionId(request)
    if not sessionId then
        return true
    end

    -- Session ids are generated by GenerateSessionId and contain only the prefix, digits, and hyphens.
    return type(sessionId) == "string" and sessionId:match("^mwmcp%-%d+%-%d+%-%d+$") ~= nil
end

---@param request Http.Request
---@return MCP.HttpSession?
function this:GetSession(request)
    local sessionId = self:GetSessionId(request)
    if not sessionId then
        return nil
    end
    local session = self.sessions[sessionId]
    if session then
        self:TouchSession(session)
    end
    return session
end

---@param request Http.Request
---@return boolean
function this:IsAllowedOrigin(request)
    -- Origin validation is a Streamable HTTP DNS-rebinding mitigation for local servers.
    local origin = request.headers[http.header.origin]
    if not origin or origin == "" then
        return true
    end

    -- TODO validate more strictly, e.g. http://localhost.othersite.example should not be allowed.
    local lowerOrigin = origin:lower()
    local lowerHostname = tostring(self.hostname):lower()
    return lowerOrigin:find("://localhost", 1, true) ~= nil
        or lowerOrigin:find("://127.0.0.1", 1, true) ~= nil
        or lowerOrigin:find("://" .. lowerHostname, 1, true) ~= nil
end

---@param request Http.Request
---@return boolean
function this:IsSupportedProtocolVersion(request)
    -- Missing protocol version is tolerated for compatibility, but invalid explicit versions are rejected.
    local version = request.headers[http.mcp_header.mcp_protocol_version]
    return not version or version == protocolVersion
end

---@param request Http.Request
---@return boolean
function this:IsSupportedPostContentType(request)
    local contentType = request.headers[http.header.content_type]
    return http.AcceptsContentType(contentType, http.content_type.json)
end

---@param uri any
---@return boolean
function this:IsValidResourceUri(uri)
    return type(uri) == "string" and pathutil.FromUri(uri, settings.uriScheme) ~= nil
end

---@param params MCP.RequestParams?
---@return MCP.ProgressToken?
function this:GetProgressToken(params)
    if not params then
        return nil
    end
    if params._meta and params._meta.progressToken ~= nil then
        return params._meta.progressToken
    end
    return params.progressToken
end

---@param session MCP.HttpSession
---@return MCP.RequestId
function this:GenerateServerRequestId(session)
    session.nextServerRequestId = session.nextServerRequestId + 1
    return string.format("server-%d", session.nextServerRequestId)
end

---@param request Http.Request
---@return boolean
function this:IsAcceptedPostResponseContentType(request)
    -- MCP POST requests can receive a JSON response, or an SSE stream in richer implementations.
    local accept = request.headers[http.header.accept]
    return not accept
        or http.AcceptsContentType(accept, http.content_type.json)
        or http.AcceptsContentType(accept, http.content_type.event_stream)
end

---@param session MCP.HttpSession
function this:RemoveSSEClient(session)
    if session.sseClient then
        pcall(function() session.sseClient:close() end)
        session.sseClient = nil
        self.logger:debug("SSE client removed: %s (sessions=%d, sseClients=%d)", session.id, table.size(self.sessions),
            self:CountSSEClients())
    end
end

---@param session MCP.HttpSession
---@param client Socket.TcpClient
function this:ReplaceSSEClient(session, client)
    -- Treat a duplicate GET for the same session as a reconnect; newest stream wins.
    local hadSSEClient = session.sseClient ~= nil
    self:RemoveSSEClient(session)
    client:settimeout(0)
    session.sseClient = client
    session.lastServerPingAt = os.time()
    if hadSSEClient then
        self.logger:debug("SSE client replaced: %s (sessions=%d, sseClients=%d)", session.id, table.size(self.sessions),
            self:CountSSEClients())
    end
    self.logger:debug("SSE client added: %s (sessions=%d, sseClients=%d)", session.id, table.size(self.sessions),
        self:CountSSEClients())
end

---@param session MCP.HttpSession
---@param message string
---@param label string
---@param dedupe boolean
function this:EnqueueSessionMessage(session, message, label, dedupe)
    -- Queue by session rather than socket so unsent SSE messages survive reconnects.
    if dedupe then
        for _, queuedMessage in ipairs(session.notificationQueue) do
            if queuedMessage == message then
                self.logger:debug("Skipped duplicate queued message: %s (session=%s)", label, session.id)
                return
            end
        end
    end

    table.insert(session.notificationQueue, message)
    local droppedCount = 0
    while table.size(session.notificationQueue) > maxNotificationQueueSize do
        table.remove(session.notificationQueue, 1)
        droppedCount = droppedCount + 1
    end
    if droppedCount > 0 then
        self.logger:warn("Dropped %d queued message(s) for session %s", droppedCount, session.id)
    end
end

---@param session MCP.HttpSession
---@param method MCP.Method|string
---@return boolean
function this:CanSendServerMessage(session, method)
    if session.initialized then
        return true
    end
    return method == mcp.method.ping or method == mcp.method.notifications_message
end

---@param session MCP.HttpSession
---@param method MCP.Method|string
---@param params table?
function this:EnqueueNotification(session, method, params)
    if not self:CanSendServerMessage(session, method) then
        self.logger:debug("Skipped server notification before initialized: %s (session=%s)", method, session.id)
        return
    end

    local notification = jsonrpc.notification(method, params)
    self:EnqueueSessionMessage(session, notification, method, true)
end

---@param sessionId string?
---@return MCP.RequestId?
function this:PingSession(sessionId)
    if not sessionId then
        self.logger:debug("Skipped server ping without session id")
        return nil
    end
    local session = self.sessions[sessionId]
    if not session then
        self.logger:debug("Skipped server ping for unknown session: %s", sessionId)
        return nil
    end
    if not session.sseClient then
        self.logger:debug("Skipped server ping without active SSE client: %s", sessionId)
        return nil
    end

    local requestId = self:GenerateServerRequestId(session)
    session.pendingServerRequests[tostring(requestId)] = {
        method = mcp.method.ping,
        createdAt = os.time(),
    }
    self:EnqueueSessionMessage(session, jsonrpc.RequestMessage(requestId, mcp.method.ping), mcp.method.ping, false)
    session.lastServerPingAt = os.time()
    self.logger:debug("Queued server ping request: requestId=%s, session=%s", tostring(requestId), session.id)
    return requestId
end

---@param session MCP.HttpSession
---@param method MCP.Method|string
---@return boolean
function this:HasPendingServerRequest(session, method)
    for _, pendingRequest in pairs(session.pendingServerRequests) do
        if pendingRequest.method == method then
            return true
        end
    end
    return false
end

---@param session MCP.HttpSession
---@param now integer
function this:CloseTimedOutServerRequests(session, now)
    for requestId, pendingRequest in pairs(session.pendingServerRequests) do
        if os.difftime(now, pendingRequest.createdAt) >= serverPingTimeoutSeconds then
            session.pendingServerRequests[requestId] = nil
            self.logger:warn("Server request timed out: requestId=%s, method=%s, session=%s", requestId,
                pendingRequest.method, session.id)
            if pendingRequest.method == mcp.method.ping then
                self:RemoveSSEClient(session)
            end
        end
    end
end

function this:MaintainServerPings()
    local now = os.time()
    for sessionId, session in pairs(self.sessions) do
        self:CloseTimedOutServerRequests(session, now)
        if session.sseClient
            and not self:HasPendingServerRequest(session, mcp.method.ping)
            and os.difftime(now, session.lastServerPingAt) >= serverPingIntervalSeconds then
            self:PingSession(sessionId)
        end
    end
end

---@return integer queuedCount
function this:PingAll()
    local queuedCount = 0
    for sessionId, _ in pairs(self.sessions) do
        if self:PingSession(sessionId) then
            queuedCount = queuedCount + 1
        end
    end
    return queuedCount
end

---@param sessionId string?
---@param method MCP.Method|string
---@param params table?
---@return boolean
function this:NotifySession(sessionId, method, params)
    if not sessionId then
        self.logger:debug("Skipped notification without session id: %s", method)
        return false
    end
    local session = self.sessions[sessionId]
    if not session then
        self.logger:debug("Skipped notification for unknown session: %s (method=%s)", sessionId, method)
        return false
    end
    self:EnqueueNotification(session, method, params)
    return true
end

---@param method MCP.Method|string
---@param params table?
---@return integer notifiedCount
function this:NotifyAll(method, params)
    local notifiedCount = 0
    for _, session in pairs(self.sessions) do
        self:EnqueueNotification(session, method, params)
        notifiedCount = notifiedCount + 1
    end
    return notifiedCount
end

function this:NotifyPromptListChanged()
    local notifiedCount = self:NotifyAll(mcp.method.notifications_prompts_listchanged)
    self.logger:debug("Queued prompt list changed notification (sessions=%d)", notifiedCount)
end

function this:NotifyResourceListChanged()
    local notifiedCount = self:NotifyAll(mcp.method.notifications_resources_listchanged)
    self.logger:debug("Queued resource list changed notification (sessions=%d)", notifiedCount)
end

---@param uri MCP.ResourceUri
---@return integer notifiedCount
function this:NotifyResourceUpdated(uri)
    if not self:IsValidResourceUri(uri) then
        self.logger:warn("Skipped resource updated notification for invalid URI: %s", tostring(uri))
        return 0
    end

    local notifiedCount = 0
    for _, session in pairs(self.sessions) do
        if session.resourceSubscriptions[uri] then
            self:EnqueueNotification(session, mcp.method.notifications_resources_updated, { uri = uri })
            notifiedCount = notifiedCount + 1
        end
    end
    self.logger:debug("Queued resource updated notification: %s (sessions=%d)", uri, notifiedCount)
    return notifiedCount
end

function this:NotifyToolListChanged()
    local notifiedCount = self:NotifyAll(mcp.method.notifications_tools_listchanged)
    self.logger:debug("Queued tool list changed notification (sessions=%d)", notifiedCount)
end

---@param sessionId string?
---@param progressToken MCP.ProgressToken?
---@param progress number
---@param total number?
---@param message string?
---@return boolean
function this:NotifyProgress(sessionId, progressToken, progress, total, message)
    if not progressToken then
        self.logger:debug("Skipped progress notification without progress token")
        return false
    end
    if type(progress) ~= "number" then
        self.logger:warn("Skipped progress notification with invalid progress value: %s", tostring(progress))
        return false
    end
    if total ~= nil and type(total) ~= "number" then
        self.logger:warn("Skipped progress notification with invalid total value: %s", tostring(total))
        return false
    end
    if message ~= nil and type(message) ~= "string" then
        self.logger:warn("Skipped progress notification with invalid message value: %s", tostring(message))
        return false
    end

    return self:NotifySession(sessionId, mcp.method.notifications_progress, {
        progressToken = progressToken,
        progress = progress,
        total = total,
        message = message,
    })
end

---@param session MCP.HttpSession
function this:FlushSessionNotifications(session)
    if not session.sseClient or table.size(session.notificationQueue) == 0 then
        return
    end

    -- Send at most once on the active stream; failed writes are restored for a later reconnect.
    while session.sseClient and table.size(session.notificationQueue) > 0 do
        local notification = table.remove(session.notificationQueue, 1)
        session.nextEventId = session.nextEventId + 1
        local eventId = tostring(session.nextEventId)
        local result = http.SendServerSentEvent(session.sseClient, notification, nil, eventId)
        if result.error then
            table.insert(session.notificationQueue, 1, notification)
            self.logger:debug(
                "SSE client send error, closing stream: %s (session=%s, eventId=%s, queuedNotifications=%d)",
                result.error, session.id, eventId, table.size(session.notificationQueue))
            self:RemoveSSEClient(session)
            break
        end
        self.logger:trace("SSE notification sent: %s", FormatResponseForLog(result.response))
    end
end

function this:BroadcastNotifications()
    for _, session in pairs(self.sessions) do
        self:FlushSessionNotifications(session)
    end
end

function this:LoadPrompts()
    self.prompts = table.new(0, 64)
    local dir = settings.modDir .. "prompts\\"
    local params = {
        resource = self.resource,
    }

    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            self.logger:trace("Load prompt from file: %s", file)
            local prompt = dofile(dir .. file) ---@type MCP.IPrompt
            if prompt and type(prompt) == "table" then
                local success, instance = pcall(prompt.new, params)
                if success and instance and instance.definition then
                    self.prompts[instance.definition.name] = instance
                else
                    self.logger:error("Failed to initialize prompt from file: %s", file)
                end
            else
                self.logger:error("Failed to load prompt from file: %s", file)
            end
        end
    end
end

function this:LoadTools()
    self.tools = table.new(0, 64)
    local dir = settings.modDir .. "tools\\"
    local params = {
        resource = self.resource,
        terrainGridManager = self.terrainGridManager,
        -- Capability discovery reads static metadata through this callback without depending on the server type.
        GetPublishedTools = function()
            return self.tools
        end,
    }

    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            self.logger:trace("Load tool from file: %s", file)
            local tool = dofile(dir .. file) ---@type MCP.ITool
            if tool and type(tool) == "table" then
                local success, instance = pcall(tool.new, params)
                if success and instance and instance.definition then
                    -- Freeze the public catalog at server startup. Runtime checks belong to CanExecute,
                    -- so later configuration changes do not silently require a list_changed notification.
                    if instance:IsPublished() then
                        self.tools[instance.definition.name] = instance
                    end
                else
                    self.logger:error("Failed to initialize tool from file: %s", file)
                end
            else
                self.logger:error("Failed to load tool from file: %s", file)
            end
        end
    end
end

function this:ReleasePrompts()
    if self.prompts then
        for _, prompt in pairs(self.prompts) do
            if prompt.Release then
                pcall(prompt.Release, prompt)
            end
        end
        self.prompts = nil
    end
end

function this:ReleaseTools()
    if self.tools then
        for _, tool in pairs(self.tools) do
            if tool.Release then
                pcall(tool.Release, tool)
            end
        end
        self.tools = nil
    end
end

---@param request Http.Request
function this:DumpRequest(request)
    local config = require("morrowind-mcp.config")
    if config.development.logLevel < mwse.logLevel.trace then
        if request.body then
            self.logger:debug("Request: %s", request.body)
        end
    else
        local str = string.format("\n%s %s %s\n", request.method, request.endpoint, request.protocol)
        if request.headers then
            for key, value in pairs(request.headers) do
                str = str .. string.format("%s: %s\n", key, value)
            end
        end
        if request.body then
            str = str .. "\n" .. string.gsub(request.body, "\r", "")
        end
        self.logger:trace("Request: %s", str)
    end
end

--- https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#initialization
---@param params MCP.InitializeRequestParams
---@return MCP.MethodResult
function this:OnInitialize(params)
    -- TODO reset state

    local settings = require("morrowind-mcp.settings")
    -- Streamable HTTP sessions begin at initialize and are returned as an HTTP header.
    local session = self:CreateSession()

    ---@type MCP.InitializeResult
    local result = jsonrpc.InitializeResult()
    result.protocolVersion = protocolVersion
    -- TODO generator, can be flatten arguments
    result.capabilities = {
        ["completions"] = jsonrpc.object(),
        ["logging"] = jsonrpc.object(),
        ["prompts"] = {
            ["listChanged"] = false,
        },
        ["resources"] = {
            ["subscribe"] = true,
            ["listChanged"] = true,
        },
        ["tools"] = {
            ["listChanged"] = false,
        },
        ["tasks"] = {
            ["list"] = jsonrpc.object(),
            ["cancel"] = jsonrpc.object(),
            ["requests"] = {
                ["tools"] = {
                    ["call"] = jsonrpc.object(),
                },
            },
        },
    }
    result.serverInfo = {
        ["name"] = settings.shortModName,
        ["title"] = settings.modName,
        ["version"] = settings.version,
        ["description"] = settings.description,
        ["icons"] = jsonrpc.array(),
        ["websiteUrl"] = settings.repository
    }
    result.instructions =
    "Provides Morrowind game-state and metadata access plus in-game action tools via MWSE. To reduce failures, inspect current game context and discover available capabilities before invoking state-changing tools, because some operations depend on runtime conditions (target, loaded cell, menu mode, etc.)."

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        http_headers = {
            [http.mcp_header.mcp_session_id] = session.id,
        },
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnPromptsList(params)
    ---@type MCP.ListPromptsResult
    local result = jsonrpc.ListPromptsResult(table.size(self.prompts))

    for _, prompt in spairs(self.prompts) do
        table.insert(result.prompts, prompt.definition)
    end

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnResourcesList(params)
    return self.resource:OnResourcesList(params)
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnResourcesTemplatesList(params)
    return self.resource:OnResourcesTemplatesList(params)
end

--- Delegate resource-template argument completion to the resource manager.
---@param params MCP.CompleteRequestParams
---@return MCP.MethodResult
function this:OnCompletionComplete(params)
    return self.resource:OnCompletionComplete(params)
end

---@param params MCP.ReadResourceRequestParams
---@return MCP.MethodResult
function this:OnResourcesRead(params)
    local result = self.resource:OnResourcesRead(params)
    if result and result.http_response == http.response_code.ok then
        if config.notification.resourcesRead and tes3.isInitialized() then
            local notify = string.format("Read %s", params.uri)
            mcpui.showNotifyMenu(notify)
        end
    end
    return result
end

---@param params MCP.SubscribeRequestParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnResourcesSubscribe(params, request)
    if not params or not self:IsValidResourceUri(params.uri) then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local session = request and self:GetSession(request.http_request) or nil
    if not session then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_request,
        }
    end

    session.resourceSubscriptions[params.uri] = true
    self.logger:debug("Resource subscribed: %s (session=%s, subscriptions=%d)", params.uri, session.id,
        table.size(session.resourceSubscriptions))

    if config.notification.resourcesSubscribe and tes3.isInitialized() then
        local notify = string.format("Subscribe %s", params.uri)
        mcpui.showNotifyMenu(notify)
    end

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
    }
end

---@param params MCP.UnsubscribeRequestParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnResourcesUnsubscribe(params, request)
    if not params or not self:IsValidResourceUri(params.uri) then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local session = request and self:GetSession(request.http_request) or nil
    if not session then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_request,
        }
    end

    session.resourceSubscriptions[params.uri] = nil
    self.logger:debug("Resource unsubscribed: %s (session=%s, subscriptions=%d)", params.uri, session.id,
        table.size(session.resourceSubscriptions))

    if config.notification.resourcesSubscribe and tes3.isInitialized() then
        local notify = string.format("Unubscribe %s", params.uri)
        mcpui.showNotifyMenu(notify)
    end

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnToolsList(params)
    ---@type MCP.ListToolsResult
    local result = jsonrpc.ListToolsResult(table.size(self.tools))

    for _, tool in spairs(self.tools) do
        table.insert(result.tools, tool.definition)
    end

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.CallToolRequestParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnToolsCall(params, request)
    if not params or not params.name then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local tool = self.tools[params.name]
    if not tool then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.ErrorWithMessage(jsonrpc.error_code.method_not_found,
                string.format("Tool is unavailable or unknown: %s.", tostring(params.name))),
        }
    end

    params.arguments = toolvalidator.NormalizeArguments(params.arguments, tool.definition.inputSchema)
    -- tools/call validation failures are returned as CallToolResult errors because the JSON-RPC envelope is valid.
    local validationResult = tool:Validate(params)
    if not validationResult.valid then
        local message = inputvalidator.FormatErrors(validationResult)
        self.logger:warn("Rejected tool arguments for %s: %s", tostring(params.name), message)
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.ok,
            result = jsonrpc.CallToolResult(jsonrpc.TextContent(message), nil, true),
        }
    end

    local sessionId = request and self:GetSessionId(request.http_request) or nil
    local progressToken = self:GetProgressToken(params)
    ---@type MCP.ToolExecutionContext
    local context = {
        sessionId = sessionId,
        progressToken = progressToken,
        NotifyProgress = function(progress, total, message)
            return self:NotifyProgress(sessionId, progressToken, progress, total, message)
        end,
        NavigatePlayer = function(destination)
            return self:StartPlayerNavigation(destination)
        end,
        CancelPlayerNavigation = function()
            return self:CancelPlayerNavigation()
        end,
        HasActivePlayerNavigation = function()
            return self:HasActivePlayerNavigation()
        end,
    }

    local canExecute, availability = tool:CanExecute(params.arguments, context)
    if not canExecute then
        -- Runtime availability is not an authorization failure. Keep the HTTP transport successful so
        -- clients do not attempt OAuth discovery, and surface the condition through the MCP tool result.
        local guidance = availability and availability.guidance or "The current game state does not permit this tool."
        local message = string.format("%s Call mw-capabilities-fetch to inspect general tool conditions.", guidance)
        local structuredContent = availability and jsonrpc.object({
            reason = availability.reason,
            guidance = availability.guidance,
        }) or nil
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.ok,
            result = jsonrpc.CallToolResult(jsonrpc.TextContent(message), structuredContent, true),
        }
    end

    if config.notification.toolsCall and tes3.isInitialized() then
        -- Insert clear visual indicators when tools are invoked
        local notify = string.format("Call %s", params.name)
        for key, value in pairs(params.arguments) do
            notify = notify .. string.format("\n%s=%s", key, tostring(value))
        end
        mcpui.showNotifyMenu(notify)
    end

    -- Tools only receive normalized arguments; request-level metadata is exposed through the execution context.
    local result = tool:Execute(params.arguments, context)

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.GetPromptRequestParams
---@return MCP.MethodResult
function this:OnPromptsGet(params)
    if not params or not params.name then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local prompt = self.prompts[params.name]
    if not prompt then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.ErrorWithMessage(jsonrpc.error_code.invalid_params,
                string.format("Prompt is unavailable or unknown: %s. Call %s to confirm current availability.",
                    tostring(params.name), mcp.method.prompts_list)),
        }
    end
    params.arguments = promptvalidator.NormalizeArguments(params.arguments)
    -- prompts/get has string-only arguments, so reject malformed values before prompt templates interpolate them.
    local validationResult = prompt:Validate(params)
    if not validationResult.valid then
        local message = inputvalidator.FormatErrors(validationResult)
        self.logger:warn("Rejected prompt arguments for %s: %s", tostring(params.name), message)
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    ---@type table
    local context = {}
    local canExecute = prompt:CanExecute(params.arguments, context)
    if not canExecute then
        -- Prompt availability depends on the current game state, not client authorization.
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.ErrorWithMessage(jsonrpc.error_code.invalid_params,
                string.format("Prompt is unavailable in the current game state: %s.", tostring(params.name))),
        }
    end

    if config.notification.promptsGet and tes3.isInitialized() then
        local notify = string.format("Get %s", params.name)
        for key, value in pairs(params.arguments) do
            notify = notify .. string.format("\n%s=%s", key, tostring(value))
        end
        mcpui.showNotifyMenu(notify)
    end

    local result = prompt:Execute(params.arguments, context)

    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.SetLevelRequestParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnLoggingSetLevel(params, request)
    -- TODO set log level for client logging
    self.logger:info("Set log level for client to: %s", params.level)
    -- Use logging/setLevel as a low-risk observable trigger for the SSE notification path.
    local sessionId = request and self:GetSessionId(request.http_request) or nil
    self:NotifySession(sessionId, mcp.method.notifications_message, {
        level = params.level,
        logger = settings.shortModName,
        data = "Logging level changed",
    })
    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
    }
end

---@param params MCP.NotificationParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnInitializedNotification(params, request)
    -- The initialized notification marks the session ready for server-initiated messages.
    local session = request and self:GetSession(request.http_request) or nil
    if session then
        session.initialized = true
    end
    return self:OnNotification(params)
end

---@param params MCP.CancelledNotificationParams
---@param request MCP.ClientRequest?
---@return MCP.MethodResult
function this:OnCancelledNotification(params, request)
    -- TODO: Track in-flight requests by session/request id and expose a cooperative cancellation flag to long-running tools.
    local sessionId = request and self:GetSessionId(request.http_request) or nil
    if not params or params.requestId == nil then
        self.logger:warn("Received cancelled notification without request id (session=%s)", tostring(sessionId))
        return self:OnNotification(params)
    end

    self.logger:info("Received cancelled notification: requestId=%s, reason=%s, session=%s", tostring(params.requestId),
        tostring(params.reason), tostring(sessionId))
    return self:OnNotification(params)
end

---@param params MCP.RequestParams?
---@return MCP.MethodResult
function this:OnPing(params)
    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.ok,
        result = jsonrpc.object(),
    }
end

---@param params MCP.NotificationParams
---@return MCP.MethodResult
function this:OnNotification(params)
    --- curretly, this function is fallback for notifications, nothing to do, just return 202 Accepted
    self.logger:info("Received notification")
    ---@type MCP.MethodResult
    return {
        http_response = http.response_code.accepted,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:OnPOST(request)
    if not request.json_request then
        self.logger:warn("Rejected POST without a JSON-RPC request (session=%s)",
            tostring(self:GetSessionId(request.http_request)))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local handler = self.methodHandlers[request.json_request.method]
    if not handler then
        self.logger:warn("No handler for method: %s (requestId=%s, session=%s)",
            tostring(request.json_request.method), tostring(request.json_request.id),
            tostring(self:GetSessionId(request.http_request)))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.not_implemented, -- ?
            json_error = jsonrpc.error_code.method_not_found,
        }
    end

    self.logger:info("handle method: %s", request.json_request.method)
    local param = request.json_request.params or {}
    local isNotification = request.json_request.id == nil
    local success, result = xpcall(
        function()
            return handler(self, param, request)
        end,
        function(err)
            return debug.traceback(tostring(err), 2)
        end
    )
    if not success then
        self.logger:error("Failed to execute method %s\n%s", request.json_request.method, result)
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.internal_server_error,
            json_error = jsonrpc.error_code.internal_error,
        }
    end

    if result.error or http.IsFailureHttpStatus(result.http_response) then
        self.logger:warn(
            "Method returned failure: %s (httpStatus=%s, jsonError=%s, requestId=%s, notification=%s, session=%s)",
            tostring(request.json_request.method), tostring(result.http_response and result.http_response.code),
            FormatJsonRpcError(result.error), tostring(request.json_request.id), tostring(isNotification),
            tostring(self:GetSessionId(request.http_request)))
    end

    ---@type MCP.ServerResponse
    return {
        -- JSON-RPC notifications are acknowledged by HTTP only and must not receive a result body.
        http_response = isNotification and http.response_code.accepted or result.http_response,
        http_headers = result.http_headers,
        json_result = result.result,
        json_error = result.error,
        no_body = isNotification and not result.error,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:OnClientResponse(request)
    local response = request.json_request
    local session = self:GetSession(request.http_request)
    if not response or response.id == nil or not session then
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local requestKey = tostring(response.id)
    local pendingRequest = session.pendingServerRequests[requestKey]
    if pendingRequest then
        session.pendingServerRequests[requestKey] = nil
        local responseError = response["error"]
        if responseError then
            self.logger:warn("Received client error response: requestId=%s, method=%s, message=%s", requestKey,
                pendingRequest.method, tostring(responseError.message))
        else
            self.logger:debug("Received client response: requestId=%s, method=%s", requestKey, pendingRequest.method)
        end
    else
        self.logger:warn("Received response for unknown server request: requestId=%s, session=%s", requestKey,
            session.id)
    end

    ---@type MCP.ServerResponse
    return {
        http_response = http.response_code.accepted,
        no_body = true,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:OnGET(request)
    -- https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#listening-for-messages-from-the-server
    -- GET is only used to listen for server-to-client messages over SSE.
    local accept = request.http_request.headers[http.header.accept]
    local sessionId = self:GetSessionId(request.http_request)
    if not http.AcceptsContentType(accept, http.content_type.event_stream) then
        self.logger:warn("Rejected GET without SSE accept header (accept=%s, session=%s)", tostring(accept),
            tostring(sessionId))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.method_not_allowed,
            no_body = true,
        }
    end

    local session = self:GetSession(request.http_request)
    if not session then
        self.logger:warn("Rejected GET for missing or unknown session (session=%s, accept=%s)", tostring(sessionId),
            tostring(accept))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.not_found,
            no_body = true,
        }
    end

    if not request.client then
        self.logger:error("Rejected GET without TCP client (session=%s)", tostring(session.id))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.internal_server_error,
            no_body = true,
        }
    end

    self:ReplaceSSEClient(session, request.client)
    local result = http.SendSSEHeaders(request.client, {
        [http.mcp_header.mcp_session_id] = session.id,
    })
    if result.error then
        self.logger:error("Failed to open SSE stream: %s", result.error)
        self:RemoveSSEClient(session)
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.internal_server_error,
            response_sent = true,
        }
    end

    self.logger:debug("SSE stream opened for session: %s", session.id)
    ---@type MCP.ServerResponse
    return {
        -- Headers have already been written; keep the socket open for future SSE events.
        http_response = http.response_code.ok,
        response_sent = true,
        keep_open = true,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:OnDELETE(request)
    -- Clients can explicitly terminate Streamable HTTP sessions with MCP-Session-Id.
    local sessionId = self:GetSessionId(request.http_request)
    if not sessionId then
        self.logger:warn("Rejected DELETE without session id")
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.bad_request,
            no_body = true,
        }
    end

    if not self:DeleteSession(sessionId) then
        self.logger:debug("DELETE requested for unknown session: %s (sessions=%d)", sessionId, table.size(self.sessions))
        ---@type MCP.ServerResponse
        return {
            http_response = http.response_code.not_found,
            no_body = true,
        }
    end

    ---@type MCP.ServerResponse
    return {
        http_response = http.response_code.no_content,
        no_body = true,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:OnOPTIONS(request)
    -- Handle OPTIONS requests for CORS preflight
    -- https://github.com/modelcontextprotocol/python-sdk/issues/1079
    self.logger:debug("Handling OPTIONS preflight (origin=%s, requestMethod=%s, requestHeaders=%s)",
        tostring(request.http_request.headers[http.header.origin]),
        tostring(request.http_request.headers[http.header.access_control_request_method]),
        tostring(request.http_request.headers[http.header.access_control_request_headers]))

    local cros = {
        [http.header.access_control_allow_origin] = "*", -- TODO return Origin if exist.
        [http.header.access_control_allow_methods] = "POST, GET, DELETE, OPTIONS",
        [http.header.access_control_allow_headers] = table.concat(
            {
                --http.header.authorization,
                -- Browser clients need these custom MCP headers to survive preflight checks.
                http.header.accept,
                http.header.content_type,
                http.header.last_event_id,
                http.mcp_header.mcp_protocol_version,
                http.mcp_header.mcp_session_id,
                --http.header.x_requested_with,
            },
            ", "),
    }

    ---@type MCP.ServerResponse
    return {
        http_response = http.response_code.no_content,
        http_headers = cros,
        -- json_error = jsonrpc.error_code.method_not_found,
    }
end

---@param request MCP.ClientRequest
---@return MCP.ServerResponse?
function this:HandleRequest(request)
    local handler = self.requestHandlers[request.http_request.method]
    if not handler then
        self.logger:warn("No handler for request: %s", request.http_request.method)
        return {
            http_response = http.response_code.not_implemented,
            json_error = jsonrpc.error_code.internal_error,
        }
    end

    self.logger:trace("handle request: %s", request.http_request.method)
    return handler(self, request)
end

---@param request Http.Request
---@return MCP.ServerResponse?
function this:ValidateTransportRequest(request)
    if not self:IsAllowedOrigin(request) then
        self.logger:warn("Rejected request from forbidden origin: %s",
            request.headers[http.header.origin] or "nil")
        return {
            http_response = http.response_code.forbidden,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    if not self:IsSupportedProtocolVersion(request) then
        self.logger:warn("Rejected request with unsupported protocol version: %s",
            request.headers[http.mcp_header.mcp_protocol_version] or "nil")
        return {
            http_response = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    if request.method == http.method.POST then
        if not self:IsSupportedPostContentType(request) then
            self.logger:warn("Rejected POST with unsupported content type: %s",
                request.headers[http.header.content_type] or "nil")
            return {
                http_response = http.response_code.unsupported_media_type,
                json_error = jsonrpc.error_code.invalid_request,
            }
        end
        if not self:IsAcceptedPostResponseContentType(request) then
            self.logger:warn("Rejected POST with unacceptable response content type: %s",
                request.headers[http.header.accept] or "nil")
            return {
                http_response = http.response_code.not_acceptable,
                json_error = jsonrpc.error_code.invalid_request,
            }
        end
    end

    if not self:HasValidSessionId(request) then
        self.logger:warn("Rejected request with malformed MCP session id: %s",
            tostring(self:GetSessionId(request)))
        return {
            http_response = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local sessionId = self:GetSessionId(request)
    if request.method ~= http.method.DELETE and sessionId and not self:GetSession(request) then
        self.logger:warn("Rejected request for unknown session: %s", sessionId)
        return {
            http_response = http.response_code.not_found,
            no_body = true,
        }
    end

    return nil
end

---@param client Socket.TcpClient
---@param request Http.Request
---@return MCP.ServerResponse?
function this:DispatchHttpRequest(client, request)
    -- Only POST carries JSON-RPC messages; GET/DELETE/OPTIONS are transport-level requests.
    if request.method ~= http.method.POST then
        return self:HandleRequest({ client = client, http_request = request })
    end

    local json_request, json_error = jsonrpc.request(request.body)
    if json_error then
        return {
            http_response = http.response_code.bad_request,
            json_error = json_error,
        }
    end

    if json_request and not json_request.method then
        return self:OnClientResponse({ client = client, http_request = request, json_request = json_request })
    end

    local response = self:HandleRequest({ client = client, http_request = request, json_request = json_request })
    if response then
        response.request_id = json_request and json_request.id or nil
    end
    return response
end

---@param client Socket.TcpClient
---@param response MCP.ServerResponse?
---@param requestId MCP.RequestId?
---@return boolean keepOpen
function this:SendServerResponse(client, response, requestId)
    if not response then
        local result = http.SendResponse(client, http.response_code.internal_server_error,
            http.PrepareResponseHeaders(nil, false),
            jsonrpc.error(requestId, jsonrpc.error_code.internal_error))
        self.logger:error("internal error: %d\n%s", http.response_code.internal_server_error.code,
            FormatResponseForLog(result.response))
        return false
    end

    if response.response_sent then
        -- SSE handlers write their own response headers before returning.
        return response.keep_open == true
    end

    if response.json_error then
        local result = http.SendResponse(client, response.http_response,
            http.PrepareResponseHeaders(response.http_headers, response.keep_open == true),
            jsonrpc.error(requestId, response.json_error))
        self.logger:error("json error: %d\n%s", response.http_response.code,
            FormatResponseForLog(result.response))
        return false
    end

    if response.no_body then
        local result = http.SendResponse(client, response.http_response,
            http.PrepareResponseHeaders(response.http_headers, response.keep_open == true))
        self.logger:debug("success: %d\n%s", response.http_response.code,
            FormatResponseForLog(result.response))
        return response.keep_open == true
    end

    local result = http.SendResponse(client, response.http_response,
        http.PrepareResponseHeaders(response.http_headers, response.keep_open == true),
        jsonrpc.result(requestId, response.json_result))
    self.logger:debug("success: %d\n%s", response.http_response.code,
        FormatResponseForLog(result.response))
    return response.keep_open == true
end

---@param client Socket.TcpClient
---@param request Http.Request
function this:ProcessClientRequest(client, request)
    self:DumpRequest(request)

    -- Transport errors are checked before JSON-RPC parsing so non-POST methods can have empty bodies.
    local response = self:ValidateTransportRequest(request)
    local requestId = nil
    if not response then
        response = self:DispatchHttpRequest(client, request)
        if response and response.request_id then
            requestId = response.request_id
        end
    end

    local keepOpen = self:SendServerResponse(client, response, requestId)
    if not keepOpen then
        pcall(function() client:close() end)
    end
end

--- @param e enterFrameEventData
function this:Listen(e)
    --- @type Socket.TcpClient?
    -- accept as many new clients as available (non-blocking accept)
    while true do
        local client, acceptErr = self.server:accept()
        if not client then
            break
        elseif acceptErr then
            self.logger:error(acceptErr)
            break
        end

        -- read the request with a short timeout to parse headers
        client:settimeout(5)
        local request, err, partial = http.ReceiveRequest(client)
        if (not request) or err then
            if http.IsClosedBeforeRequest(request, err, partial) then
                self.logger:debug("HTTP client closed connection before sending a request")
                pcall(function() client:close() end)
            else
                self.logger:error("Reading HTTP request: %s", err)
                if partial then
                    self.logger:debug("Partial data received: %s", partial)
                end

                local result = http.SendResponse(client, http.response_code.bad_request,
                    http.PrepareResponseHeaders(nil, false)) -- TODO add json?
                self.logger:error("bad request: %d%s", http.response_code.bad_request.code,
                    FormatResponseForLog(result.response))

                pcall(function() client:close() end)
            end
        else
            self:ProcessClientRequest(client, request)
        end
    end
end

--- @param e enterFrameEventData
function this:PollPrimitiveCondition(e)
    -- Resource changes remain dynamic even though the tool and prompt catalogs are static.
    if self.resource:IsChangedResourceList() then
        self:NotifyResourceListChanged()
        self.resource:ResetChangedResourceList()
    end
    -- publish subscription
    local updated = self.resource:GetUpdatedResources()
    if updated and table.size(updated) > 0 then
        for uri, _ in pairs(updated) do
            self:NotifyResourceUpdated(uri)
        end
        self.resource:ResetUpdatedResources()
    end
end

---@param e keyDownEventData
function this:DebugNotification(e)
    self.logger:debug("Debug Notification.")

    ---@type string[]
    local texts = {
        mcp.method.notifications_cancelled,
        mcp.method.notifications_tasks_status,
        mcp.method.notifications_message,
        mcp.method.notifications_progress,
        mcp.method.notifications_prompts_listchanged,
        mcp.method.notifications_resources_listchanged,
        mcp.method.notifications_resources_updated,
        mcp.method.notifications_tools_listchanged,
        mcp.method.notifications_elicitation_complete,
    }

    --- @type tes3ui.showMessageMenu.params.button[]
    local buttons = table.new(table.size(texts), 0)
    for i, text in ipairs(texts) do
        buttons[i] = {
            text = text,
            callback = function()
                self.logger:debug("Broadcasting notification: %s", text)
                if text == mcp.method.notifications_prompts_listchanged then
                    self:NotifyPromptListChanged()
                elseif text == mcp.method.notifications_resources_listchanged then
                    self:NotifyResourceListChanged()
                elseif text == mcp.method.notifications_resources_updated then
                    self:NotifyResourceUpdated(settings.uriScheme .. "debug-notification.txt")
                elseif text == mcp.method.notifications_tools_listchanged then
                    self:NotifyToolListChanged()
                else
                    -- TODO
                    self:NotifyAll(text)
                end
            end
        }
    end

    tes3ui.showMessageMenu({
        header = "MCP Notifications",
        message = "Broadcast notifications event.",
        cancels = true,
        buttons = buttons
    })
end

---@param e keyDownEventData
function this:DebugMemory(e)
    self.logger:debug("Debug Memory")
    self.resource.memory:SaveDebugDocuments()
end

---@param e keyDownEventData
function this:DebugNavigation(e)
    if not self.visualizer then
        self.logger:warn("Navigation visualizer is unavailable")
        return
    end
    tes3ui.showMessageMenu({
        header = "Navigation Debug",
        message = "Choose a navigation visualization action.",
        cancels = true,
        buttons = {
            {
                text = self.visualizer.options.terrainEnabled and "Hide Terrain Grid" or "Show Terrain Grid",
                callback = function()
                    self.visualizer:SetTerrainEnabled(not self.visualizer.options.terrainEnabled)
                end,
            },
            {
                text = self.visualizer.options.graphEnabled and "Hide Pathfinding Graph" or "Show Pathfinding Graph",
                callback = function()
                    self.visualizer:SetGraphEnabled(not self.visualizer.options.graphEnabled)
                end,
            },
            {
                text = "Pathgrid Navigation",
                callback = function()
                    self:DebugNavigationCandidates(e)
                end,
            },
        },
    })
end

---@param e keyDownEventData
function this:DebugNavigationCandidates(e)
    local player = tes3.player
    if not player or not player.cell then
        self.logger:warn("Navigation debug menu requires an active player cell")
        return
    end
    local cellId = cellutil.GetIdentityKey(player.cell)
    local nodeIds = cellId and self.pathfinding.nodeIdsByCellId[cellId] or nil
    if not nodeIds or table.size(nodeIds) == 0 then
        self.logger:warn("Navigation debug menu found no pathgrid nodes in the current cell")
        return
    end

    local candidates = {}
    local missingNodes = 0
    for _, nodeId in ipairs(nodeIds) do
        local node = self.pathfinding.nodes[nodeId]
        if node then
            -- Nearby nodes can belong to disconnected pathgrid components, so only offer routes that A* can traverse.
            local path = self.pathfinding:FindPath({ cell = player.cell, position = player.position },
                { cell = player.cell, position = node.position })
            if path and table.size(path.nodeIds) > 1 then
                local dx = node.position.x - player.position.x
                local dy = node.position.y - player.position.y
                table.insert(candidates, { node = node, distance = dx * dx + dy * dy })
            end
        else
            missingNodes = missingNodes + 1
        end
    end
    self.logger:info("Navigation debug candidates: cell=%s total=%d reachable=%d missing=%d", cellId,
        table.size(nodeIds), table.size(candidates), missingNodes)
    if table.size(candidates) == 0 then
        self.logger:warn("Navigation debug menu found no reachable pathgrid nodes in the current cell")
        tes3.messageBox("No reachable pathgrid destination is available in the current cell.")
        return
    end
    table.sort(candidates, function(first, second) return first.distance < second.distance end)

    local buttons = table.new(math.min(table.size(candidates), 8), 0)
    for index = 1, math.min(table.size(candidates), 8) do
        local candidate = candidates[index]
        local node = candidate.node
        buttons[index] = {
            text = string.format("Node %d: %.0f, %.0f, %.0f", node.id, node.position.x, node.position.y, node.position.z),
            callback = function()
                local ok, message, navigation = self:StartPlayerNavigation({
                    cell = player.cell,
                    position = node
                        .position
                })
                if not ok then
                    tes3.messageBox("Navigation failed: %s", tostring(message))
                elseif navigation then
                    self.logger:info("Navigation debug started: routeNodes=%d waypoints=%d", navigation.routeNodeCount,
                        navigation.waypointCount)
                end
            end,
        }
    end
    tes3ui.showMessageMenu({
        header = "Pathgrid Navigation",
        message = "Choose a nearby pathgrid destination.",
        cancels = true,
        buttons = buttons,
    })
end

function this:DisableVanityMode()
    if tes3.mobilePlayer then
        if config.autoplay.vanityDisabled and not tes3.mobilePlayer.vanityDisabled then
            tes3.mobilePlayer.vanityDisabled = true
            self.logger:info("Vanity disabled")
        end
    end
end

function this:Start()
    if self.server then
        self.logger:warn("MCP server is already running")
        return false
    end

    self.server = socket.bind(self.hostname, self.port)
    if not self.server then
        self.logger:error("Failed to start MCP server on %s:%d", self.hostname, self.port)
        return false
    end
    self.server:settimeout(0)

    input_action.RegisterEventHandlers()
    ui_action.RegisterEventHandlers()
    target:RegisterEvent()
    self.pathfinding:RegisterEventHandlers()
    self.terrainGridManager:RegisterEventHandlers()
    self:CreateNavigationVisualizer()

    self.enterFrameCallback = function(e)
        self:Listen(e)
        self:PollPrimitiveCondition(e)
        self:MaintainServerPings()
        self:BroadcastNotifications()
        self:CloseExpiredSessions()
        self:UpdateNavigationVisualizer()
        -- Since it is set back to `true` when TPV becomes active during character generation, it always attempts to apply it.
        self:DisableVanityMode()
    end
    event.register(tes3.event.enterFrame, self.enterFrameCallback)

    self.loadedCallback = function(e)
        debugGeometryProbe.Remove()
        self:UpdateNavigationVisualizer(true)
        if tes3.worldController then
            if config.notification.showSubtitles and not tes3.worldController.showSubtitles then
                tes3.worldController.showSubtitles = true
                self.logger:info("Subtitles shown")
            end
            if tes3.worldController.menuController then
                if config.development.cellBorder ~= tes3.worldController.menuController.bordersEnabled then
                    tes3.worldController.menuController.bordersEnabled = config.development.cellBorder
                    self.logger:debug("Cell border changed to %s", tostring(config.development.cellBorder))
                end
                if config.development.collisionBox ~= tes3.worldController.menuController.collisionBoxesEnabled then
                    tes3.worldController.menuController.collisionBoxesEnabled = config.development.collisionBox
                    self.logger:debug("Collision boxes changed to %s", tostring(config.development.collisionBox))
                end
                if config.development.pathGrid ~= tes3.worldController.menuController.pathGridShown then
                    tes3.worldController.menuController.pathGridShown = config.development.pathGrid
                    self.logger:debug("Pathgrid changed to %s", tostring(config.development.pathGrid))
                end
            end
        end
    end
    event.register(tes3.event.loaded, self.loadedCallback)

    if config.development.debug then
        -- register debug command
        self.debugKeyCallback = function(e)
            -- self:DebugNotification(e)
            self:DebugMemory(e)
        end
        event.register(tes3.event.keyDown, self.debugKeyCallback, { filter = tes3.scanCode.F4 })
        self.debugNavigationKeyCallback = function(e)
            self:DebugNavigation(e)
        end
        event.register(tes3.event.keyDown, self.debugNavigationKeyCallback, { filter = tes3.scanCode.F2 })
    end

    self.logger:info("MCP server started on %s:%d", self.hostname, self.port)
    return true
end

function this:Shutdown()
    if not self.server then
        self.logger:warn("MCP server is already stopped.")
        return false
    end

    if self.enterFrameCallback then
        event.unregister(tes3.event.enterFrame, self.enterFrameCallback)
        self.enterFrameCallback = nil
    end

    if self.loadedCallback then
        event.unregister(tes3.event.loaded, self.loadedCallback)
        self.loadedCallback = nil
    end

    if self.debugKeyCallback then
        event.unregister(tes3.event.keyDown, self.debugKeyCallback)
        self.debugKeyCallback = nil
    end
    if self.debugNavigationKeyCallback then
        event.unregister(tes3.event.keyDown, self.debugNavigationKeyCallback)
        self.debugNavigationKeyCallback = nil
    end

    for _, session in pairs(self.sessions) do
        self:RemoveSSEClient(session)
    end

    self:ReleasePrompts()
    self:ReleaseTools()
    self.resource:Release()
    self.resource = nil

    if self.activeNavigator then
        self.activeNavigator:Release()
        self.activeNavigator = nil
    end

    debugGeometryProbe.Remove()
    self:ReleaseNavigationVisualizer()

    self.terrainGridManager:Release()

    self.pathfinding:UnregisterEventHandlers()
    target:UnregisterEvent()
    input_action.UnregisterEventHandlers()
    ui_action.UnregisterEventHandlers()

    self.server:close()
    self.server = nil
    self.logger:info("MCP Server stopped")
    return true
end

return this
