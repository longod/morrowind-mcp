--[[
local base = require("morrowind-mcp.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

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


---@type Socket.Module
local socket = require("socket")

---@class MwseStreamableHttpServer: MCP.IServer
---@field logger mwseLogger
---@field server Socket.TcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field clients Socket.TcpClient[]
---@field eventQueue string[]
---@field requestHandlers table<string, fun(self: MwseStreamableHttpServer, request: Http.Request): table>
---@field methodHandlers table<string, fun(self: MwseStreamableHttpServer, params: table?): table>
---@field prompts table<string, MCP.IPrompt>
---@field resources table<string, MCP.IResource>
---@field tools table<string, MCP.ITool>
local this = {}
setmetatable(this, { __index = base })

-- this.returnedTypes = {
--     complete = "complete",
--     failed = "failed",
--     progressing = "progressing",
-- }

---@deprecated currently not implemeneted
---@param params table?
---@return MwseStreamableHttpServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MwseStreamableHttpServer
    instance.logger = require("morrowind-mcp.logger")
    instance.requestHandlers = {
        ["POST"] = instance.HandlePOST,
        ["GET"] = instance.HandleGET,
    }
    instance.methodHandlers = {
        ["initialize"] = instance.HandleInitialize,
    }
    instance.clients = {}
    instance.eventQueue = {}
    return instance
end




---@param request Http.Request
function this:DumpRequest(request)
    self.logger:debug("Request: %s", request.method)
    if request.headers then
        for index, value in ipairs(request.headers) do
            self.logger:trace("%s", value)
        end
    end
    if request.body then
        self.logger:debug("Body: %s", request.body)
    end
end


function this:HandleInitialize(params)
    -- TODO reset state

    return {
        initialized = true,
    }
end

---@param request Http.Request
---@return table
function this:HandlePOST(request)
    -- TODO check headers

    if not request.body then
        self.logger:warn("POST request without body")
        return {
            status = 400,
            headers = { ["Content-Type"] = "application/json" },
            body = jsonrpc.error(nil, jsonrpc.error_code.invalid_request),
        }
    end

    local jsonRpcRequest, err = jsonrpc.request(request.body)
    if not jsonRpcRequest then
        self.logger:error("Invalid JSON-RPC request: %s", err)
        return {
            status = 400,
            headers = { ["Content-Type"] = "application/json" },
            body = jsonrpc.error(nil, jsonrpc.error_code.invalid_request, err), -- need?
        }
    end

    local handler = self.methodHandlers[jsonRpcRequest.method]
    if not handler then
        self.logger:warn("No handler for method: %s", jsonRpcRequest.method)
        return {
            status = 404,
            headers = { ["Content-Type"] = "application/json" },
            body = jsonrpc.error(jsonRpcRequest.id, jsonrpc.error_code.method_not_found),
        }
    end

    local result = handler(self, jsonRpcRequest.params)

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
        body = jsonrpc.result(jsonRpcRequest.id, result),
    }
end

function this:HandleGET(request)
end

---comment
---@param request Http.Request
---@return table
function this:HandleRequest(request)
    local method = http.ParseRequestMethod(request.method)
    if not method then
        self.logger:warn("Invalid request object")
        return {
            status = 400,
            body = "Bad Request",
        }
    end

    local handler = self.requestHandlers[method]
    if handler then
        return handler(self, request)
    else
        self.logger:warn("No handler for method: %s", method)
        return {
            status = 404,
            body = "Not Found",
        }
    end
end

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

---@param request Http.Request
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

--- @param e enterFrameEventData
function this:Listen(e)
    --- @type Socket.TcpClient?
    -- accept as many new clients as available (non-blocking accept)
    while true do
        local client, acceptErr = self.server:accept()
        if not client then
            if acceptErr then
                -- no more pending clients
                self.logger:error(acceptErr)
            end
            break
        end

        self.logger:trace("client accepted")

        -- read the request with a short timeout to parse headers
        client:settimeout(5)
        local request, err, partial = http.ReceiveRequest(client)
        if (not request) or err then
            self.logger:error("Error reading HTTP request: %s", err)
            if partial then
                self.logger:debug("Partial data received: %s", partial)
            end
            pcall(function() client:close() end)
        else
            self:DumpRequest(request)

            if this.IsSSE(request) then
                -- SSE subscription request: send headers and keep client
                local success, sendErr = http.SendResponse(client, "HTTP/1.1 200 OK", {
                    ["Content-Type"] = "text/event-stream",
                    ["Cache-Control"] = "no-cache",
                    ["Connection"] = "keep-alive",
                }, "")
                if not success then
                    self.logger:error("Error sending SSE response: %s", sendErr)
                    pcall(function() client:close() end)
                else
                    self:AddClient(client)
                end
            else
                -- normal request: dispatch through existing handlers and close connection
                local response = self:HandleRequest(request)
                local status = 200
                if response and response.status then status = response.status end
                local reason = "OK"
                if status == 400 then
                    reason = "Bad Request"
                elseif status == 404 then
                    reason = "Not Found"
                elseif status == 500 then
                    reason = "Internal Server Error"
                end
                local body = ""
                if response and response.body then body = response.body end
                local headers = (response and response.headers) or { ["Content-Type"] = "text/plain", ["Connection"] = "close" }
                if headers["Connection"] == nil and headers["connection"] == nil then
                    headers["Connection"] = "close"
                end
                local statusLine = "HTTP/1.1 " .. tostring(status) .. " " .. reason
                local success, sendErr = http.SendResponse(client, statusLine, headers, body)
                if not success then
                    self.logger:error("Error sending response: %s", sendErr)
                end
                pcall(function() client:close() end)
            end
        end
    end
end

function this:Start()
    if self.server then
        self.logger:warn("MCP server is already running")
        return false
    end
    self.server = socket.bind("localhost", "33427")
    if not self.server then
        self.logger:error("Failed to start MCP server on port 33427")
        return false
    end

    self.server:settimeout(0)
    self.enterFrameCallback = function (e)
        self:Listen(e)
        -- broadcast any queued events to connected SSE clients
        self:BroadcastEvents()
    end
    event.register(tes3.event.enterFrame, self.enterFrameCallback)

    self.logger:info("server started on port 33427")
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

    self:CloseAllClients()
    self.server:close()
    self.server = nil
    self.logger:info("server stopped")
    return true
end

return this
--]]
