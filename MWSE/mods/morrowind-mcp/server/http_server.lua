local base = require("morrowind-mcp.core.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local mcp = require("morrowind-mcp.core.mcp")
local pathutil = require("morrowind-mcp.core.pathutil")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")
local resourceManager = require("morrowind-mcp.resources.manager")

-- TODO split implementations, such as session manager?

---@type Socket.Module
local socket = require("socket")

local maxResponseLogLength = config.development.debug and 2048 or 256
local maxNotificationQueueSize = 128
local serverPingIntervalSeconds = 60
local serverPingTimeoutSeconds = 30
local sessionIdleTimeoutSeconds = 300
local pollingIntervalSeconds = 10.0
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
---@field debugKeyCallback fun(e : keyDownEventData)?
---@field hostname string
---@field port integer
---@field httpHeaders table<string, string> must headers
---@field requestHandlers table<string, fun(self: MCP.MwseHttpServer, request: MCP.ClientRequest): MCP.ServerResponse?>
---@field methodHandlers table<string, fun(self: MCP.MwseHttpServer, params: MCP.RequestParams, request: MCP.ClientRequest?): MCP.MethodResult>
---@field prompts table<string, MCP.IPrompt>
---@field tools table<string, MCP.ITool>
---@field promptsStatus table<string, boolean>
---@field toolsStatus table<string, boolean>
---@field resource MCP.ResourceManager
---@field sessions table<string, MCP.HttpSession>
---@field nextSessionIndex integer
---@field lastPollingPromptsInterval number
---@field lastPollingToolsInterval number
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
    instance.sessions = {}
    instance.nextSessionIndex = 0
    instance.lastPollingPromptsInterval = 0
    instance.lastPollingToolsInterval = pollingIntervalSeconds / 2.0 -- cycle prompts and tools polling to avoid simultaneous polling
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
    self.promptsStatus = table.new(0, table.size(self.prompts))
end

function this:LoadTools()
    self.tools = table.new(0, 64)
    local dir = settings.modDir .. "tools\\"
    local params = {
        resource = self.resource,
    }

    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            self.logger:trace("Load tool from file: %s", file)
            local tool = dofile(dir .. file) ---@type MCP.ITool
            if tool and type(tool) == "table" then
                local success, instance = pcall(tool.new, params)
                if success and instance and instance.definition then
                    self.tools[instance.definition.name] = instance
                else
                    self.logger:error("Failed to initialize tool from file: %s", file)
                end
            else
                self.logger:error("Failed to load tool from file: %s", file)
            end
        end
    end
    self.toolsStatus = table.new(0, table.size(self.tools))
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
        ["logging"] = jsonrpc.object(),
        ["prompts"] = {
            ["listChanged"] = true,
        },
        ["resources"] = {
            ["subscribe"] = true,
            ["listChanged"] = true,
        },
        ["tools"] = {
            ["listChanged"] = true,
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

function this:CanExecuteAllPrompts()
    local changed = false
    for name, prompt in pairs(self.prompts) do
        local can = prompt:CanExecute({})
        if self.promptsStatus[name] ~= can then
            changed = true
            self.promptsStatus[name] = can
            self.logger:trace("Prompt executable changed: %s is %s", name, tostring(can))
        end
    end
    return changed
end

function this:CanExecuteAllTools()
    local changed = false
    for name, tool in pairs(self.tools) do
        local can = tool:CanExecute({})
        if self.toolsStatus[name] ~= can then
            changed = true
            self.toolsStatus[name] = can
            self.logger:trace("Tool executable changed: %s is %s", name, tostring(can))
        end
    end
    return changed
end

---@param params MCP.PaginatedRequestParams
---@return MCP.MethodResult
function this:OnPromptsList(params)
    ---@type MCP.ListPromptsResult
    local result = jsonrpc.ListPromptsResult(table.size(self.prompts))

    for name, prompt in pairs(self.prompts) do
        local can = prompt:CanExecute({})
        if can then
            table.insert(result.prompts, prompt.definition)
        end
        self.promptsStatus[name] = can
    end
    self.lastPollingPromptsInterval = 0

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

---@param params MCP.ReadResourceRequestParams
---@return MCP.MethodResult
function this:OnResourcesRead(params)
    return self.resource:OnResourcesRead(params)
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

    for name, tool in pairs(self.tools) do
        local can = tool:CanExecute({})
        if can then
            table.insert(result.tools, tool.definition)
        end
        self.toolsStatus[name] = can
    end
    self.lastPollingToolsInterval = 0

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
            error = jsonrpc.error_code.method_not_found,
        }
    end
    if not tool:CanExecute(params) then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.forbidden,
            error = jsonrpc.error_code.invalid_params,
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
    }

    local result = tool:Execute(params, context)

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
            error = jsonrpc.error_code.method_not_found,
        }
    end
    if not prompt:CanExecute(params) then
        ---@type MCP.MethodResult
        return {
            http_response = http.response_code.forbidden,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- TODO maybe need more context table (world, player, etc...)
    local result = prompt:Execute(params)

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
        self.logger:warn("Method returned failure: %s (httpStatus=%s, jsonError=%s, requestId=%s, notification=%s, session=%s)",
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
    self.lastPollingPromptsInterval = self.lastPollingPromptsInterval + e.delta
    self.lastPollingToolsInterval = self.lastPollingToolsInterval + e.delta
    if self.lastPollingToolsInterval >= pollingIntervalSeconds then
        if self:CanExecuteAllTools() then
            self:NotifyToolListChanged()
        end
        self.logger:trace("Polling tools for executable changes (interval=%f seconds)", self.lastPollingToolsInterval)
        self.lastPollingToolsInterval = 0
    elseif self.lastPollingPromptsInterval >= pollingIntervalSeconds then
        if self:CanExecuteAllPrompts() then
            self:NotifyPromptListChanged()
        end
        self.logger:trace("Polling prompts for executable changes (interval=%f seconds)", self.lastPollingPromptsInterval)
        self.lastPollingPromptsInterval = 0
    end

    -- FIXME dont touch private field in this. PoC
    -- no polling time?
    if self.resource.changed > 0 then
        self:NotifyResourceListChanged()
        self.logger:debug("resource list changed, changed=%d total=%d", self.resource.changed, table.size(self.resource.resources))
        self.resource.changed = 0
    end
    -- publish subscription
    if table.size(self.resource.updated) > 0 then
        for uri, _ in pairs(self.resource.updated) do
            self:NotifyResourceUpdated(uri)
        end
        self.logger:debug("resource updated, updated=%d total=%d", table.size(self.resource.updated), table.size(self.resource.resources))
        table.clear(self.resource.updated)
    end

end

--- @param e keyDownEventData
function this:OnDebugKeyCallback(e)
    self.logger:debug("Debug key pressed, opening MCP log level and tool selection menu")

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

    self.enterFrameCallback = function(e)
        self:Listen(e)
        self:PollPrimitiveCondition(e)
        self:MaintainServerPings()
        self:BroadcastNotifications()
        self:CloseExpiredSessions()
    end
    event.register(tes3.event.enterFrame, self.enterFrameCallback)
    self.logger:info("server started on %s:%d", self.hostname, self.port)

    if config.development.debug then
        -- register debug command
        self.debugKeyCallback = function(e)
            self:OnDebugKeyCallback(e)
        end
        event.register(tes3.event.keyDown, self.debugKeyCallback, { filter = tes3.scanCode.F4 })
    end
    return true
end

function this:Shutdown()
    if not self.server then
        self.logger:warn("server is already stopped.")
        return false
    end

    if self.debugKeyCallback then
        event.unregister(tes3.event.keyDown, self.debugKeyCallback)
        self.debugKeyCallback = nil
    end

    if self.enterFrameCallback then
        event.unregister(tes3.event.enterFrame, self.enterFrameCallback)
        self.enterFrameCallback = nil
    end

    for _, session in pairs(self.sessions) do
        self:RemoveSSEClient(session)
    end

    self:ReleasePrompts()
    self:ReleaseTools()
    self.resource:Release()
    self.resource = nil

    self.server:close()
    self.server = nil
    self.logger:info("server stopped")
    return true
end

return this
