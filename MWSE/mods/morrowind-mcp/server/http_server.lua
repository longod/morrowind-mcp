local base = require("morrowind-mcp.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local strutil = require("morrowind-mcp.strutil")
local mcp = require("morrowind-mcp.mcp")
local settings = require("morrowind-mcp.settings")

---@type Socket.Module
local socket = require("socket")

---@class MwseHttpServer : MCP.IServer
---@field logger mwseLogger
---@field server Socket.TcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field hostname string
---@field port integer
---@field httpHeaders table<string, string> must headers
---@field requestHandlers table<string, fun(self: MwseHttpServer, request: ClientRequest): ServerResponce?>
---@field methodHandlers table<string, fun(self: MwseHttpServer, params: MCP.RequestParams): MethodResult>
---@field prompts table<string, MCP.IPrompt>
---@field resources table<string, MCP.IResource>
---@field tools table<string, MCP.ITool>
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MwseHttpServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MwseHttpServer
    if not instance.logger then
        instance.logger = require("morrowind-mcp.logger")
    end
    instance.hostname = instance.hostname or settings.defaultConfig.server.address
    instance.port = instance.port or settings.defaultConfig.server.port
    instance.httpHeaders = {}
    instance.requestHandlers = {
        [http.method.POST] = instance.OnPOST,
        [http.method.GET] = instance.OnGET,
        [http.method.OPTIONS] = instance.OnOPTIONS,
    }
    -- or split sub-category
    instance.methodHandlers = {
        [mcp.method.initialize] = instance.OnInitialize,
        [mcp.method.notifications_initialized] = instance.OnNotification,
        [mcp.method.logging_setlevel] = instance.OnLoggingSetLevel,
        [mcp.method.prompts_list] = instance.OnPromptsList,
        [mcp.method.resources_list] = instance.OnResourcesList,
        [mcp.method.tools_list] = instance.OnToolsList,
        [mcp.method.tools_call] = instance.OnToolsCall,
    }
    instance:LoadPrompts()
    instance:LoadResources()
    instance:LoadTools()
    return instance
end


function this:LoadPrompts()
    self.prompts = {}
    local dir = settings.modDir .. "prompts\\"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local prompt  = dofile(dir .. file) ---@type MCP.IPrompt
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
    local dir = settings.modDir .. "resources\\"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local res  = dofile(dir .. file) ---@type MCP.IResource
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
    local dir = settings.modDir .. "tools\\"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local tool = dofile(dir .. file) ---@type MCP.ITool
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



--- https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle#initialization
---@param params MCP.InitializeRequestParams
---@return MethodResult
function this:OnInitialize(params)
    -- TODO reset state

    local settings = require("morrowind-mcp.settings")

    ---@type MCP.InitializeResult
    local result = jsonrpc.InitializeResult()
    result.protocolVersion = "2025-11-25"
    result.capabilities = {
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
    }
    result.serverInfo = {
        ["name"] = settings.modName,
        ["title"] = settings.modName,
        ["version"] = settings.version,
        ["description"] = settings.description,
        ["icons"] = jsonrpc.array(),
        ["websiteUrl"] = "http://localhost:33427" -- or repository?
    }
    result.instructions = "Optional instructions for the client"

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnPromptsList(params)
    ---@type MCP.ListPromptsResult
    local result = jsonrpc.ListPromptsResult(table.size(self.prompts))

    for name, value in pairs(self.prompts) do
        if value:CanExecute({}) then
            table.insert(result.prompts, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnResourcesList(params)
    ---@type MCP.ListResourcesResult
    local result = jsonrpc.ListResourcesResult(table.size(self.resources))

    for name, value in pairs(self.resources) do
        if value:CanExecute({}) then
            table.insert(result.resources, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnToolsList(params)
    ---@type MCP.ListToolsResult
    local result = jsonrpc.ListToolsResult(table.size(self.tools))

    for name, value in pairs(self.tools) do
        if value:CanExecute({}) then
            table.insert(result.tools, value.definition)
        end
    end

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.CallToolRequestParams
---@return MethodResult
function this:OnToolsCall(params)
    if not params or not params.name then
        return {
            http_responce = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local tool = self.tools[params.name]
    if not tool then
        return {
            http_responce = http.response_code.bad_request,
            error = jsonrpc.error_code.method_not_found,
        }
    end
    if not tool:CanExecute(params) then
        return {
            http_responce = http.response_code.forbidden,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- TODO maybe need more context table (world, player, etc...)
    local result = tool:Execute(params)

    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.SetLevelRequestParams
---@return MethodResult
function this:OnLoggingSetLevel(params)
    -- TODO set log level for client logging
    self.logger:info("Set log level for client to: %s", params.level)
    ---@type MethodResult
    return {
        http_responce = http.response_code.ok,
    }
end

---@param params MCP.NotificationParams
---@return MethodResult
function this:OnNotification(params)
    --- curretly, this function is fallback for notifications, nothing to do, just return 202 Accepted
    self.logger:info("Received notification")
    ---@type MethodResult
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
    local param = request.json_request.params or {}
    local success, result = pcall(handler, self, param)
    if not success then
        self.logger:error("Failed to execute method %s", request.json_request.method)
        ---@type ServerResponce
        return {
            http_responce = http.response_code.internal_server_error,
            json_error = jsonrpc.error_code.internal_error,
        }
    end

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
    self.server = socket.bind(self.hostname, self.port)
    if not self.server then
        self.logger:error("Failed to start MCP server on %s:%d", self.hostname, self.port)
        return false
    end
    self.server:settimeout(0)

    self.enterFrameCallback = function (e)
        self:Listen(e)
        -- broadcast any queued events to connected SSE clients
        -- self:BroadcastEvents()
    end
    event.register(tes3.event.enterFrame, self.enterFrameCallback)

    self.logger:info("server started on %s:%d", self.hostname, self.port)
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
