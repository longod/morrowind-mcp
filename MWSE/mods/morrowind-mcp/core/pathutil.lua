local strutil = require("morrowind-mcp.core.strutil")

local this = {}

---@param resourcePath string
---@return boolean
local function IsValidResourcePath(resourcePath)
    -- Accept only safe, resourceRootDir-relative logical paths.
    if resourcePath == "" or strutil.startswith(resourcePath, "/") then
        return false
    end

    if string.find(resourcePath, "\\", 1, true) or string.find(resourcePath, ":", 1, true) then
        return false
    end

    local segments = strutil.split(resourcePath, "/")
    if not segments then
        return false
    end

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

    return uriScheme .. normalizedPath
end

---@param uri string
---@param uriScheme string
---@return string?
function this.FromUri(uri, uriScheme)
    -- URI must belong to this scheme before extracting the relative path.
    if not strutil.startswith(uri, uriScheme) then
        return nil
    end

    local resourcePath = string.sub(uri, string.len(uriScheme) + 1)
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
