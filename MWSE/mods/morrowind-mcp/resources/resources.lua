local base = require("morrowind-mcp.core.iresource")
local jsonrpc = require("morrowind-mcp.server.jsonrpc")

---@class MCP.ResourceManager: MCP.IResource
---@field logger mwseLogger
local this = {}
setmetatable(this, { __index = base })

---@param params table?
---@return MCP.ResourceManager
function this.new(params)
    local instance = base.new(params)
    setmetatable(instance, { __index = this }) ---@cast instance MCP.ResourceManager
    instance.logger = require("morrowind-mcp.logger").Get({ moduleName = "resource" })
    return instance
end

return this
