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

---@param str string
---@param prefix string
---@return boolean
function this.startswith(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

---@param str string
---@param suffix string
---@return boolean
function this.endswith(str, suffix)
    return suffix == "" or string.sub(str, -string.len(suffix)) == suffix
end


---@param str string?
---@param token string
---@return string[]?
function this.split(str, token)
    if not str then
        return nil
    end
    if token == "" or token == nil then
        return { str }
    end
    local parts = {}
    local start = 1
    while true do
        local s, e = string.find(str, token, start, true)
        if not s then
            table.insert(parts, string.sub(str, start))
            break
        end
        table.insert(parts, string.sub(str, start, s - 1))
        start = e + 1
    end
    return parts
end

---@param str string
---@param from string
---@param to string
---@return string
function this.replace(str, from, to)
    if not str or from == nil or from == "" then
        return str
    end
    local escapedFrom = from:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return (str:gsub(escapedFrom, to or ""))
end

return this
