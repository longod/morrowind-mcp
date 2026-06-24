local mcp = require("morrowind-mcp.core.mcp")
local strutil = require("morrowind-mcp.core.strutil")

local this = {}

local mimeTypeByExtension = {
    [".apng"] = mcp.mime_type.image_apng,
    [".avif"] = mcp.mime_type.image_avif,
    [".gif"] = mcp.mime_type.image_gif,
    [".jpg"] = mcp.mime_type.image_jpeg,
    [".jpeg"] = mcp.mime_type.image_jpeg,
    [".png"] = mcp.mime_type.image_png,
    [".svg"] = mcp.mime_type.image_svg_xml,
    [".webp"] = mcp.mime_type.image_webp,
    [".bmp"] = mcp.mime_type.image_bmp,
    [".tga"] = mcp.mime_type.image_tga,
    [".dds"] = mcp.mime_type.image_dds,
    [".aac"] = mcp.mime_type.audio_aac,
    [".flac"] = mcp.mime_type.audio_flac,
    [".mp3"] = mcp.mime_type.audio_mpeg,
    [".ogg"] = mcp.mime_type.audio_ogg,
    [".wav"] = mcp.mime_type.audio_wav,
    [".txt"] = mcp.mime_type.text_plain,
    [".json"] = mcp.mime_type.application_json,
}

---@param extension string?
---@return MCP.MimeType
function this.ResolveMimeTypeFromExtension(extension)
    if type(extension) ~= "string" then
        return mcp.mime_type.application_octet_stream
    end

    local normalized = string.lower(extension)
    local mimeType = mimeTypeByExtension[normalized]
    if mimeType then
        return mimeType
    end
    return mcp.mime_type.application_octet_stream
end

---@param resourcePath string
---@return MCP.MimeType
function this.ResolveMimeTypeFromResourcePath(resourcePath)
    local extension = strutil.splitext(resourcePath)
    return this.ResolveMimeTypeFromExtension(extension)
end

return this
