local function Test()
	local args = os.getCommandLine()
    for index, value in ipairs(args) do
        print(value)
    end

    local exitAfter = false
    local dataFiles = "Data Files\\"
    local testDir = "MWSE\\mods\\morrowind-mcp\\tests"
    local dir = dataFiles .. testDir
    for file in lfs.dir(dir) do
        if (string.endswith(file:lower(), ".lua")) then
            local test = dofile(dir .. "\\" .. file)
            if test then
                pcall(test.Test)
            end
        end
    end
    if exitAfter then
        os.exit(0)
    end
end
Test()

local server = require("morrowind-mcp.server.http_server").new()

local function OnInitialized()
    server:Start()
end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")

--- @class tes3scriptVariables
