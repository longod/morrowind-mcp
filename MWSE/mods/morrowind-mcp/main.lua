
local dataFiles = "Data Files\\"
local testDir = "MWSE\\mods\\morrowind-mcp\\tests"
local dir = dataFiles .. testDir

for file in lfs.dir(dir) do
    if (string.endswith(file:lower(), ".lua")) then
        dofile(dir .. "\\" .. file)
    end
end

local server = require("morrowind-mcp.server.http_server").new()

local function OnInitialized()
    server:Start()
end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")

--- @class tes3scriptVariables
