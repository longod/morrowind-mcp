local base = require("morrowind-mcp.core.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")
local strutil = require("morrowind-mcp.core.strutil")
local mcp = require("morrowind-mcp.core.mcp")
local mime = require("morrowind-mcp.core.mime")
local settings = require("morrowind-mcp.settings")
local config = require("morrowind-mcp.config")

---@type Socket.Module
local socket = require("socket")

local maxResponseLogLength = config.development.debug and 1024 or 256

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

---@class MwseHttpServer : MCP.IServer
---@field logger mwseLogger
---@field server Socket.TcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field hostname string
---@field port integer
---@field httpHeaders table<string, string> must headers
---@field requestHandlers table<string, fun(self: MwseHttpServer, request: ClientRequest): ServerResponse?>
---@field methodHandlers table<string, fun(self: MwseHttpServer, params: MCP.RequestParams): MethodResult>
---@field prompts table<string, MCP.IPrompt>
---@field tools table<string, MCP.ITool>
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MwseHttpServer
function this.new(params)
    jsonrpc.SetPrimitivePrefix(settings.name_prefix, settings.title_prefix, settings.description_prefix)

    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MwseHttpServer
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "http_server" })
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
        [mcp.method.resources_templates_list] = instance.OnResourcesTemplatesList,
        [mcp.method.tools_list] = instance.OnToolsList,
        [mcp.method.tools_call] = instance.OnToolsCall,
        [mcp.method.resources_read] = instance.OnResourcesRead,
        [mcp.method.prompts_get] = instance.OnPromptsGet,
    }
    instance:LoadPrompts()
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
        self.logger:trace("%s", str)
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
    -- TODO generator, can be flatten arguments
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
        ["name"] = settings.shortModName,
        ["title"] = settings.modName,
        ["version"] = settings.version,
        ["description"] = settings.description,
        ["icons"] = jsonrpc.array(),
        ["websiteUrl"] = settings.repository
    }
    result.instructions = "Provides Morrowind game-state and metadata access plus in-game action tools via MWSE. To reduce failures, inspect current game context and discover available capabilities before invoking state-changing tools, because some operations depend on runtime conditions (target, loaded cell, menu mode, etc.)."

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
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
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnResourcesList(params)
    ---@type MCP.ListResourcesResult
    local result = jsonrpc.ListResourcesResult()

    -- TODO crawl files from resource directory, or maybe only registered resources
    -- implementation as to resources/

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.PaginatedRequestParams
---@return MethodResult
function this:OnResourcesTemplatesList(params)
    ---@type MCP.ListResourceTemplatesResult
    local result = jsonrpc.ListResourceTemplatesResult()

    -- TODO crawl files from resource directory, or maybe only registered resources
    -- implementation as to resources/

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.ReadResourceRequestParams
---@return MethodResult
function this:OnResourcesRead(params)
    -- TODO move implementation to resources/

    if not params or type(params.uri) ~= "string" then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- Custom resource URIs are resolved as Data Files-relative paths through MWSE/MO2 VFS.
    local prefix = settings.resourceUriPrefix
    if string.sub(params.uri, 1, string.len(prefix)) ~= prefix then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local resourcePath = string.sub(params.uri, string.len(prefix) + 1)
    if resourcePath == "" or string.sub(resourcePath, 1, 1) == "/" or string.find(resourcePath, "\\", 1, true) or string.find(resourcePath, "..", 1, true) or string.find(resourcePath, ":", 1, true) then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local file = io.open(settings.dataFiles .. string.gsub(resourcePath, "/", "\\"), "rb")
    if not file then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local data = file:read("*a")
    file:close()

    local base64 = require("morrowind-mcp.core.base64")
    local mimeType = mime.ResolveMimeTypeFromResourcePath(resourcePath)
    local content = jsonrpc.BlobResourceContents(params.uri, base64.encode(data), mimeType)

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = jsonrpc.ReadResourceResult({ content }),
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
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.CallToolRequestParams
---@return MethodResult
function this:OnToolsCall(params)
    if not params or not params.name then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local tool = self.tools[params.name]
    if not tool then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.method_not_found,
        }
    end
    if not tool:CanExecute(params) then
        ---@type MethodResult
        return {
            http_response = http.response_code.forbidden,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- TODO maybe need more context table (world, player, etc...)
    local result = tool:Execute(params)

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
        result = result,
    }
