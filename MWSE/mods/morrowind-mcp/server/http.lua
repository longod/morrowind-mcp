local this = {}

local strutil = require("morrowind-mcp.core.strutil")

-- https://defold.com/ref/stable/socket-lua/
--- lua socket meta data

---@class Socket.TcpClient
---@field settimeout fun(self: Socket.TcpClient, timeout: number, mode?: string): number?, string?
---@field receive fun(self: Socket.TcpClient, pattern?: string|number, prefix?: string): string?, string?, string?
---@field send fun(self: Socket.TcpClient, data: string, i?: number, j?: number): number?, string?, number?
---@field close fun(self: Socket.TcpClient): number?, string?
---@field setpeername fun(self: Socket.TcpClient, host: string, port: number): number?, string?
---@field getpeername fun(self: Socket.TcpClient): string?, string?
---@field setoption fun(self: Socket.TcpClient, name: string, value: any): number?, string?

---@class Socket.TcpServer
---@field accept fun(self: Socket.TcpServer): Socket.TcpClient? , string?
---@field settimeout fun(self: Socket.TcpServer, timeout: number, mode?: string): number?, string?
---@field close fun(self: Socket.TcpServer): number?, string?
---@field getsockname fun(self: Socket.TcpServer): string?, string?
---@field setoption fun(self: Socket.TcpServer, name: string, value: any): number?, string?

---@class Socket.TcpMaster
---@field bind fun(self: Socket.TcpMaster, address: string, port: number): Socket.TcpServer?, string?
---@field connect fun(self: Socket.TcpMaster, address: string, port: number): Socket.TcpClient?, string?
---@field listen fun(self: Socket.TcpMaster, backlog: number): number?, string?
---@field close fun(self: Socket.TcpMaster): number?, string?
---@field settimeout fun(self: Socket.TcpMaster, timeout: number, mode?: string): number?, string?

---@class Socket.Module
---@field bind fun(host: string, port: number|string): Socket.TcpServer?, string?
---@field tcp fun(): Socket.TcpMaster?, string?
---@field select fun(recvt: table?, sendt: table?, timeout?: number): table, table, string?
---@field sleep fun(time:number): number
---@field connect fun(address: string, port: number, locaddr?: string, locport?: number, family?: string): Socket.TcpClient?, string?


---@class Http.Request
---@field method Http.RequestMethod
---@field endpoint string
---@field protocol Http.Protocol
---@field headers table<Http.Header|Http.MCPHeader, string>
---@field body string?

---@class Http.Result
---@field index number?
---@field error string?
---@field lastIndex number?
---@field response string


---@class Http.ResponseStatusCodes
---@field code integer
---@field message string


---@enum Http.RequestMethod
this.method = {
    CONNECT = "CONNECT",
    DELETE = "DELETE",
    GET = "GET",
    HEAD = "HEAD",
    OPTIONS = "OPTIONS",
    PATCH = "PATCH",
    POST = "POST",
    PUT = "PUT",
    TRACE = "TRACE",
}

---@enum Http.Protocol
this.protocol = {
    HTTP1_1 = "HTTP/1.1"
}

