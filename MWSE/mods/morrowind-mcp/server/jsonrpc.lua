local this = {}

-- TODO move to server.lua or anyway
---@enum JsonRPC.ResultType
this.resultTypes = {
    complete = "complete",
    input_required = "input_required",
}

---@class JsonRPC.Request
---@field jsonrpc string
---@field id string|number
---@field method string
---@field params table?

---@class JsonRPC.Result
---@field jsonrpc string
---@field id string|number
---@field result table?

---@class JsonRPC.Notification
---@field jsonrpc string
---@field method string
---@field params table?

---@class JsonRPC.ErrorObject
---@field code integer
---@field message string
---@field data any

---@class JsonRPC.Error
---@field jsonrpc string
---@field id string|number?
---@field error JsonRPC.ErrorObject


--- -32000 to -32099	Server error -- Reserved for implementation-defined server-errors.
this.error_code = {
    --- standard error code
    parse_error = { code = -32700, message = "Parse error" }, ---@type JsonRPC.ErrorObject Invalid JSON was received by the server. An error occurred on the server while parsing the JSON text.
    invalid_request = { code = -32600, message = "Invalid Request" }, ---@type JsonRPC.ErrorObject The JSON sent is not a valid Request object.
    method_not_found = { code = -32601, message = "Method not found" }, ---@type JsonRPC.ErrorObject The method does not exist / is not available.
    invalid_params = { code = -32602, message = "Invalid params" }, ---@type JsonRPC.ErrorObject Invalid method parameter(s).
    internal_error = { code = -32603, message = "Internal error" }, ---@type JsonRPC.ErrorObject Internal JSON-RPC error.
    --- mcp
    header_mismatch = { code = -32001, message = "Header mismatch" }, ---@type JsonRPC.ErrorObject https://modelcontextprotocol.io/specification/draft/basic/transports/streamable-http#server-validation
}

---@param tbl table
---@return boolean
local function IsArray(tbl)
    if type(tbl) ~= "table" then return false end
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
        -- キーが1以上の整数型であり、かつテーブルのサイズを超えていないか判定
        if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k or k > #tbl then
            return false
        end
    end
    return count == #tbl
end

---@param tbl table
---@param forceType string?
---@return table
local function AddType(tbl, forceType)
    if tbl.type then
        return tbl -- error
    end
    if forceType then
        tbl.type = forceType
        return tbl
    end
    for key, value in pairs(tbl) do
        local t = type(value)
        if t == "nil" then
            tbl.type = "null"
        elseif t == "table" then
            tbl.type = IsArray(tbl) and "array" or "object"
        elseif t == "function" then
            -- error
        elseif t == "thread" then
            -- error
        elseif t == "userdata" then
            -- error
        else
            -- number, string, boolean
            tbl.type = t
        end
        break
    end
    return tbl
end

---@param reserved number?
---@return table
function this.object(reserved)
    local t = table.new(0, reserved or 0)
    setmetatable(t, { __jsontype = "object" })
    return t
end

---@param reserved number?
---@return table
function this.array(reserved)
    local t = table.new(reserved or 0, 0)
    setmetatable(t, { __jsontype = "array" })
    return t
end

local dummy_object = this.object()

---@param str string
---@return JsonRPC.Request|JsonRPC.Notification? json
---@return JsonRPC.ErrorObject?
function this.request(str)
    if not str then -- allow nil
        return nil, nil
    end
    local success, result = pcall(json.decode, str)
    if not success or result == nil then
        return nil, this.error_code.parse_error
    end

    if result.jsonrpc ~= "2.0" then
        return nil, this.error_code.invalid_request
    end
    -- possible notification
    -- local t = type(result.id)
    -- if t ~= "string" and t ~= "number" then
    --     return nil, this.error_code.invalid_request
    -- end
    if type(result.method) ~= "string" then
        return nil, this.error_code.invalid_request
    end
    if result.params and type(result.params) ~= "table" then
        return nil, this.error_code.invalid_request
    end
    -- typeがあったらキャストする？
    return result
end

---@param id string|number?
---@param params table?
---@return string
function this.result(id, params)
    ---@type JsonRPC.Result
    local body = {
        jsonrpc = "2.0",
        id = id,
        result = params or dummy_object,
    }
    -- TODO typeの追加... deepcopyがいる？
    local encoded = json.encode(body, { indent = false })
    return encoded
end

---@param id string|number?
---@param err JsonRPC.ErrorObject
---@param data any?
---@return string
function this.error(id, err, data)
    ---@type JsonRPC.Error
    local body = {
        jsonrpc = "2.0",
        id = id,
        error = err,
    }
    if id then
        body.id = id
    end
    if data then
        body.error = table.deepcopy(body.error) -- const original table
        body.error.data = data
        -- TODO typeの追加
    end
    return json.encode(body, { indent = false })
end

--- maybe server should not use notification.
---@param method string
---@param params table?
---@return string
function this.notification(method, params)
    ---@type JsonRPC.Notification
    local body = {
        jsonrpc = "2.0",
        method = method,
    }
    if params then
        body.params = params
    end
    return json.encode(body, { indent = false })

end

return this
