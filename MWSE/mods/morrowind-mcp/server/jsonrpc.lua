local this = {}

function this.request(str)
    local success, result = pcall(json.decode, str)
    if success then
        if result.jsonrpc ~= "2.0" then
            return nil, "Invalid JSON-RPC version"
        end
        local t = type(result.id)
        if t ~= "string" and t ~= "number" then
            return nil, "Invalid JSON-RPC id type"
        end
        if type(result.method) ~= "string" then
            return nil, "Invalid JSON-RPC method"
        end
        return result
    else
        return nil, "Invalid JSON"
    end
end

-- TODO move to server.lua or anyway
---@enum ResultType
this.resultTypes = {
    complete = "complete",
    input_required = "input_required",
}

---@enum ErrorCode
this.errorCode = {
    not_found = 404,
}

---@param resultType ResultType
---@param id string|number?
---@param params table?
---@return string
function this.result(resultType, id, params)
    local body = {
        jsonrpc = "2.0",
        id = id,
        result = table.copy(params or {}),
    }
    body.result.type = resultType
    return json.encode(body)
end

---comment
---@param id string|number?
---@param code ErrorCode
---@param message string
---@param data any
---@return string
function this.error(id, code, message, data)
    local body = {
        jsonrpc = "2.0",
        id = id,
        error = {
            code = code,
            message = message,
        },
    }
    if id then
        body.id = id
    end
    if data then
        body.error.data = data
    end
    return json.encode(body)
end

function this.notification(method, params)
    local body = {
        jsonrpc = "2.0",
        method = method,
    }
    if params then
        body.params = table.copy(params)
    end
    return json.encode(body)

end

return this