---@enum Http.Header
this.header = {
    accept = "accept",
    accept_ch = "accept-ch",
    accept_encoding = "accept-encoding",
    accept_language = "accept-language",
    accept_patch = "accept-patch",
    accept_post = "accept-post",
    accept_ranges = "accept-ranges",
    access_control_allow_credentials = "access-control-allow-credentials",
    access_control_allow_headers = "access-control-allow-headers",
    access_control_allow_methods = "access-control-allow-methods",
    access_control_allow_origin = "access-control-allow-origin",
    access_control_expose_headers = "access-control-expose-headers",
    access_control_max_age = "access-control-max-age",
    access_control_request_headers = "access-control-request-headers",
    access_control_request_method = "access-control-request-method",
    activate_storage_access = "activate-storage-access",
    age = "age",
    allow = "allow",
    alt_svc = "alt-svc",
    alt_used = "alt-used",
    attribution_reporting_eligible = "attribution-reporting-eligible",
    attribution_reporting_register_source = "attribution-reporting-register-source",
    attribution_reporting_register_trigger = "attribution-reporting-register-trigger",
    authorization = "authorization",
    available_dictionary = "available-dictionary",
    cache_control = "cache-control",
    clear_site_data = "clear-site-data",
    connection = "connection",
    content_digest = "content-digest",
    content_disposition = "content-disposition",
    content_dpr = "content-dpr",
    content_encoding = "content-encoding",
    content_language = "content-language",
    content_length = "content-length",
    content_location = "content-location",
    content_range = "content-range",
    content_security_policy = "content-security-policy",
    content_security_policy_report_only = "content-security-policy-report-only",
    content_type = "content-type",
    cookie = "cookie",
    critical_ch = "critical-ch",
    cross_origin_embedder_policy = "cross-origin-embedder-policy",
    cross_origin_embedder_policy_report_only = "cross-origin-embedder-policy-report-only",
    cross_origin_opener_policy = "cross-origin-opener-policy",
    cross_origin_resource_policy = "cross-origin-resource-policy",
    date = "date",
    device_memory = "device-memory",
    dictionary_id = "dictionary-id",
    dnt = "dnt",
    downlink = "downlink",
    dpr = "dpr",
    early_data = "early-data",
    ect = "ect",
    etag = "etag",
    expect = "expect",
    expect_ct = "expect-ct",
    expires = "expires",
    forwarded = "forwarded",
    from = "from",
    host = "host",
    idempotency_key = "idempotency-key",
    if_match = "if-match",
    if_modified_since = "if-modified-since",
    if_none_match = "if-none-match",
    if_range = "if-range",
    if_unmodified_since = "if-unmodified-since",
    integrity_policy = "integrity-policy",
    integrity_policy_report_only = "integrity-policy-report-only",
    keep_alive = "keep-alive",
    last_modified = "last-modified",
    link = "link",
    location = "location",
    max_forwards = "max-forwards",
    nel = "nel",
    no_vary_search = "no-vary-search",
    origin = "origin",
    origin_agent_cluster = "origin-agent-cluster",
    permissions_policy = "permissions-policy",
    permissions_policy_report_only = "permissions-policy-report-only",
    prefer = "prefer",
    preference_applied = "preference-applied",
    priority = "priority",
    proxy_authenticate = "proxy-authenticate",
    proxy_authorization = "proxy-authorization",
    range = "range",
    referer = "referer",
    referrer_policy = "referrer-policy",
    refresh = "refresh",
    reporting_endpoints = "reporting-endpoints",
    repr_digest = "repr-digest",
    retry_after = "retry-after",
    rtt = "rtt",
    save_data = "save-data",
    sec_ch_device_memory = "sec-ch-device-memory",
    sec_ch_dpr = "sec-ch-dpr",
    sec_ch_prefers_color_scheme = "sec-ch-prefers-color-scheme",
    sec_ch_prefers_reduced_motion = "sec-ch-prefers-reduced-motion",
    sec_ch_prefers_reduced_transparency = "sec-ch-prefers-reduced-transparency",
    sec_ch_ua = "sec-ch-ua",
    sec_ch_ua_arch = "sec-ch-ua-arch",
    sec_ch_ua_bitness = "sec-ch-ua-bitness",
    sec_ch_ua_form_factors = "sec-ch-ua-form-factors",
    sec_ch_ua_full_version_list = "sec-ch-ua-full-version-list",
    sec_ch_ua_mobile = "sec-ch-ua-mobile",
    sec_ch_ua_model = "sec-ch-ua-model",
    sec_ch_ua_platform = "sec-ch-ua-platform",
    sec_ch_ua_platform_version = "sec-ch-ua-platform-version",
    sec_ch_ua_wow64 = "sec-ch-ua-wow64",
    sec_ch_viewport_height = "sec-ch-viewport-height",
    sec_ch_viewport_width = "sec-ch-viewport-width",
    sec_ch_width = "sec-ch-width",
    sec_fetch_dest = "sec-fetch-dest",
    sec_fetch_mode = "sec-fetch-mode",
    sec_fetch_site = "sec-fetch-site",
    sec_fetch_storage_access = "sec-fetch-storage-access",
    sec_fetch_user = "sec-fetch-user",
    sec_gpc = "sec-gpc",
    sec_private_state_token = "sec-private-state-token",
    sec_private_state_token_crypto_version = "sec-private-state-token-crypto-version",
    sec_private_state_token_lifetime = "sec-private-state-token-lifetime",
    sec_purpose = "sec-purpose",
    sec_redemption_record = "sec-redemption-record",
    sec_speculation_tags = "sec-speculation-tags",
    sec_websocket_accept = "sec-websocket-accept",
    sec_websocket_extensions = "sec-websocket-extensions",
    sec_websocket_key = "sec-websocket-key",
    sec_websocket_protocol = "sec-websocket-protocol",
    sec_websocket_version = "sec-websocket-version",
    server = "server",
    server_timing = "server-timing",
    service_worker = "service-worker",
    service_worker_allowed = "service-worker-allowed",
    service_worker_navigation_preload = "service-worker-navigation-preload",
    set_cookie = "set-cookie",
    set_login = "set-login",
    sourcemap = "sourcemap",
    speculation_rules = "speculation-rules",
    strict_transport_security = "strict-transport-security",
    supports_loading_mode = "supports-loading-mode",
    te = "te",
    timing_allow_origin = "timing-allow-origin",
    trailer = "trailer",
    transfer_encoding = "transfer-encoding",
    upgrade = "upgrade",
    upgrade_insecure_requests = "upgrade-insecure-requests",
    use_as_dictionary = "use-as-dictionary",
    user_agent = "user-agent",
    vary = "vary",
    via = "via",
    want_content_digest = "want-content-digest",
    want_repr_digest = "want-repr-digest",
    warning = "warning",
    width = "width",
    www_authenticate = "www-authenticate",
    x_content_type_options = "x-content-type-options",
    x_dns_prefetch_control = "x-dns-prefetch-control",
    x_forwarded_for = "x-forwarded-for",
    x_forwarded_host = "x-forwarded-host",
    x_forwarded_proto = "x-forwarded-proto",
    x_frame_options = "x-frame-options",
    x_permitted_cross_domain_policies = "x-permitted-cross-domain-policies",
    x_powered_by = "x-powered-by",
    x_robots_tag = "x-robots-tag",
}

