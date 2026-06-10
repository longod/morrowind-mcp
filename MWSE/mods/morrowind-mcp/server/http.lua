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

local function startswith(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

local function endswith(str, suffix)
    return suffix == "" or string.sub(str, -string.len(suffix)) == suffix
end

--- @param requestLine string
--- @return string?
function this.ParseRequestMethod(requestLine)
    if not endswith(requestLine, " HTTP/1.1") then
        return nil
    end
    local sep = requestLine:find(" ", 1, true)
    if not sep then
        return nil
    end
    local method = requestLine:sub(1, sep - 1)
    return method
end

---@param line string
---@return string?, string?
function this.ParseHeader(line)
        local sep = line:find(":", 1, true)
        if sep then
            local name = line:sub(1, sep - 1):lower()
            local value = this.ltrim(line:sub(sep + 1))
            return name, value
        end
    return nil, nil
end

--- @param client LuaSocketTcpClient
--- @return table<string, string>|nil, string?, string?
function this.ReceiveHeader(client)
    local headers = {}
    while true do
        local line, err, partial = client:receive("*l")
        if not line then
            return nil, err, partial
        end
        if line == "" then
            break
        end

        local name, value = this.ParseHeader(line)
        if name and value then
            headers[name] = value
        end
    end
    return headers
end

--- @param client LuaSocketTcpClient
--- @return table<string, any>|nil, string?, string?
function this.ReceiveRequest(client)
    local requestLine, err, partial = client:receive("*l")
    if not requestLine then
        return nil, err, partial
    end
    local method = this.ParseRequestMethod(requestLine)
    if not method then
        return nil, nil, nil
    end

    local headers, err, partial = this.ReceiveHeader(client)
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

    return {
        method = method,
        headers = headers,
        body = body,
    }
end


--- @param client LuaSocketTcpClient
--- @param statusLine string
--- @param headers table<string, string>
--- @param body string?
--- @return number?, string?
function this.SendResponse(client, statusLine, headers, body)
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
