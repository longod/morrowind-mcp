local this = {}

---@deprecated
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
---@return boolean
function this.IsNullOrEmpty(str)
    if str == nil then
        return true
    end
    return str == ""
end

---@param str string
---@return boolean
function this.IsNullOrWhiteSpace(str)
    if str == nil then
        return true
    end
    return str:match("^%s*$") ~= nil
end

---@param str string
---@param from string
---@param to string
---@return string
function this.replace(str, from, to)
    if not str or from == nil or from == "" then
        return str
    end
    to = to or ""

    local parts = {}
    local start = 1
    local replaced = false
    while true do
        local s, e = string.find(str, from, start, true)
        if not s then
            break
        end
        table.insert(parts, string.sub(str, start, s - 1))
        table.insert(parts, to)
        start = e + 1
        replaced = true
    end

    if not replaced then
        return str
    end

    table.insert(parts, string.sub(str, start))
    return table.concat(parts)
end

---@param path string?
---@return string?
function this.splitext(path)
    if type(path) ~= "string" then
        return nil
    end

    local i = string.len(path)
    while i > 0 do
        local ch = string.sub(path, i, i)
        if ch == "/" or ch == "\\" then
            return nil
        end
        if ch == "." then
            return string.sub(path, i)
        end
        i = i - 1
    end

    return nil
end

return this
