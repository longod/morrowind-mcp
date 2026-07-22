local this = {}

---@class MCP.UnitWindResult
---@field testsPassed integer
---@field testsFailed integer

---@alias MCP.UnitWindTestFunction fun(): MCP.UnitWindResult

---@param targetSet table<string, boolean>?
local function LogTestTargets(targetSet)
    local logger = require("morrowind-mcp.logger").Get({ moduleName = "unittest" })

    if targetSet == nil then
        logger:info("Planned unit test targets: all test files")
        return
    end

    local targetList = {}
    for target in pairs(targetSet) do
        table.insert(targetList, target)
    end
    table.sort(targetList)

    logger:info("Planned unit test targets: %s", table.concat(targetList, ", "))
end

---@param line string
---@return string?
local function NormalizeTestTarget(line)
    local target = line:gsub("^%s+", ""):gsub("%s+$", "")
    if target == "" or target:sub(1, 1) == "#" then
        return nil
    end

    target = target:match("[^/\\]+$") or target
    target = target:lower()
    if not string.endswith(target, ".lua") then
        target = target .. ".lua"
    end

    return target
end

---@param sentinelPath string
---@return boolean exists
---@return table<string, boolean>?
local function LoadTestTargets(sentinelPath)
    local file = io.open(sentinelPath, "r")
    if not file then
        return false, nil
    end

    local targetSet = {}
    for line in file:lines() do
        local target = NormalizeTestTarget(line)
        if target ~= nil then
            targetSet[target] = true
        end
    end
    file:close()

    if table.size(targetSet) == 0 then
        return true, nil
    end

    return true, targetSet
end

local function HasAutomatedServerTestFlag()
    local settings = require("morrowind-mcp.settings")
    local flagPath = settings.modDir .. ".server-test-running"
    return lfs.attributes(flagPath, "mode") == "file"
end

function this.Run()
    if HasAutomatedServerTestFlag() then
        return
    end

    local settings = require("morrowind-mcp.settings")
    local sentinelPath = settings.modDir .. ".unit-test-targets"
    local hasTestSentinel, testTargets = LoadTestTargets(sentinelPath)

    -- Log the planned targets before any test module starts executing.
    LogTestTargets(testTargets)

    -- Suppress logging for tests to avoid cluttering the test output.
    if hasTestSentinel then
        local config = require("morrowind-mcp.config")
        config.development.logLevel = mwse.logLevel.info
        config.development.logToConsole = false
        local loggerFactory = require("morrowind-mcp.logger")
        loggerFactory.ApplyConfigToAll({ level = config.development.logLevel, logToConsole = config.development.logToConsole })
    end
    local logger = require("morrowind-mcp.logger").Get({ moduleName = "unittest" })

    local totalPassed = 0
    local totalFailed = 0
    local dir = settings.modDir .. "tests"
    for file in lfs.dir(dir) do
        if string.endswith(file:lower(), ".lua") then
            local normalizedFile = file:lower()
            -- An empty sentinel means run the full suite; otherwise only run the listed files.
            if testTargets == nil or testTargets[normalizedFile] then
                local test = dofile(dir .. "\\" .. file)
                if test then
                    local ok, result = pcall(test.Test --[[@as MCP.UnitWindTestFunction]])
                    if not ok then
                        -- Treat runtime errors in Test() as test failures.
                        totalFailed = totalFailed + 1
                        logger:error("Unit test %s failed.", file)
                    elseif type(result) ~= "table" or type(result.testsFailed) ~= "number" then
                        -- Treat malformed Test() results as failures to keep CI signaling reliable.
                        totalFailed = totalFailed + 1
                        logger:error("Unit test %s returned an invalid result.", file)
                    else
                        totalPassed = totalPassed + result.testsPassed
                        totalFailed = totalFailed + result.testsFailed
                        if result.testsFailed > 0 then
                            logger:error("Unit test %s failed: tests_passed=%d tests_failed=%d", file, result.testsPassed, result.testsFailed)
                        else
                            logger:info("Unit test %s passed: tests_passed=%d tests_failed=%d", file, result.testsPassed, result.testsFailed)
                        end
                    end
                end
            end
        end
    end

    if totalFailed > 0 then
        logger:error("Unit test suite completed: tests_passed=%d tests_failed=%d", totalPassed, totalFailed)
    else
        logger:info("Unit test suite completed: tests_passed=%d tests_failed=%d", totalPassed, totalFailed)
    end

    if hasTestSentinel then
        if totalFailed > 0 then
            os.exit(1)
        end

        os.exit(0)
    end
end

return this
