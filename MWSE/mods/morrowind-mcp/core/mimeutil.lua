local mcp = require("morrowind-mcp.core.mcp")
local strutil = require("morrowind-mcp.core.strutil")

local this = {}

local mimeTypeByExtension = {
    [".apng"] = mcp.mimeType.image_apng,
    [".avif"] = mcp.mimeType.image_avif,
    [".gif"] = mcp.mimeType.image_gif,
    [".jpg"] = mcp.mimeType.image_jpeg,
    [".jpeg"] = mcp.mimeType.image_jpeg,
    [".png"] = mcp.mimeType.image_png,
    [".svg"] = mcp.mimeType.image_svg_xml,
    [".webp"] = mcp.mimeType.image_webp,
    [".bmp"] = mcp.mimeType.image_bmp,
    [".tga"] = mcp.mimeType.image_tga,
    [".dds"] = mcp.mimeType.image_dds,
    [".aac"] = mcp.mimeType.audio_aac,
    [".flac"] = mcp.mimeType.audio_flac,
    [".mp3"] = mcp.mimeType.audio_mpeg,
    [".ogg"] = mcp.mimeType.audio_ogg,
    [".wav"] = mcp.mimeType.audio_wav,
    [".txt"] = mcp.mimeType.text_plain,
    [".json"] = mcp.mimeType.application_json,
}

---@param extension string?
---@return MCP.MimeType
function this.ResolveMimeTypeFromExtension(extension)
    if type(extension) ~= "string" then
        return mcp.mimeType.application_octet_stream
    end

    local normalized = string.lower(extension)
    local mimeType = mimeTypeByExtension[normalized]
    if mimeType then
        return mimeType
    end
    return mcp.mimeType.application_octet_stream
end

---@param resourcePath string
---@return MCP.MimeType
function this.ResolveMimeTypeFromResourcePath(resourcePath)
    local extension = strutil.splitext(resourcePath)
    return this.ResolveMimeTypeFromExtension(extension)
end

return this
