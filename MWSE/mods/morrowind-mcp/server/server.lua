local base = require("morrowind-mcp.iserver")
local http = require("morrowind-mcp.server.http")

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
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCPServer
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this })
    ---@cast instance MCPServer
    instance.logger = require("morrowind-mcp.logger")
    return instance
end

function this.LoadTools(self)

    local dataFiles = "Data Files\\"
    local testDir = "MWSE\\mods\\morrowind-mcp\\tools"
    local dir = dataFiles .. testDir

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

--- @param e enterFrameEventData
function this.Listen(self, e)
    --- @type LuaSocketTcpClient?
    local client = self.server:accept()
    if not client then
        return
    end

    client:settimeout(5)
    local request, err, partial = http.readHttpRequest(client)
    if not request then
        self.logger:error("Error reading HTTP request: %s", err)
        if partial and #partial > 0 then
            self.logger:debug("Partial data received: %s", partial)
        end
        client:close()
        return
    end

    self.logger:info("Received HTTP request: %s", request.requestLine)
    for name, value in pairs(request.headers) do
        self.logger:info("Header: %s=%s", name, value)
    end
    if #request.body > 0 then
        self.logger:info("Body (%d bytes): %s", #request.body, request.body)
    end

    local success, sendErr = http.sendHttpResponse(client, "HTTP/1.1 200 OK", {
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
