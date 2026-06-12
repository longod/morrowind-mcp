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

return this
