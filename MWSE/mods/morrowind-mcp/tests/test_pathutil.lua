local this = {}

---@return MCP.UnitWindResult
function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local pathutil = require("morrowind-mcp.core.pathutil")
    local settings = require("morrowind-mcp.settings")
    -- Pass uriScheme explicitly because pathutil.lua is intentionally settings-independent.
    local uriScheme = settings.uriScheme

    unitwind:start("morrowind-mcp.core.pathutil")

    unitwind:test("ToUri converts relative paths to scheme URI", function()
        unitwind:expect(pathutil.ToUri("test.jpg", uriScheme)).toBe("morrowind://test.jpg")
        unitwind:expect(pathutil.ToUri("nested/folder/test.png", uriScheme)).toBe("morrowind://nested/folder/test.png")
        unitwind:expect(pathutil.ToUri("nested\\folder\\test.png", uriScheme)).toBe("morrowind://nested/folder/test.png")
    end)

    unitwind:test("FromUri converts scheme URI to relative path", function()
        unitwind:expect(pathutil.FromUri("morrowind://test.jpg", uriScheme)).toBe("test.jpg")
        unitwind:expect(pathutil.FromUri("morrowind://nested/folder/test.png", uriScheme)).toBe("nested/folder/test.png")
    end)

    unitwind:test("ToUri applies percent encoding for reserved characters", function()
        unitwind:expect(pathutil.ToUri("folder/my file#.txt", uriScheme)).toBe("morrowind://folder/my%20file%23.txt")
        unitwind:expect(pathutil.ToUri("folder/a?b&c.txt", uriScheme)).toBe("morrowind://folder/a%3Fb%26c.txt")
    end)

    unitwind:test("FromUri applies percent decoding before validation", function()
        unitwind:expect(pathutil.FromUri("morrowind://folder/my%20file%23.txt", uriScheme)).toBe("folder/my file#.txt")
        unitwind:expect(pathutil.FromUri("morrowind://folder/a%3Fb%26c.txt", uriScheme)).toBe("folder/a?b&c.txt")
    end)

    unitwind:test("FromUri rejects invalid inputs", function()
        unitwind:expect(pathutil.FromUri("http://test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.FromUri("morrowind://../test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.FromUri("morrowind:///test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.FromUri("morrowind://folder//test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.FromUri("morrowind://folder/file%2", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.FromUri("morrowind://folder/file%GG", uriScheme)).toBe(nil)
    end)

    unitwind:test("ToUri rejects invalid inputs", function()
        unitwind:expect(pathutil.ToUri("", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.ToUri("../test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.ToUri("/test.jpg", uriScheme)).toBe(nil)
        unitwind:expect(pathutil.ToUri("folder//test.jpg", uriScheme)).toBe(nil)
    end)

    unitwind:test("ToUri and FromUri are reversible", function()
        local original = "nested/folder/test.dds"
        local converted = pathutil.ToUri(original, uriScheme)
        if converted then
            unitwind:expect(pathutil.FromUri(converted, uriScheme)).toBe(original)
        else
            unitwind:expect(converted).NOT.toBe(nil)
        end
    end)

    unitwind:test("ToResourceFilePath converts to Windows path under resource root", function()
        local rootDir = "X:\\root\\"
        unitwind:expect(pathutil.ToResourceFilePath("test.jpg", rootDir)).toBe("X:\\root\\test.jpg")
        unitwind:expect(pathutil.ToResourceFilePath("nested/folder/test.png", rootDir)).toBe(
            "X:\\root\\nested\\folder\\test.png")
        unitwind:expect(pathutil.ToResourceFilePath("nested\\folder\\test.png", rootDir)).toBe(
            "X:\\root\\nested\\folder\\test.png")
    end)

    unitwind:test("ToResourceFilePath rejects invalid paths", function()
        local rootDir = "X:\\root\\"
        unitwind:expect(pathutil.ToResourceFilePath("", rootDir)).toBe(nil)
        unitwind:expect(pathutil.ToResourceFilePath("../test.jpg", rootDir)).toBe(nil)
        unitwind:expect(pathutil.ToResourceFilePath("/test.jpg", rootDir)).toBe(nil)
        unitwind:expect(pathutil.ToResourceFilePath("folder//test.jpg", rootDir)).toBe(nil)
    end)

    unitwind:test("FromResourceFilePath converts absolute path under root to resource path", function()
        local rootDir = "X:\\root\\"
        unitwind:expect(pathutil.FromResourceFilePath("X:\\root\\test.jpg", rootDir)).toBe("test.jpg")
        unitwind:expect(pathutil.FromResourceFilePath("X:/root/nested/folder/test.png", rootDir)).toBe(
            "nested/folder/test.png")
        unitwind:expect(pathutil.FromResourceFilePath("X:\\root\\nested\\folder\\test.png", rootDir)).toBe(
            "nested/folder/test.png")
    end)

    unitwind:test("FromResourceFilePath rejects paths outside root or invalid resource paths", function()
        local rootDir = "X:\\root\\"
        unitwind:expect(pathutil.FromResourceFilePath("Y:\\root\\test.jpg", rootDir)).toBe(nil)
        unitwind:expect(pathutil.FromResourceFilePath("X:\\root\\..\\test.jpg", rootDir)).toBe(nil)
        unitwind:expect(pathutil.FromResourceFilePath("X:\\root\\folder\\\\test.jpg", rootDir)).toBe(nil)
    end)

    local testsPassed = unitwind.testsPassed
    local testsFailed = unitwind.testsFailed
    unitwind:finish()

    return { testsPassed = testsPassed, testsFailed = testsFailed }
end

return this
