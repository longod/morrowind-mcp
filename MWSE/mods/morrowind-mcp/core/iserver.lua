---@class MCP.IServer
local this = {}

---@protected
---@param params table?
---@return MCP.IServer
function this.new(params)
    ---@type MCP.IServer
    local instance = {}
    if params then
        table.copymissing(instance, table.deepcopy(params))
    end
    setmetatable(instance, { __index = this })
    return instance
end

return this

---@class ClientRequest
---@field client Socket.TcpClient?
---@field http_request Http.Request
---@field json_request MCP.JSONRPCRequest|MCP.JSONRPCNotification?

---@class ServerResponse
---@field http_response Http.ResponseStatusCodes
---@field http_headers table<string, string>?
---@field json_result table?
---@field json_error MCP.Error?
---@field request_id MCP.RequestId?
---@field no_body boolean?
---@field keep_open boolean?
---@field response_sent boolean?

---@class MethodResult
---@field http_response Http.ResponseStatusCodes -- TODO simplify 200, 202, 400 or more?
---@field http_headers table<string, string>?
---@field result MCP.Result?
---@field error MCP.Error?
