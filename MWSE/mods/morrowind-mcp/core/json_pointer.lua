local this = {}

--- Escapes one RFC 6901 reference token for use in a JSON Pointer.
---@param token string
---@return string
function this.EscapeToken(token)
    return (token:gsub("~", "~0"):gsub("/", "~1"))
end

--- Decodes one RFC 6901 reference token and rejects malformed escape sequences.
---@param token string
---@return string? decoded
---@return string? errorMessage
function this.DecodeToken(token)
    local parts = {}
    local index = 1
    while index <= #token do
        local character = string.sub(token, index, index)
        if character ~= "~" then
            parts[table.size(parts) + 1] = character
            index = index + 1
        else
            local escape = string.sub(token, index + 1, index + 1)
            if escape == "0" then
                parts[table.size(parts) + 1] = "~"
            elseif escape == "1" then
                parts[table.size(parts) + 1] = "/"
            else
                return nil, "JSON Pointer contains an invalid RFC 6901 escape."
            end
            index = index + 2
        end
    end
    return table.concat(parts), nil
end

--- Parses an RFC 6901 JSON Pointer into decoded reference tokens.
---@param pointer string
---@return string[]? tokens
---@return string? errorMessage
function this.Parse(pointer)
    if type(pointer) ~= "string" or string.sub(pointer, 1, 1) ~= "/" then
        return nil, "JSON Pointer must begin with '/'."
    end

    local tokens = {}
    local startIndex = 2
    while startIndex <= #pointer + 1 do
        local separatorIndex = string.find(pointer, "/", startIndex, true)
        local endIndex = separatorIndex and separatorIndex - 1 or #pointer
        local token, errorMessage = this.DecodeToken(string.sub(pointer, startIndex, endIndex))
        if not token then
            return nil, errorMessage
        end
        tokens[table.size(tokens) + 1] = token
        if not separatorIndex then
            break
        end
        startIndex = separatorIndex + 1
    end
    return tokens, nil
end

return this
