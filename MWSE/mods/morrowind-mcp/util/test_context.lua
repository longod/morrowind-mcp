local this = {}

---@class MCP.TestContextUnitTest
---@field mode "run"|"run-and-exit"|"skip"
---@field targets string[]

---@class MCP.TestContext
---@field suppressAutoContinue boolean
---@field acceptDisclaimer boolean
---@field unitTest MCP.TestContextUnitTest

---@param contents string
---@return MCP.TestContext? context
---@return string? errorMessage
function this.Parse(contents)
    local json = require("dkjson")
    local decoded, _, decodeError = json.decode(contents)
    if type(decoded) ~= "table" then
        return nil, decodeError or "JSON root must be an object."
    end
    if decoded.version ~= 1 then
        return nil, "Unsupported or missing context version."
    end
    if type(decoded.suppress_auto_continue) ~= "boolean" then
        return nil, "suppress_auto_continue must be a boolean."
    end
    if type(decoded.accept_disclaimer) ~= "boolean" then
        return nil, "accept_disclaimer must be a boolean."
    end
    if type(decoded.unit_test) ~= "table" then
        return nil, "unit_test must be an object."
    end

    local mode = decoded.unit_test.mode
    if mode ~= "run" and mode ~= "run-and-exit" and mode ~= "skip" then
        return nil, "unit_test.mode is invalid."
    end
    if type(decoded.unit_test.targets) ~= "table" then
        return nil, "unit_test.targets must be an array."
    end
    for _, target in ipairs(decoded.unit_test.targets) do
        if type(target) ~= "string" then
            return nil, "unit_test.targets must contain only strings."
        end
    end

    return {
        suppressAutoContinue = decoded.suppress_auto_continue,
        acceptDisclaimer = decoded.accept_disclaimer,
        unitTest = {
            mode = mode,
            targets = decoded.unit_test.targets,
        },
    }, nil
end

---@return MCP.TestContext? context
function this.Load()
    local settings = require("morrowind-mcp.settings")
    local contextPath = settings.modDir .. "tests\\test-context.json"
    local file = io.open(contextPath, "r")
    if not file then
        return nil
    end

    local contents = file:read("*a")
    file:close()
    local context, errorMessage = this.Parse(contents)
    if context == nil then
        -- An invalid residual context must never enable a partial test mode.
        local logger = require("morrowind-mcp.logger").Get({ moduleName = "test_context" })
        logger:warn("Ignoring invalid test context at %s: %s", contextPath, errorMessage or "unknown error")
    end
    return context
end

return this
