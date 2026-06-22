local function Test()
    -- commandline and environment variables are not available in MWSE with MO2
    -- so we use a file to indicate that we should exit after running tests
    local dataFiles = "Data Files\\"
    local exitAfterFlagPath = dataFiles .. "MWSE\\mods\\morrowind-mcp\\.exit-after-tests"
    local exitAfter = lfs.attributes(exitAfterFlagPath, "mode") == "file"
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

local config =require("morrowind-mcp.config")

if config.development.unitTest then
    Test()
end

local server = require("morrowind-mcp.server.http_server").new({
    hostname = config.server.hostname,
    port = config.server.port,
})

---@param e initializedEventData
local function OnInitialized(e)
    server:Start()
end

event.register(tes3.event.initialized, OnInitialized)

require("morrowind-mcp.mcm")

--- @class tes3scriptVariables
