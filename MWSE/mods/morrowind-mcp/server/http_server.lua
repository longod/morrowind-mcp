local base = require("morrowind-mcp.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local strutil = require("morrowind-mcp.strutil")

local dataFiles = "Data Files\\"
local modDir = "MWSE\\mods\\morrowind-mcp\\"
local maxClients = 32
local maxQueueSize = 128
local notificationMethod = "server/event"


-- ---@type table<string, function>
-- local methods = {
--     ["server/discover"] = nil,
--     ["prompts/list"] = nil,
--     ["prompts/get"] = nil,
-- }

-- "server"
-- "prompts"
-- "list"
-- "get"


---@type LuaSocketModule
local socket = require("socket")

---@class MwseHttpServer : IServer
---@field logger mwseLogger
---@field server LuaSocketTcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field requestHandlers table<string, fun(self: MwseHttpServer, request: ClientRequest): ServerResponce?>
---@field methodHandlers table<string, fun(self: MwseHttpServer, params: table?): MethodResult>
---@field prompts table<string, IPrompt>
---@field resources table<string, IResource>
---@field tools table<string, ITool>
local this = {}
setmetatable(this, { __index = base })

-- this.returnedTypes = {
--     complete = "complete",
--     failed = "failed",
--     progressing = "progressing",
-- }

---@param params table?
---@return MwseHttpServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this })
    ---@cast instance MwseHttpServer
    if not instance.logger then
        instance.logger = require("morrowind-mcp.logger")
    end
    instance.requestHandlers = {
        ["POST"] = instance.OnPOST,
        ["GET"] = instance.OnGET,
    }
    instance.methodHandlers = {
        ["initialize"] = instance.OnInitialize,
    }
    return instance
end


function this:LoadPrompts()
    local dir = dataFiles .. modDir .. "tools"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local prompt  = dofile(dir .. "\\" .. file) ---@type IPrompt
            if prompt and type(prompt) == "table" then
                self.prompts[prompt.name] = prompt
            else
                self.logger:error("Failed to load prompt from file: %s", file)
            end
        end
    end
end

function this:LoadResources()
    local dir = dataFiles .. modDir .. "resources"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local res  = dofile(dir .. "\\" .. file) ---@type IResource
            if res and type(res) == "table" then
                self.resources[res.name] = res
            else
                self.logger:error("Failed to load resource from file: %s", file)
            end
        end
    end
end

function this:LoadTools()
    local dir = dataFiles .. modDir .. "tools"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local tool  = dofile(dir .. "\\" .. file) ---@type ITool
            if tool and type(tool) == "table" then
                self.tools[tool.name] = tool
            else
                self.logger:error("Failed to load tool from file: %s", file)
            end
        end
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
            str = str .. "\n" .. request.body
        end
        self.logger:trace(str)
    end
end

---@class ClientRequest
---@field http_request Http.Request
---@field json_request JsonRPC.Request|JsonRPC.Notification?

---@class ServerResponce
---@field http_responce Http.Response
---@field json_result table?
---@field json_error JsonRPC.ErrorObject?

---@class MethodResult
---@field http_responce Http.Response -- TODO simplify 200, 202, 400 or more?
---@field result table?
---@field error JsonRPC.ErrorObject?

---comment
---@param params table?
---@return MethodResult
function this:OnInitialize(params)
    -- TODO reset state

    self:LoadPrompts()
    self:LoadResources()
    self:LoadTools()
    return {
        http_responce = http.response_code.ok,
    }
end

