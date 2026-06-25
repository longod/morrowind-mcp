local strutil = require("morrowind-mcp.core.strutil")

local this = {}

---@param ch integer
---@return boolean
local function IsUnreservedByte(ch)
    -- RFC3986 unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~"
    return
        (ch >= string.byte("A") and ch <= string.byte("Z")) or
        (ch >= string.byte("a") and ch <= string.byte("z")) or
        (ch >= string.byte("0") and ch <= string.byte("9")) or
        ch == string.byte("-") or
        ch == string.byte(".") or
        ch == string.byte("_") or
        ch == string.byte("~")
end

---@param ch integer
---@return boolean
local function IsHexByte(ch)
    return
        (ch >= string.byte("0") and ch <= string.byte("9")) or
        (ch >= string.byte("A") and ch <= string.byte("F")) or
        (ch >= string.byte("a") and ch <= string.byte("f"))
end

---@param hexPair string
---@return integer?
local function HexPairToByte(hexPair)
    local high = tonumber(string.sub(hexPair, 1, 1), 16)
    local low = tonumber(string.sub(hexPair, 2, 2), 16)
    if not high or not low then
        return nil
    end
    return high * 16 + low
end

---@param path string
---@return string
local function PercentEncodePath(path)
    -- Keep path separator "/" and unreserved bytes; encode everything else as %HH.
    local result = {}
    local len = string.len(path)
    local i = 1
    while i <= len do
        local ch = string.byte(path, i)
        if ch == string.byte("/") or IsUnreservedByte(ch) then
            table.insert(result, string.char(ch))
        else
            table.insert(result, string.format("%%%02X", ch))
        end
        i = i + 1
    end
    return table.concat(result)
end

---@param path string
---@return string?
local function PercentDecodePath(path)
    -- Decode only valid %HH sequences and reject malformed percent encoding.
    local result = {}
    local len = string.len(path)
    local i = 1
    while i <= len do
        local ch = string.byte(path, i)
        if ch == string.byte("%") then
            if i + 2 > len then
                return nil
            end
            local h1 = string.byte(path, i + 1)
            local h2 = string.byte(path, i + 2)
            if not IsHexByte(h1) or not IsHexByte(h2) then
                return nil
            end
            local byteValue = HexPairToByte(string.sub(path, i + 1, i + 2))
            if not byteValue then
                return nil
            end
            table.insert(result, string.char(byteValue))
            i = i + 3
        else
            table.insert(result, string.char(ch))
            i = i + 1
        end
    end
    return table.concat(result)
end

---@param resourcePath string
---@return boolean
local function IsValidResourcePath(resourcePath)
    -- Accept only safe, resourceRootDir-relative logical paths.
    -- Reject empty input and absolute-style paths.
    if resourcePath == "" or strutil.startswith(resourcePath, "/") then
        return false
    end

    -- Reject Windows separators and drive/URI-like colon usage.
    if string.find(resourcePath, "\\", 1, true) or string.find(resourcePath, ":", 1, true) then
        return false
    end

    -- Split by logical URI/resource separator.
    local segments = strutil.split(resourcePath, "/")
    if not segments then
        return false
    end

    -- Reject empty segments and traversal markers.
    for _, segment in ipairs(segments) do
        if segment == "" or segment == "." or segment == ".." then
            return false
        end
    end

    return true
end

---@param resourcePath string
---@param uriScheme string
---@return string?
function this.ToUri(resourcePath, uriScheme)
    -- Normalize separators so URI paths are consistently slash-separated.
    local normalizedPath = string.gsub(resourcePath, "\\", "/")
    if not IsValidResourcePath(normalizedPath) then
        return nil
    end

    -- Encode after validation so reserved characters do not break URI parsing.
    return uriScheme .. PercentEncodePath(normalizedPath)
end

---@param uri string
---@param uriScheme string
---@return string?
function this.FromUri(uri, uriScheme)
    -- URI must belong to this scheme before extracting the relative path.
    if not strutil.startswith(uri, uriScheme) then
        return nil
    end

    local encodedPath = string.sub(uri, string.len(uriScheme) + 1)
    -- Decode first, then validate decoded path safety.
    local resourcePath = PercentDecodePath(encodedPath)
    if not resourcePath then
        return nil
    end

    if not IsValidResourcePath(resourcePath) then
        return nil
    end

    return resourcePath
end

---@param resourcePath string
---@param resourceRootDir string
---@return string?
function this.ToResourceFilePath(resourcePath, resourceRootDir)
    -- Normalize and validate first, then convert to Windows separators for filesystem access.
    local normalizedPath = string.gsub(resourcePath, "\\", "/")
    if not IsValidResourcePath(normalizedPath) then
        return nil
    end

    return resourceRootDir .. string.gsub(normalizedPath, "/", "\\")
end

---@param resourceFilePath string
---@param resourceRootDir string
---@return string?
function this.FromResourceFilePath(resourceFilePath, resourceRootDir)
    -- Convert to slash-separated form so prefix matching works across OS-style separators.
    local normalizedRootDir = string.gsub(resourceRootDir, "\\", "/")
    local normalizedFilePath = string.gsub(resourceFilePath, "\\", "/")
    if not strutil.endswith(normalizedRootDir, "/") then
        normalizedRootDir = normalizedRootDir .. "/"
    end

    if not strutil.startswith(normalizedFilePath, normalizedRootDir) then
        return nil
    end

    local resourcePath = string.sub(normalizedFilePath, string.len(normalizedRootDir) + 1)
    if not IsValidResourcePath(resourcePath) then
        return nil
    end

    return resourcePath
end

return this
