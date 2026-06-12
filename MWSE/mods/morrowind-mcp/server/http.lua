local this  = {}

local strutil = require("morrowind-mcp.strutil")

--- @param requestLine string
--- @return string?
function this.ParseRequestMethod(requestLine)
    if not strutil.endswith(requestLine, " HTTP/1.1") then
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
            local name = line:sub(1, sep - 1)
            local value = strutil.ltrim(line:sub(sep + 1))
            return name, value
        end
    return nil, nil
end


---@class HttpRequest
---@field method string
---@field headers string[]
---@field body string?

--- @param client LuaSocketTcpClient
--- @return HttpRequest?, string?, string?
function this.ReceiveRequest(client)
    local method, err, partial = client:receive("*l")
    if not method then
        return nil, err, partial
    end

    ---@type HttpRequest
    local request = {
        method = method,
        headers = {},
        body = nil,
    }

    local contentLengthKey = "content-length:"
    local contentLength = 0
    while true do
        local line, err, partial = client:receive("*l")
        if not line then
            return request, err, partial
        end
        if line == "" then
            break
        end

        table.insert(request.headers, line)

        -- parse content length
        if contentLength == 0 then
            if strutil.startswith(line:lower(), contentLengthKey) then
                contentLength = tonumber(line:sub(#contentLengthKey + 1))
            end
        end
    end

    local body = nil
    if contentLength > 0 then
        body, err, partial = client:receive(contentLength)
        if not body then
            return request, err, partial
        end
        request.body = body
    end

    return request, nil, nil
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
