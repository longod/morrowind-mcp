local this  = {}

---@param str string
---@return string
function this.ltrim(str)
    local i = 1
    local len = #str
    while i <= len and str:sub(i, i) == " " do
        i = i + 1
    end
    return str:sub(i)
end

--- @param client LuaSocketTcpClient
--- @return table<string, string>|nil, string?, string?
function this.readHeaders(client)
    local headers = {}
    while true do
        local line, err, partial = client:receive("*l")
        if not line then
            return nil, err, partial
        end
        if line == "" then
            break
        end

        local sep = line:find(":", 1, true)
        if sep then
            local name = line:sub(1, sep - 1):lower()
            local value = this.ltrim(line:sub(sep + 1))
            headers[name] = value
        end
    end
    return headers
end

--- @param client LuaSocketTcpClient
--- @return table<string, any>|nil, string?, string?
function this.readHttpRequest(client)
    local requestLine, err, partial = client:receive("*l")
    if not requestLine then
        return nil, err, partial
    end

    local headers, err, partial = this.readHeaders(client)
    if not headers then
        return nil, err, partial
    end

    local length = tonumber(headers["content-length"]) or 0
    local body = ""
    if length > 0 then
        body, err, partial = client:receive(length)
        if not body then
            return nil, err, partial
        end
    end

    local method = this.parseRequestMethod(requestLine)

    return {
        requestLine = requestLine,
        method = method,
        headers = headers,
        body = body,
    }
end

--- @param requestLine string
--- @return string
function this.parseRequestMethod(requestLine)
    local sep = requestLine:find(" ", 1, true)
    if not sep then
        return requestLine
    end
    return requestLine:sub(1, sep - 1)
end

--- @param client LuaSocketTcpClient
--- @param statusLine string
--- @param headers table<string, string>
--- @param body string?
--- @return number?, string?
function this.sendHttpResponse(client, statusLine, headers, body)
    local response = statusLine .. "\r\n"
    for name, value in pairs(headers) do
        response = response .. string.format("%s: %s\r\n", name, value)
    end
    response = response .. "\r\n"
    if body and #body > 0 then
        response = response .. body
    end
    return client:send(response)
end


return this