---@enum Http.MCPHeader
this.mcp_header = {
    mcp_protocol_version = "MCP-Protocol-Version",
    mcp_session_id = "MCP-Session-Id",
    mcp_method = "Mcp-Method",
    mcp_name = "Mcp-Name"
}

---@enum Http.ConnectionType
this.connection_type = {
    keep = "keep-alive",
}

---@enum Http.ContentType
this.content_type = {
    json = "application/json",
    event_stream = "text/event-stream",
}

---@param acceptHeader string?
---@param contentType Http.ContentType|string
---@return boolean
function this.AcceptsContentType(acceptHeader, contentType)
    -- Accept can contain comma-separated media ranges with parameters; compare only the media range.
    if not acceptHeader or not contentType then
        return false
    end

    local expected = contentType:lower()
    local slash = expected:find("/", 1, true)
    local expectedType = slash and expected:sub(1, slash - 1) or nil

    for _, value in ipairs(string.split(acceptHeader, ",")) do
        local accepted = string.trim(value:lower())
        local paramsStart = accepted:find(";", 1, true)
        if paramsStart then
            accepted = string.trim(accepted:sub(1, paramsStart - 1))
        end

        if accepted == expected or accepted == "*/*" then
            return true
        end

        if expectedType and accepted == expectedType .. "/*" then
            return true
        end
    end

    return false
end

---@param data string
---@param eventName string?
---@param eventId string?
---@param retry integer?
---@return string
function this.FormatServerSentEvent(data, eventName, eventId, retry)
    -- SSE frames use LF-delimited fields; HTTP headers still use CRLF in SendResponse.
    local event = ""
    if eventId then
        event = event .. string.format("id: %s\n", eventId)
    end
    if eventName then
        event = event .. string.format("event: %s\n", eventName)
    end
    if retry then
        event = event .. string.format("retry: %d\n", retry)
    end

    local normalizedData = string.gsub(data or "", "\r", "")
    for _, line in ipairs(string.split(normalizedData, "\n")) do
        event = event .. string.format("data: %s\n", line)
    end
    return event .. "\n"
