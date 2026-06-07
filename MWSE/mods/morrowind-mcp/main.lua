local config = require("morrowind-mcp.config")
local logger = require("morrowind-mcp.logger")
local settings = require("morrowind-mcp.settings")

local function OnInitialized()

end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")

local dataFiles = "Data Files\\"
local testDir = "MWSE\\mods\\morrowind-mcp\\tests"
local dir = dataFiles .. testDir

for file in lfs.dir(dir) do
    if (string.endswith(file:lower(), ".lua")) then
        -- table.insert(commandFiles, config.commandDir .. "\\" .. file)
    end
end

--- @class tes3scriptVariables
