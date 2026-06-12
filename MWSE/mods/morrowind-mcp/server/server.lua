local base = require("morrowind-mcp.iserver")
local http = require("morrowind-mcp.server.http")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

local dataFiles = "Data Files\\"
local modDir = "MWSE\\mods\\morrowind-mcp\\"


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

---@class LuaSocketTcpClient
---@field settimeout fun(self: LuaSocketTcpClient, timeout: number, mode?: string): number?, string?
---@field receive fun(self: LuaSocketTcpClient, pattern?: string|number, prefix?: string): string?, string?, string?
---@field send fun(self: LuaSocketTcpClient, data: string, i?: number, j?: number): number?, string?, number?
---@field close fun(self: LuaSocketTcpClient): number?, string?
---@field setpeername fun(self: LuaSocketTcpClient, host: string, port: number): number?, string?
---@field getpeername fun(self: LuaSocketTcpClient): string?, string?
---@field setoption fun(self: LuaSocketTcpClient, name: string, value: any): number?, string?

---@class LuaSocketTcpServer
---@field accept fun(self: LuaSocketTcpServer): LuaSocketTcpClient? , string?
---@field settimeout fun(self: LuaSocketTcpServer, timeout: number, mode?: string): number?, string?
---@field close fun(self: LuaSocketTcpServer): number?, string?
---@field getsockname fun(self: LuaSocketTcpServer): string?, string?
---@field setoption fun(self: LuaSocketTcpServer, name: string, value: any): number?, string?

---@class LuaSocketTcpMaster
---@field bind fun(self: LuaSocketTcpMaster, address: string, port: number): LuaSocketTcpServer?, string?
---@field connect fun(self: LuaSocketTcpMaster, address: string, port: number): LuaSocketTcpClient?, string?
---@field listen fun(self: LuaSocketTcpMaster, backlog: number): number?, string?
---@field close fun(self: LuaSocketTcpMaster): number?, string?
---@field settimeout fun(self: LuaSocketTcpMaster, timeout: number, mode?: string): number?, string?

---@class LuaSocketModule
---@field bind fun(host: string, port: number|string): LuaSocketTcpServer?, string?
---@field tcp fun(): LuaSocketTcpMaster?, string?
---@field select fun(recvt: table?, sendt: table?, timeout?: number): table, table, string?
---@field sleep fun(time:number): number
---@field connect fun(address: string, port: number, locaddr?: string, locport?: number, family?: string): LuaSocketTcpClient?, string?
---@type LuaSocketModule
local socket = require("socket")

---@class MCPServer : IServer
---@field logger mwseLogger
---@field server LuaSocketTcpServer?
---@field enterFrameCallback fun(e : enterFrameEventData)?
---@field requestHandlers table<string, fun(self: MCPServer, request: HttpRequest): table>
---@field methodHandlers table<string, fun(self: MCPServer, params: table?): table>
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
---@return MCPServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this })
    ---@cast instance MCPServer
    instance.logger = require("morrowind-mcp.logger")
    instance.requestHandlers = {
        ["POST"] = instance.HandlePOST,
    }
    instance.methodHandlers = {
        ["initialize"] = instance.HandleInitialize,
    }
    return instance
end


function this.LoadPrompts(self)
    local dir = dataFiles .. modDir .. "tools"
    for file in lfs.dir(dir) do
        if (string.endswith(file:lower(), ".lua")) then
            local prompt  = dofile(dir .. "\\" .. file) ---@type IPrompt
            if prompt and type(prompt) == "table" then
                self.prompts[prompt.name] = prompt
            else
                self.logger:error("Failed to load prompt from file: %s", file)
            end
        end
    end
end

function this.LoadResources(self)
    local dir = dataFiles .. modDir .. "resources"
    for file in lfs.dir(dir) do
        if (string.endswith(file:lower(), ".lua")) then
            local res  = dofile(dir .. "\\" .. file) ---@type IResource
            if res and type(res) == "table" then
                self.resources[res.name] = res
            else
                self.logger:error("Failed to load resource from file: %s", file)
            end
        end
    end
end

function this.LoadTools(self)
    local dir = dataFiles .. modDir .. "tools"
    for file in lfs.dir(dir) do
        if (string.endswith(file:lower(), ".lua")) then
            local tool  = dofile(dir .. "\\" .. file) ---@type ITool
            if tool and type(tool) == "table" then
                self.tools[tool.name] = tool
            else
                self.logger:error("Failed to load tool from file: %s", file)
            end
        end
    end
end

---@param request HttpRequest
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

    self:LoadPrompts()
    self:LoadResources()
    self:LoadTools()
    return {
        status = 200,
    }
end

---@param request HttpRequest
---@return table
function this:HandlePOST(request)
    -- TODO check headers

    if not request.body then
        self.logger:warn("POST request without body")
        return {
            status = 400,
            body = "Bad Request",
        }
    end

    local jsonRpcRequest, err = jsonrpc.request(request.body)
    if not jsonRpcRequest then
        self.logger:error("Invalid JSON-RPC request: %s", err)
        return {
            status = 400,
            body = "Bad Request",
        }
    end

    -- unsplit / token
    local handler = self.methodHandlers[jsonRpcRequest.method]
    if not handler then
        self.logger:warn("No handler for method: %s", jsonRpcRequest.method)
        return {
            status = 404,
            body = "Not Found",
        }
    end

    -- 複数フレームにわたって処理する場合stateが必要なので、resultを返すよりも、objectを返す方が良さそう
    return handler(self, jsonRpcRequest.params)

end

---comment
---@param request HttpRequest
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

--- @param e enterFrameEventData
function this.Listen(self, e)
    --- @type LuaSocketTcpClient?
    local client = self.server:accept()
    if not client then
        self.logger:trace("no client")
        return
    end
    self.logger:trace("client accepted")

    local timeout = 10
    client:settimeout(timeout)
    local request, err, partial = http.ReceiveRequest(client)
    if err then
        self.logger:error("Error reading HTTP request: %s", err)
        if partial then
            self.logger:debug("Partial data received: %s", partial)
        end
        client:close()
        return
    end

    self:DumpRequest(request)
    local response = self:HandleRequest(request)


    local success, sendErr = http.SendResponse(client, "HTTP/1.1 200 OK", {
        ["Content-Type"] = "text/event-stream",
        ["Cache-Control"] = "no-cache",
        ["Connection"] = "keep-alive",
    }, "")

    if not success then
        self.logger:error("Error sending response: %s", sendErr)
    end

    client:close()
end

function this.Launch(self)
    if(self.server) then
        self.logger:warn("MCP server is already running")
        return false
    end
    self.server = socket.bind("*", "45024")
    if (not self.server) then
        self.logger:error("Failed to start MCP server on port 45024")
        return false
    end
    self.server:settimeout(0)
    self.enterFrameCallback = function (e)
        self:Listen(e)
    end

    event.register(tes3.event.enterFrame, self.enterFrameCallback)

    self.logger:info("MCP server started on port 45024")
    return true
end

function this.Shutdown(self)
    if self.server then
        if self.enterFrameCallback then
            event.unregister(tes3.event.enterFrame, self.enterFrameCallback)
            self.enterFrameCallback = nil
        end

        self.server:close()
        self.server = nil
        self.logger:info("MCP server stopped")
        return true
    end
    return false
end

return this
