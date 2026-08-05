param(
    [ValidateRange(0, 3600)]
    [int]$WatchSeconds = 0,
    [string]$OutputPath
)

$ProtocolVersion = "2025-11-25"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

function New-McpRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$SessionId,
        [string]$Body,
        [string]$Accept = "application/json, text/event-stream"
    )

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::$Method, $Url)
    $request.Headers.TryAddWithoutValidation("Accept", $Accept) | Out-Null
    $request.Headers.TryAddWithoutValidation("MCP-Protocol-Version", $ProtocolVersion) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $request.Headers.TryAddWithoutValidation("MCP-Session-Id", $SessionId) | Out-Null
    }
    if ($null -ne $Body) {
        $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, "application/json")
    }
    return $request
}

function Get-RequiredHeaderValue {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpResponseMessage]$Response,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $values = [string[]]@()
    if (-not $Response.Headers.TryGetValues($Name, [ref]$values) -or $values.Count -eq 0 -or [string]::IsNullOrWhiteSpace($values[0])) {
        throw "Missing response header: $Name"
    }
    return $values[0]
}

function Send-McpRequest {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$SessionId,
        [Parameter(Mandatory = $true)][hashtable]$Message
    )

    $body = $Message | ConvertTo-Json -Depth 32 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "MCP request $($Message.method) failed: HTTP $([int]$response.StatusCode)"
        }
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $document = $text | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $document.result) {
            throw "MCP request $($Message.method) returned no result."
        }
        return $document.result
    }
    finally {
        $response.Dispose()
    }
}

function Send-McpNotification {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][hashtable]$Message
    )

    $body = $Message | ConvertTo-Json -Depth 32 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::Accepted) {
            throw "MCP notification $($Message.method) failed: HTTP $([int]$response.StatusCode)"
        }
    }
    finally {
        $response.Dispose()
    }
}

function Start-McpSession {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$Url
    )

    $message = @{
        jsonrpc = "2.0"
        id = 1
        method = "initialize"
        params = @{
            protocolVersion = $ProtocolVersion
            capabilities = @{}
            clientInfo = @{ name = "morrowind-mcp-discover"; version = "1.0.0" }
        }
    }
    $body = $message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "Initialize failed: HTTP $([int]$response.StatusCode)"
        }
        $document = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $document.result) {
            throw "Initialize returned no result."
        }
        return [pscustomobject]@{
            Result = $document.result
            SessionId = Get-RequiredHeaderValue -Response $response -Name "MCP-Session-Id"
        }
    }
    finally {
        $response.Dispose()
    }
}

function Get-McpListSnapshot {
    param(
        [Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][int]$RequestId,
        [Parameter(Mandatory = $true)][ValidateSet("tools/list", "resources/list", "prompts/list")][string]$Method
    )

    return Send-McpRequest -Client $Client -Url $Url -SessionId $SessionId -Message @{
        jsonrpc = "2.0"
        id = $RequestId
        method = $Method
    }
}

function Read-SseEvent {
    param(
        [Parameter(Mandatory = $true)][System.IO.StreamReader]$Reader,
        [Parameter(Mandatory = $true)][datetime]$Deadline
    )

    $dataLines = [System.Collections.Generic.List[string]]::new()
    while ([datetime]::UtcNow -lt $Deadline) {
        $remaining = [int][math]::Ceiling(($Deadline - [datetime]::UtcNow).TotalMilliseconds)
        $task = $Reader.ReadLineAsync()
        if (-not $task.Wait([math]::Max(1, $remaining))) {
            return $null
        }
        $line = $task.Result
        if ($null -eq $line) {
            throw "SSE stream ended while waiting for a notification."
        }
        if ($line.Length -eq 0) {
            if ($dataLines.Count -gt 0) {
                return $dataLines -join "`n"
            }
            continue
        }
        if ($line.StartsWith("data: ")) {
            $dataLines.Add($line.Substring(6))
        }
    }
    return $null
}