end

---@param client Socket.TcpClient
---@param headers table<Http.Header|Http.MCPHeader, string>?
---@return Http.Result
function this.SendSSEHeaders(client, headers)
    -- Send only the stream-opening headers here; the caller keeps the socket open for later events.
    local sseHeaders = {
        [this.header.content_type] = this.content_type.event_stream,
        [this.header.cache_control] = "no-cache",
        [this.header.connection] = this.connection_type.keep,
    }
    if headers then
        for name, value in pairs(headers) do
            sseHeaders[name] = value
        end
    end
    return this.SendResponse(client, this.response_code.ok, sseHeaders)
end

---@param client Socket.TcpClient
---@param data string
---@param eventName string?
---@param eventId string?
---@param retry integer?
---@return Http.Result
function this.SendServerSentEvent(client, data, eventName, eventId, retry)
    -- Write one already-encoded JSON-RPC message as one SSE event.
    local event = this.FormatServerSentEvent(data, eventName, eventId, retry)
    local index, error, lastIndex = client:send(event)
    ---@type Http.Result
    return {
        index = index,
        error = error,
        lastIndex = lastIndex,
        response = event,
    }
end


---@enum Http.ResponseCode
this.response_code = {
    continue = { code = 100, message = "Continue" },
    switching_protocols = { code = 101, message = "Switching Protocols" },
    processing = { code = 102, message = "Processing" },
    early_hints = { code = 103, message = "Early Hints" },
    ok = { code = 200, message = "OK" },
    created = { code = 201, message = "Created" },
    accepted = { code = 202, message = "Accepted" },
    non_authoritative_information = { code = 203, message = "Non-Authoritative Information" },
    no_content = { code = 204, message = "No Content" },
    reset_content = { code = 205, message = "Reset Content" },
    partial_content = { code = 206, message = "Partial Content" },
    multi_status = { code = 207, message = "Multi-Status" },
    already_reported = { code = 208, message = "Already Reported" },
    im_used = { code = 226, message = "IM Used" },
    multiple_choices = { code = 300, message = "Multiple Choices" },
    moved_permanently = { code = 301, message = "Moved Permanently" },
    found = { code = 302, message = "Found" },
    see_other = { code = 303, message = "See Other" },
    not_modified = { code = 304, message = "Not Modified" },
    temporary_redirect = { code = 307, message = "Temporary Redirect" },
    permanent_redirect = { code = 308, message = "Permanent Redirect" },
    bad_request = { code = 400, message = "Bad Request" },
    unauthorized = { code = 401, message = "Unauthorized" },
    payment_required = { code = 402, message = "Payment Required" },
    forbidden = { code = 403, message = "Forbidden" },
    not_found = { code = 404, message = "Not Found" },
    method_not_allowed = { code = 405, message = "Method Not Allowed" }, ---@type Http.ResponseStatusCodes
    not_acceptable = { code = 406, message = "Not Acceptable" },
    proxy_authentication_required = { code = 407, message = "Proxy Authentication Required" },
    request_timeout = { code = 408, message = "Request Timeout" },
    conflict = { code = 409, message = "Conflict" },
    gone = { code = 410, message = "Gone" },
    length_required = { code = 411, message = "Length Required" },
    precondition_failed = { code = 412, message = "Precondition Failed" },
    content_too_large = { code = 413, message = "Content Too Large" },
    uri_too_long = { code = 414, message = "URI Too Long" },
    unsupported_media_type = { code = 415, message = "Unsupported Media Type" },
    range_not_satisfiable = { code = 416, message = "Range Not Satisfiable" },
    expectation_failed = { code = 417, message = "Expectation Failed" },
    im_a_teapot = { code = 418, message = "I'm a teapot" },
    misdirected_request = { code = 421, message = "Misdirected Request" },
    unprocessable_content = { code = 422, message = "Unprocessable Content" },
    locked = { code = 423, message = "Locked" },
    failed_dependency = { code = 424, message = "Failed Dependency" },
    too_early = { code = 425, message = "Too Early" },
    upgrade_required = { code = 426, message = "Upgrade Required" },
    precondition_required = { code = 428, message = "Precondition Required" },
    too_many_requests = { code = 429, message = "Too Many Requests" },
    request_header_fields_too_large = { code = 431, message = "Request Header Fields Too Large" },
    unavailable_for_legal_reasons = { code = 451, message = "Unavailable For Legal Reasons" },
    internal_server_error = { code = 500, message = "Internal Server Error" },
    not_implemented = { code = 501, message = "Not Implemented" },
    bad_gateway = { code = 502, message = "Bad Gateway" },
    service_unavailable = { code = 503, message = "Service Unavailable" },
    gateway_timeout = { code = 504, message = "Gateway Timeout" },
    http_version_not_supported = { code = 505, message = "HTTP Version Not Supported" },
    variant_also_negotiates = { code = 506, message = "Variant Also Negotiates" },
    insufficient_storage = { code = 507, message = "Insufficient Storage" },
    loop_detected = { code = 508, message = "Loop Detected" },
    not_extended = { code = 510, message = "Not Extended" },
    network_authentication_required = { code = 511, message = "Network Authentication Required" },
}