end

---@param params MCP.GetPromptRequestParams
---@return MethodResult
function this:OnPromptsGet(params)
    if not params or not params.name then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    local prompt = self.prompts[params.name]
    if not prompt then
        ---@type MethodResult
        return {
            http_response = http.response_code.bad_request,
            error = jsonrpc.error_code.method_not_found,
        }
    end
    if not prompt:CanExecute(params) then
        ---@type MethodResult
        return {
            http_response = http.response_code.forbidden,
            error = jsonrpc.error_code.invalid_params,
        }
    end

    -- TODO maybe need more context table (world, player, etc...)
    local result = prompt:Execute(params)

    ---@type MethodResult
    return {
        http_response = http.response_code.ok,
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
        http_response = http.response_code.ok,
    }
end

---@param params MCP.NotificationParams
---@return MethodResult
function this:OnNotification(params)
    --- curretly, this function is fallback for notifications, nothing to do, just return 202 Accepted
    self.logger:info("Received notification")
    ---@type MethodResult
    return {
        http_response = http.response_code.accepted,
    }
end

---@param request ClientRequest
---@return ServerResponse?
function this:OnPOST(request)
    -- TODO check headers

    if not request.json_request then
        ---@type ServerResponse
        return {
            http_response = http.response_code.bad_request,
            json_error = jsonrpc.error_code.invalid_request,
        }
    end

    local handler = self.methodHandlers[request.json_request.method]
    if not handler then
        self.logger:warn("No handler for method: %s", request.json_request.method)
        ---@type ServerResponse
        return {
            http_response = http.response_code.not_implemented, -- ?
            json_error = jsonrpc.error_code.method_not_found,
        }
    end

    self.logger:info("handle method: %s", request.json_request.method)
    local param = request.json_request.params or {}
    local success, result = xpcall(
        function()
            return handler(self, param)
        end,
        function(err)
            return debug.traceback(tostring(err), 2)
        end
    )
    if not success then
        self.logger:error("Failed to execute method %s\n%s", request.json_request.method, result)
        ---@type ServerResponse
        return {
            http_response = http.response_code.internal_server_error,
            json_error = jsonrpc.error_code.internal_error,
        }
    end

    ---@type ServerResponse
    return {
        http_response = result.http_response,
        json_result = result.result,
        json_error = result.error,
    }
end

---@param request ClientRequest
---@return ServerResponse?
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
                ---@type ServerResponse
                return {
                    http_response = http.response_code.method_not_allowed,
                    -- json_error = jsonrpc.error_code.method_not_found,
                }
            end
        end
    end
    -- TODO return
end

---@param request ClientRequest
---@return ServerResponse?
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

    ---@type ServerResponse
    return {
        http_response = http.response_code.no_content,
        http_headers = cros,
        -- json_error = jsonrpc.error_code.method_not_found,
    }
end

---@param request ClientRequest
---@return ServerResponse?
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
            self.logger:error("bad request: %d%s", http.response_code.bad_request.code, FormatResponseForLog(result.response))

            pcall(function() client:close() end)
        else
            self:DumpRequest(request)

            local json_request, json_error = jsonrpc.request(request.body)
            local id = json_request and json_request.id or nil ---@type string|number?
            if not json_error then
                local response = self:HandleRequest({http_request = request, json_request = json_request})
                if response then
                    if response.json_error then
                        local result = http.SendResponse(client, response.http_response, response.http_headers, jsonrpc.error(id, response.json_error) )
                        self.logger:error("json error: %d\n%s", response.http_response.code, FormatResponseForLog(result.response))
                    else
                        local result = http.SendResponse(client, response.http_response, response.http_headers, jsonrpc.result(id, response.json_result) )
                        self.logger:debug("success: %d\n%s", response.http_response.code, FormatResponseForLog(result.response))
                    end
                else
                    local result = http.SendResponse(client, http.response_code.internal_server_error, nil, jsonrpc.error(id, jsonrpc.error_code.internal_error) )
                    self.logger:error("internal error: %d\n%s", http.response_code.internal_server_error.code, FormatResponseForLog(result.response))
                end
            else
                local result = http.SendResponse(client, http.response_code.bad_request, nil, jsonrpc.error(nil, json_error))
                self.logger:error("request error: %d\n%s", http.response_code.bad_request.code, FormatResponseForLog(result.response))
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