try {
    $config = Get-MwmcpConfig
    $endpointUrl = $config.Connection.url
    $postClient = [System.Net.Http.HttpClient]::new()
    $sseClient = [System.Net.Http.HttpClient]::new()
    $sseResponse = $null
    $stream = $null
    $reader = $null
    $sessionId = $null
    try {
        $session = Start-McpSession -Client $postClient -Url $endpointUrl
        $initializeResponse = $session.Result
        $sessionId = $session.SessionId

        Send-McpNotification -Client $postClient -Url $endpointUrl -SessionId $sessionId -Message @{
            jsonrpc = "2.0"
            method = "notifications/initialized"
        }

        $requestId = 2
        $discovery = [ordered]@{
            observed_at = (Get-Date -Format o)
            endpoint = $endpointUrl
            session_id = $sessionId
            initialize = $initializeResponse
            tools = Get-McpListSnapshot -Client $postClient -Url $endpointUrl -SessionId $sessionId -RequestId $requestId -Method "tools/list"
            resources = Get-McpListSnapshot -Client $postClient -Url $endpointUrl -SessionId $sessionId -RequestId ($requestId + 1) -Method "resources/list"
            prompts = Get-McpListSnapshot -Client $postClient -Url $endpointUrl -SessionId $sessionId -RequestId ($requestId + 2) -Method "prompts/list"
            notifications = @()
        }
        $requestId += 3

        if ($WatchSeconds -gt 0) {
            $sseRequest = New-McpRequest -Method "Get" -Url $endpointUrl -SessionId $sessionId -Body $null -Accept "text/event-stream"
            $sseResponse = $sseClient.SendAsync($sseRequest, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            if ($sseResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK -or $sseResponse.Content.Headers.ContentType.MediaType -ne "text/event-stream") {
                throw "Unable to open SSE stream: HTTP $([int]$sseResponse.StatusCode)"
            }
            $stream = $sseResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $reader = [System.IO.StreamReader]::new($stream)
            $deadline = [datetime]::UtcNow.AddSeconds($WatchSeconds)

            while ([datetime]::UtcNow -lt $deadline) {
                $eventData = Read-SseEvent -Reader $reader -Deadline $deadline
                if ($null -eq $eventData) { break }
                $notification = $eventData | ConvertFrom-Json -ErrorAction Stop
                $record = [ordered]@{ observed_at = (Get-Date -Format o); notification = $notification }
                $listMethod = switch ($notification.method) {
                    "notifications/tools/list_changed" { "tools/list" }
                    "notifications/resources/list_changed" { "resources/list" }
                    "notifications/prompts/list_changed" { "prompts/list" }
                    default { $null }
                }
                if ($listMethod) {
                    $record["refreshed"] = Get-McpListSnapshot -Client $postClient -Url $endpointUrl -SessionId $sessionId -RequestId $requestId -Method $listMethod
                    $requestId++
                }
                $discovery.notifications += [pscustomobject]$record
            }
        }

        $json = $discovery | ConvertTo-Json -Depth 64
        if ($OutputPath) {
            $directory = Split-Path -Parent $OutputPath
            if ($directory) { $null = New-Item -ItemType Directory -Path $directory -Force }
            Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
            Write-Host "[INFO] Discovery record: $OutputPath" -ForegroundColor Cyan
        }
        else {
            $json
        }
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($sseResponse) { $sseResponse.Dispose() }
        if ($postClient -and $sessionId) {
            $deleteRequest = New-McpRequest -Method "Delete" -Url $endpointUrl -SessionId $sessionId -Body $null -Accept "application/json"
            $deleteResponse = $postClient.SendAsync($deleteRequest).GetAwaiter().GetResult()
            $deleteResponse.Dispose()
        }
        if ($sseClient) { $sseClient.Dispose() }
        if ($postClient) { $postClient.Dispose() }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