--- @param requestLine string
--- @return string? method
--- @return string? endpoint
--- @return string? protocol
function this.ParseRequestMethod(requestLine)
    local parts = string.split(requestLine, " ")
    if not parts or #parts ~= 3 then
        return nil, nil, nil
    end
    return parts[1], parts[2], parts[3]
end

---@param line string
---@return string?, string?
function this.ParseHeader(line)
    local sep = line:find(":", 1, true)
    if sep then
        local name = line:sub(1, sep - 1):lower()
        local value = string.trim(line:sub(sep + 1))
        return name, value
    end
    return nil, nil
end

--- @param client Socket.TcpClient
--- @return Http.Request?, string?, string?
function this.ReceiveRequest(client)
    local requestLine, err, partial = client:receive("*l")
    -- print(requestLine)
    if not requestLine then
        return nil, err, partial
    end
    local method, endpoint, protocol = this.ParseRequestMethod(requestLine)
    if not method then
        return nil, "Failed to parse request method", nil
    end

    ---@type Http.Request
    local request = {
        method = method,
        endpoint = endpoint,
        protocol = protocol,
        headers = {},
        body = nil,
    }

    while true do
        local line, err, partial = client:receive("*l")
        if not line then
            return request, err, partial
        end
        if line == "" then
            break
        end

        local name, value = this.ParseHeader(line)
        if name and value then
            request.headers[name] = value
        end
    end

    local body = nil
    local contentLength = tonumber(request.headers[this.header.content_length]) or 0
    if contentLength > 0 then
        body, err, partial = client:receive(contentLength)
        if not body then
            return request, err, partial
        end
        request.body = body
    end

    return request, nil, nil
end

---@param client Socket.TcpClient
---@param response_code Http.ResponseStatusCodes
---@param headers table<Http.Header|Http.MCPHeader, string>?
---@param body string?
---@return Http.Result
function this.SendResponse(client, response_code, headers, body)
    local response = string.format("%s %d %s\r\n", this.protocol.HTTP1_1, response_code.code, response_code.message)
    if headers then
        for name, value in pairs(headers) do
            response = response .. string.format("%s: %s\r\n", name, value)
        end
    end
    -- response = response .. string.format("%s: %s\r\n", this.header.connection, "close") -- test
    if body and #body > 0 then
        response = response .. string.format("%s: %s\r\n", this.header.content_type, this.content_type.json)
        response = response .. string.format("%s: %s\r\n", this.header.content_length, #body)
    end
    response = response .. "\r\n"
    if body and #body > 0 then
        response = response .. body
    end
    local index, error, lastIndex = client:send(response)
    ---@type Http.Result
    return {
        index = index,
        error = error,
        lastIndex = lastIndex,
        response = response,
    }
end

return this
