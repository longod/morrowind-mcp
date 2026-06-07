
local function RunTest()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    do
    unitwind:start("morrowind-mcp")


    unitwind:finish()
    end
end
RunTest()
