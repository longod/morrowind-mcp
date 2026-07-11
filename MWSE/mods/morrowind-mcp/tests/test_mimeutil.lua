local this = {}

function this.Test()
    local unitwind = require("unitwind").new({
        enabled = true,
        highlight = false,
    })

    local mcp = require("morrowind-mcp.core.mcp")
    local mimeutil = require("morrowind-mcp.core.mimeutil")

    unitwind:start("morrowind-mcp.core.mimeutil")

    unitwind:test("ResolveMimeTypeFromExtension resolves known image and audio extensions", function()
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".png")).toBe(mcp.mimeType.image_png)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".JPEG")).toBe(mcp.mimeType.image_jpeg)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".dds")).toBe(mcp.mimeType.image_dds)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".tga")).toBe(mcp.mimeType.image_tga)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".mp3")).toBe(mcp.mimeType.audio_mpeg)
    end)

    unitwind:test("ResolveMimeTypeFromExtension resolves known text and json extensions", function()
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".txt")).toBe(mcp.mimeType.text_plain)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".json")).toBe(mcp.mimeType.application_json)
    end)

    unitwind:test("ResolveMimeTypeFromExtension falls back to octet-stream for invalid input", function()
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(nil)).toBe(mcp.mimeType.application_octet_stream) ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(123)).toBe(mcp.mimeType.application_octet_stream) ---@diagnostic disable-line: param-type-mismatch
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension(".unknown")).toBe(mcp.mimeType.application_octet_stream)
        unitwind:expect(mimeutil.ResolveMimeTypeFromExtension("png")).toBe(mcp.mimeType.application_octet_stream)
    end)

    unitwind:test("ResolveMimeTypeFromResourcePath uses extension extracted from path", function()
        unitwind:expect(mimeutil.ResolveMimeTypeFromResourcePath("Textures/menu_newgame.tga")).toBe(mcp.mimeType
        .image_tga)
        unitwind:expect(mimeutil.ResolveMimeTypeFromResourcePath("Textures/menu_continue.DDS")).toBe(mcp.mimeType
        .image_dds)
        unitwind:expect(mimeutil.ResolveMimeTypeFromResourcePath("docs/readme.txt")).toBe(mcp.mimeType.text_plain)
    end)

    unitwind:test("ResolveMimeTypeFromResourcePath falls back when extension is missing", function()
        unitwind:expect(mimeutil.ResolveMimeTypeFromResourcePath("Textures/menu_continue")).toBe(mcp.mimeType
        .application_octet_stream)
    end)

    unitwind:finish()
end

return this
