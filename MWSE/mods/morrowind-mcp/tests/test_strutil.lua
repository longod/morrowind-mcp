local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local strutil = require("morrowind-mcp.core.strutil")

    unitwind:start("morrowind-mcp.core.strutil")

    unitwind:test("replace substitutes strings correctly", function()
        unitwind:expect(strutil.replace("hello world", "world", "morrowind")).toBe("hello morrowind")
        unitwind:expect(strutil.replace("aaaa", "aa", "b")).toBe("bb")
        unitwind:expect(strutil.replace("abc", "d", "x")).toBe("abc")
        unitwind:expect(strutil.replace("a.b.c", ".", "%")).toBe("a%b%c")
        unitwind:expect(strutil.replace("abc", "", "x")).toBe("abc")
        unitwind:expect(strutil.replace(nil, "a", "b")).toBe(nil) ---@diagnostic disable-line: param-type-mismatch
    end)

    unitwind:test("splitext extracts file extension", function()
        unitwind:expect(strutil.splitext("Textures/abc.dds")).toBe(".dds")
        unitwind:expect(strutil.splitext("Textures/ABC.DDS")).toBe(".DDS")
        unitwind:expect(strutil.splitext("no_extension")).toBe(nil)
        unitwind:expect(strutil.splitext("Textures/folder.name/file")).toBe(nil)
        unitwind:expect(strutil.splitext("Textures/folder.name/file.tga")).toBe(".tga")
        unitwind:expect(strutil.splitext(nil)).toBe(nil) ---@diagnostic disable-line: param-type-mismatch
    end)

    unitwind:finish()

    return { testsPassed = unitwind.testsPassed, testsFailed = unitwind.testsFailed }
end

return this
