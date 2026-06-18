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

---@type Socket.Module
local socket = require("socket")

---@class MwseHttpServer : MCP.IServer
---@field logger mwseLogger
---@field server Socket.TcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field httpHeaders table<string, string> must headers
---@field requestHandlers table<string, fun(self: MwseHttpServer, request: ClientRequest): ServerResponce?>
---@field methodHandlers table<string, fun(self: MwseHttpServer, params: table?): MethodResult>
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

---@param params table?
---@return MwseHttpServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MwseHttpServer
    if not instance.logger then
        instance.logger = require("morrowind-mcp.logger")
    end
    instance.httpHeaders = {}
    instance.requestHandlers = {
        [http.method.POST] = instance.OnPOST,
        [http.method.GET] = instance.OnGET,
        [http.method.OPTIONS] = instance.OnOPTIONS,
    }
    -- or split sub-category
    instance.methodHandlers = {
        ["initialize"] = instance.OnInitialize,
        ["notifications/initialized"] = instance.OnNotification,
        ["logging/setLevel"] = instance.OnLogging,
        ["prompts/list"] = instance.OnPromptsList,
        ["resources/list"] = instance.OnResourcesList,
        ["tools/list"] = instance.OnToolsList,
    }
    instance:LoadPrompts()
    instance:LoadResources()
    instance:LoadTools()
    return instance
end


function this:LoadPrompts()
    self.prompts = {}
    local dir = dataFiles .. modDir .. "prompts"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local prompt  = dofile(dir .. "\\" .. file) ---@type MCP.IPrompt
            if prompt and type(prompt) == "table" then
                local instance = prompt.new()
                self.prompts[instance.definition.name] = instance
            else
                self.logger:error("Failed to load prompt from file: %s", file)
            end
        end
    end
end

function this:LoadResources()
    self.resources = {}
    local dir = dataFiles .. modDir .. "resources"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local res  = dofile(dir .. "\\" .. file) ---@type MCP.IResource
            if res and type(res) == "table" then
                local instance = res.new()
                self.resources[instance.definition.name] = instance
            else
                self.logger:error("Failed to load resource from file: %s", file)
            end
        end
    end
end

function this:LoadTools()
    self.tools = {}
    local dir = dataFiles .. modDir .. "tools"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local tool = dofile(dir .. "\\" .. file) ---@type MCP.ITool
            if tool and type(tool) == "table" then
                local instance = tool.new()
                self.tools[instance.definition.name] = instance
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
---@field json_request MCP.JSONRPCRequest|MCP.JSONRPCNotification?

---@class ServerResponce
---@field http_responce Http.ResponseStatusCodes
---@field http_headers table<string, string>?
---@field json_result table?
---@field json_error MCP.Error?

---@class MethodResult
---@field http_responce Http.ResponseStatusCodes -- TODO simplify 200, 202, 400 or more?
---@field result table?
---@field error MCP.Error?