---@param request ClientRequest
---@return ServerResponce?
function this:OnPOST(request)
    -- TODO check headers

    if not request.json_request then
        return {
            http_responce = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local handler = self.methodHandlers[request.json_request.method]
    if not handler then
        self.logger:warn("No handler for method: %s", request.json_request.method)
        return {
            http_responce = http.response_code.method_not_allowed, -- ?
            json_error = jsonrpc.error_code.method_not_found,
        }
    end

    self.logger:info("handle method: %s", request.json_request.method)

    local result = handler(self, request.json_request.params)

    return {
        http_responce = result.http_responce,
        json_result = result.result,
        json_error = result.error,
    }


    --[[
    if type(result) == "table" and result.notify then
        local notify = result.notify
        result.notify = nil
        if type(notify) == "table" then
            self:NotifyClients(notify.method, notify.params)
        elseif type(notify) == "string" then
            self:NotifyClients(notificationMethod, { message = notify })
        end
    end

    if type(result) == "string" then
        return {
            status = 200,
            headers = { ["Content-Type"] = "application/json", ["Connection"] = "close" },
            body = result,
        }
    end

    if type(result) == "table" and (result.status or result.body or result.headers) then
        if not result.headers then
            result.headers = { ["Content-Type"] = "application/json", ["Connection"] = "close" }
        elseif not result.headers["Connection"] and not result.headers["connection"] then
            result.headers["Connection"] = "close"
        end
        return result
    end

    return {
        status = 200,
        headers = { ["Content-Type"] = "application/json", ["Connection"] = "close" },
        body = jsonrpc.result(jsonrpc.resultTypes.complete, jsonRpcRequest.id, result),
    }
    --]]
end

---@param request ClientRequest
---@return ServerResponce?
function this:OnGET(request)
    -- server is supported SSE?
    -- https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#listening-for-messages-from-the-server
    local contents = strutil.split(request.http_request.headers[http.header.accept], ",")
    if contents then
        for _, value in ipairs(contents) do
            local content = strutil.ltrim(value:lower())
            if content == http. content_type_value.event_stream then
                -- no supported SSE
                self.logger:info("No supported SSE")
                return {
                    http_responce = http.response_code.method_not_allowed,
                    json_error = jsonrpc.error_code.method_not_found,
                }
            end
        end
    end
    -- TODO return
end

---@param request ClientRequest
---@return ServerResponce?
function this:HandleRequest(request)
    local handler = self.requestHandlers[request.http_request.method]
    if not handler then
        self.logger:warn("No handler for request: %s", request.http_request.method)
        return {
            http_responce = http.response_code.not_implemented,
            json_error = jsonrpc.error_code.internal_error,
        }
    end

    self.logger:trace("handle request: %s", request.http_request.method)
    return handler(self, request)
end

--[[
function this:AddClient(client)
    if #self.clients >= maxClients then
        self.logger:warn("Max clients reached, rejecting new SSE client")
        pcall(function() client:close() end)
        return false
    end

    client:settimeout(0)
    table.insert(self.clients, client)
    self.logger:info("SSE client connected (total=%d)", #self.clients)
    if #self.eventQueue > 0 then
        self:BroadcastEvents()
    end
    return true
end

function this:RemoveClient(client)
    for i, c in ipairs(self.clients) do
        if c == client then
            pcall(function() c:close() end)
            table.remove(self.clients, i)
            self.logger:info("SSE client disconnected (total=%d)", #self.clients)
            return true
        end
    end
    return false
end

function this:CloseAllClients()
    for _, client in ipairs(self.clients) do
        pcall(function() client:close() end)
    end
    self.clients = {}
end

function this:EnqueueEvent(event)
    if type(event) == "table" then
        table.insert(self.eventQueue, json.encode(event))
    else
        table.insert(self.eventQueue, tostring(event))
    end

    while #self.eventQueue > maxQueueSize do
        table.remove(self.eventQueue, 1)
    end
end

function this:SendEvent(event)
    self:EnqueueEvent(event)
    self:BroadcastEvents()
end

function this:NotifyClients(method, params)
    self:SendEvent(jsonrpc.notification(method or notificationMethod, params))
end

function this:BroadcastEvents()
    if not self.clients or #self.clients == 0 then
        return
    end

    if not self.eventQueue or #self.eventQueue == 0 then
        return
    end

    local events = self.eventQueue
    self.eventQueue = {}

    for i = #self.clients, 1, -1 do
        local client = self.clients[i]
        local shouldRemove = false
        for _, ev in ipairs(events) do
            local sse = "data: " .. tostring(ev) .. "\n\n"
            local ok, err = client:send(sse)
            if not ok then
                self.logger:debug("client send error, removing: %s", tostring(err))
                shouldRemove = true
                break
            end
        end
        if shouldRemove then
            self:RemoveClient(client)
        end
    end
end

---@param request HttpRequest
function this.IsSSE(request)
    -- if http.ParseRequestMethod(request.method) == "GET" then
        for _, h in ipairs(request.headers) do
            local low = h:lower()
            if low:find("accept:") and low:find("text/event-stream") then -- FIXME compare
                return true
            end
        end
    -- end
    return false
end
--]]

--- @param e enterFrameEventData
function this:Listen(e)
    --- @type LuaSocketTcpClient?
    -- accept as many new clients as available (non-blocking accept)
    while true do
        local client, acceptErr = self.server:accept()
        if not client then
            break
        elseif acceptErr then
            self.logger:error(acceptErr)
            break
        end

        self.logger:trace("client accepted")

        -- read the request with a short timeout to parse headers
        client:settimeout(5)
        local request, err, partial = http.ReceiveRequest(client)
        if (not request) or err then
            self.logger:error("Reading HTTP request: %s", err)
            if partial then
                self.logger:debug("Partial data received: %s", partial)
            end

            local result = http.SendResponse(client, http.response_code.bad_request) -- TODO add json?
            self.logger:error(result.response)

            pcall(function() client:close() end)
        else
            self:DumpRequest(request)

            local json_request, json_error = jsonrpc.request(request.body)
            local id = json_request and json_request.id or nil ---@type string|number?
            if not json_error then
                local response = self:HandleRequest({http_request = request,  json_request = json_request})
                if response then
                    if response.json_error then
                        local result = http.SendResponse(client, response.http_responce, jsonrpc.error(id, response.json_error) )
                        self.logger:error("json error: %d\n%s", response.http_responce.code, result.response)
                    else
                        local result = http.SendResponse(client, response.http_responce, jsonrpc.result(id, response.json_result) )
                        self.logger:debug("success: %d\n%s", response.http_responce.code, result.response)
                    end
                else
                    local result = http.SendResponse(client, http.response_code.internal_server_error, jsonrpc.error(id, jsonrpc.error_code.internal_error) )
                    self.logger:error("internal error: %s", result.response)
                end
            else
                local result = http.SendResponse(client, http.response_code.bad_request, jsonrpc.error(nil, json_error))
                self.logger:error("request error: %s", result.response)
            end

            pcall(function() client:close() end)
        end
    end
end

function this:Start()
    if self.server then
        self.logger:warn("MCP server is already running")
        return false
    end
    -- self.server = socket.bind("localhost", "45024")
    self.server = socket.bind("*", "45024")
    if not self.server then
        self.logger:error("Failed to start MCP server on port 45024")
        return false
    end
    self.server:settimeout(0)

    self.enterFrameCallback = function (e)
        self:Listen(e)
        -- broadcast any queued events to connected SSE clients
        -- self:BroadcastEvents()
    end
    event.register(tes3.event.enterFrame, self.enterFrameCallback)

    self.logger:info("server started on port 45024")
    return true
end

function this:Shutdown()
    if not self.server then
        self.logger:warn("server is already stopped.")
        return false
    end

    if self.enterFrameCallback then
        event.unregister(tes3.event.enterFrame, self.enterFrameCallback)
        self.enterFrameCallback = nil
    end

    -- self:CloseAllClients()
    self.server:close()
    self.server = nil
    self.logger:info("server stopped")
    return true
end

return this
