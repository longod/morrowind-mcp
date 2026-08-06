local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local capabilitiesFetch = require("morrowind-mcp.tools.capabilities_fetch")

    unitwind:start("morrowind-mcp.tools.capabilities_fetch")

    unitwind:test("returns sorted conditions for published tools", function()
        local tool
        tool = capabilitiesFetch.new({
            GetPublishedTools = function()
                return {
                    ["alternate-beta"] = {
                        GetCapabilityConditions = function()
                            return "Second condition."
                        end,
                    },
                    ["alternate-alpha"] = {
                        GetCapabilityConditions = function()
                            return "First condition."
                        end,
                    },
                    ["alternate-capabilities-fetch"] = tool,
                }
            end,
        })

        local result = tool:Execute({}, nil)
        local tools = result.structuredContent.tools

        unitwind:expect(table.size(tools)).toBe(2)
        unitwind:expect(tools[1].name).toBe("alternate-alpha")
        unitwind:expect(tools[1].conditions).toBe("First condition.")
        unitwind:expect(tools[2].name).toBe("alternate-beta")
    end)

    unitwind:test("filters conditions by the requested tool name and excludes itself", function()
        local tool
        tool = capabilitiesFetch.new({
            GetPublishedTools = function()
                return {
                    ["alternate-reference-fetch"] = {
                        GetCapabilityConditions = function()
                            return "A game must be active."
                        end,
                    },
                    ["alternate-capabilities-fetch"] = tool,
                }
            end,
        })

        local matching = tool:Execute({ tool_name = "alternate-reference-fetch" }, nil)
        local missing = tool:Execute({ tool_name = "alternate-unknown" }, nil)
        local self = tool:Execute({ tool_name = "alternate-capabilities-fetch" }, nil)

        unitwind:expect(table.size(matching.structuredContent.tools)).toBe(1)
        unitwind:expect(table.size(missing.structuredContent.tools)).toBe(0)
        unitwind:expect(table.size(self.structuredContent.tools)).toBe(0)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
