local settings = require("morrowind-mcp.settings")
local this = {}

local notifyPrefix = settings.modName .. ": "

--- Show a toast that is visibly and semantically owned by Morrowind MCP.
---@param text any
---@param ... any
---@return tes3uiElement? element
function this.showNotifyMenu(text, ...)
    local message = tostring(text)
    if select("#", ...) > 0 then
        message = string.format(message, ...)
    end
    message = notifyPrefix .. message
    -- Pass the completed message as an argument so percent characters in game data are never formatted again.
    return tes3ui.showNotifyMenu("%s", message)
end

--- Return whether a displayed toast belongs to Morrowind MCP.
---@param text any
---@return boolean owned
function this.isOwnNotify(text)
    if type(text) ~= "string" then
        return false
    end
    return string.sub(text, 1, string.len(notifyPrefix)) == notifyPrefix
end

return this