--- https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#initialization
---@param params table?
---@return MethodResult
function this:OnInitialize(params)
    -- TODO reset state

    local settings = require("morrowind-mcp.settings")

    -- todo validation and set correct values
    local protocolVersion = "2025-11-25"

    ---@type MethodResult
    local reuslt = {
        http_responce = http.response_code.ok,
        result = {
            ["protocolVersion"] = "2025-11-25",
            ["capabilities"] = {
                ["logging"] = jsonrpc.object(),
                ["prompts"] = {
                    ["listChanged"] = false,
                },
                ["resources"] = {
                    ["subscribe"] = false,
                    ["listChanged"] = false,
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
            },
            ["serverInfo"] = {
                ["name"] = settings.modName,
                ["title"] = settings.modName,
                ["version"] = settings.version,
                ["description"] = settings.description,
                ["icons"] = jsonrpc.array(),
                ["websiteUrl"] = "http://localhost:33427" -- or repository?
            },
            ["instructions"] = "Optional instructions for the client"
        },
    }
    return reuslt
end

---@param params table?
---@return MethodResult
function this:OnPromptsList(params)
    local list = jsonrpc.array(table.size(self.prompts))

    for name, value in pairs(self.prompts) do
        if value:CanExecute({}) then
            table.insert(list, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = {
            prompts = list,
        },
    }
end

---@param params table?
---@return MethodResult
function this:OnResourcesList(params)
    local list = jsonrpc.array(table.size(self.resources))

    for name, value in pairs(self.resources) do
        if value:CanExecute({}) then
            table.insert(list, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = {
            resources = list,
        },
    }
end

---@param params table?
---@return MethodResult
function this:OnToolsList(params)

    local list = jsonrpc.array(table.size(self.tools))

    for name, value in pairs(self.tools) do
        if value:CanExecute({}) then
            table.insert(list, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = {
            tools = list,
        },
    }
end

---@param params table?
---@return MethodResult
function this:OnLogging(params)
    -- TODO set log level for cliant logging
    return {
        http_responce = http.response_code.ok,
    }
end

---@param params table?
---@return MethodResult
function this:OnNotification(params)
    return {
        http_responce = http.response_code.accepted,
    }
end

---@param request ClientRequest
---@return ServerResponce?
function this:OnPOST(request)
    -- TODO check headers

    if not request.json_request then
        ---@type ServerResponce
        return {
            http_responce = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local handler = self.methodHandlers[request.json_request.method]
    if not handler then
        self.logger:warn("No handler for method: %s", request.json_request.method)
        ---@type ServerResponce
        return {
            http_responce = http.response_code.not_implemented, -- ?
            json_error = jsonrpc.error_code.method_not_found,
        }
    end

    self.logger:info("handle method: %s", request.json_request.method)

    local result = handler(self, request.json_request.params)

    ---@type ServerResponce
    return {
        http_responce = result.http_responce,
        json_result = result.result,
        json_error = result.error,
    }
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
            if content == http. content_type.event_stream then
                -- no supported SSE
                self.logger:info("No supported SSE")
                ---@type ServerResponce
                return {
                    http_responce = http.response_code.method_not_allowed,
                    -- json_error = jsonrpc.error_code.method_not_found,
                }
            end
        end
    end
    -- TODO return
end

---@param request ClientRequest
---@return ServerResponce?
function this:OnOPTIONS(request)
    -- Streamable http

    -- Handle OPTIONS requests for CORS preflight
    -- https://github.com/modelcontextprotocol/python-sdk/issues/1079
    local cros = {
        [http.header.access_control_allow_origin] = "*", -- or request hosts?
        [http.header.access_control_allow_methods] = "POST, GET, OPTIONS",
        [http.header.access_control_allow_headers] = table.concat(
        {
          --http.header.authorization,
          http.header.content_type,
          --http.header.x_requested_with,
        },
        ", "),
    }

    ---@type ServerResponce
    return {
        http_responce = http.response_code.no_content,
        http_headers = cros,
            -- json_error = jsonrpc.error_code.method_not_found,
    }
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
                local response = self:HandleRequest({http_request = request, json_request = json_request})
                if response then
                    if response.json_error then
                        local result = http.SendResponse(client, response.http_responce, response.http_headers, jsonrpc.error(id, response.json_error) )
                        self.logger:error("json error: %d\n%s", response.http_responce.code, string.gsub(result.response, "\r", ""))
                    else
                        local result = http.SendResponse(client, response.http_responce, response.http_headers, jsonrpc.result(id, response.json_result) )
                        self.logger:debug("success: %d\n%s", response.http_responce.code, string.gsub(result.response, "\r", ""))
                    end
                else
                    local result = http.SendResponse(client, http.response_code.internal_server_error, nil, jsonrpc.error(id, jsonrpc.error_code.internal_error) )
                    self.logger:error("internal error: %s", string.gsub(result.response, "\r", ""))
                end
            else
                local result = http.SendResponse(client, http.response_code.bad_request, nil, jsonrpc.error(nil, json_error))
                self.logger:error("request error: %s", string.gsub(result.response, "\r", ""))
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
    self.server = socket.bind("localhost", "33427")
    if not self.server then
        self.logger:error("Failed to start MCP server on port 33427")
        return false
    end
    self.server:settimeout(0)

    self.enterFrameCallback = function (e)
        self:Listen(e)
        -- broadcast any queued events to connected SSE clients
        -- self:BroadcastEvents()
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

    -- self:CloseAllClients()
    self.server:close()
    self.server = nil
    self.logger:info("server stopped")
    return true
end

return this
