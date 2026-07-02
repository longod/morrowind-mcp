param(
    [switch]$NoStart,
    [switch]$NoStop
)

$MaxTry = 10
$IntervalMilliseconds = 1000
$SseReadTimeoutMilliseconds = 10000
$ProtocolVersion = "2025-11-25"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")

try {
    $Config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function New-McpRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Url,
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
        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpResponseMessage]$Response,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $values = [string[]]@()
    if (-not $Response.Headers.TryGetValues($Name, [ref]$values)) {
        throw "Missing response header: $Name"
    }
    if ($values.Count -eq 0 -or [string]::IsNullOrWhiteSpace($values[0])) {
        throw "Empty response header: $Name"
    }
    return $values[0]
}

function Send-McpJson {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$SessionId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Message
    )

    $body = $Message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    return $Client.SendAsync($request).GetAwaiter().GetResult()
}

function Send-McpDelete {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )

    $request = New-McpRequest -Method "Delete" -Url $Url -SessionId $SessionId -Body $null -Accept "application/json"
    return $Client.SendAsync($request).GetAwaiter().GetResult()
}

function Read-SseDataLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.StreamReader]$Reader,
        [int]$TimeoutMilliseconds = 10000
    )

    # Read only one line task at a time; StreamReader does not support overlapping reads.
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -lt 1) { break }
        $task = $Reader.ReadLineAsync()
        if (-not $task.Wait($remaining)) {
            throw "Timed out waiting for SSE data line."
        }

        $line = $task.Result
        if ($null -eq $line) {
            throw "SSE stream ended before a data line was received."
        }
        if ($line.StartsWith("data: ")) {
            return $line.Substring(6)
        }
    }

    throw "Timed out waiting for SSE data line."
}

$TargetIP = $Config.Connection.host
$TargetPort = [int]$Config.Connection.port
$EndpointUrl = $Config.Connection.url
$StartScriptPath = Join-Path $ScriptDir "start_server_mo2.ps1"
$StopScriptPath = Join-Path $ScriptDir "stop_server.ps1"
$ExitCode = 0

try {
    if (-not $NoStart) {
        Write-Host "[INFO] Starting server..." -ForegroundColor Cyan
        & $StartScriptPath
        if ([int]$LASTEXITCODE -ne 0) {
            Write-Host "[WARN] start_server_mo2.ps1 exited non-zero: $LASTEXITCODE" -ForegroundColor Yellow
        }
    }

    $ProgressPreference = 'SilentlyContinue'
    $connected = $false
    for ($TryCount = 1; $TryCount -le $MaxTry; $TryCount++) {
        $result = Test-NetConnection -ComputerName $TargetIP -Port $TargetPort -WarningAction Ignore -InformationAction Ignore
        if ($result.TcpTestSucceeded) {
            $connected = $true
            break
        }
        [System.Threading.Thread]::Sleep($IntervalMilliseconds)
    }
    if (-not $connected) {
        throw "Failed to connect to the server at ${TargetIP}:${TargetPort}."
    }

    $postClient = [System.Net.Http.HttpClient]::new()
    $sseClient = [System.Net.Http.HttpClient]::new()
    try {
        # Initialize first so the server can bind later POST and GET requests to one MCP session.
        $initialize = @{
            jsonrpc = "2.0"
            id = 1
            method = "initialize"
            params = @{
                protocolVersion = $ProtocolVersion
                capabilities = @{}
                clientInfo = @{
                    name = "morrowind-mcp-sse-test"
                    version = "1.0.0"
                }
            }
        }
        $initializeResponse = Send-McpJson -Client $postClient -Url $EndpointUrl -Message $initialize
        if ($initializeResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "Initialize failed: HTTP $([int]$initializeResponse.StatusCode)"
        }
        $sessionId = Get-RequiredHeaderValue -Response $initializeResponse -Name "MCP-Session-Id"
        Write-Host "[INFO] Session: $sessionId" -ForegroundColor Cyan

        # Client-to-server notifications are POST requests and should be acknowledged with no body.
        $initialized = @{
            jsonrpc = "2.0"
            method = "notifications/initialized"
        }
        $initializedResponse = Send-McpJson -Client $postClient -Url $EndpointUrl -SessionId $sessionId -Message $initialized
        $initializedBody = $initializedResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ($initializedResponse.StatusCode -ne [System.Net.HttpStatusCode]::Accepted) {
            throw "Initialized notification failed: HTTP $([int]$initializedResponse.StatusCode)"
        }
        if (-not [string]::IsNullOrEmpty($initializedBody)) {
            throw "Initialized notification returned a body, expected empty response."
        }

    # Open the session-scoped server-to-client stream before triggering a notification.
        $sseRequest = New-McpRequest -Method "Get" -Url $EndpointUrl -SessionId $sessionId -Body $null -Accept "text/event-stream"
        $sseResponse = $sseClient.SendAsync($sseRequest, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if ($sseResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "SSE GET failed: HTTP $([int]$sseResponse.StatusCode)"
        }
        $mediaType = $sseResponse.Content.Headers.ContentType.MediaType
        if ($mediaType -ne "text/event-stream") {
            throw "Unexpected SSE content type: $mediaType"
        }

        $stream = $sseResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream)

    # logging/setLevel is used as a harmless trigger for a notifications/message event.
        $setLevel = @{
            jsonrpc = "2.0"
            id = 2
            method = "logging/setLevel"
            params = @{
                level = "debug"
            }
        }
        $setLevelResponse = Send-McpJson -Client $postClient -Url $EndpointUrl -SessionId $sessionId -Message $setLevel
        if ($setLevelResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "logging/setLevel failed: HTTP $([int]$setLevelResponse.StatusCode)"
        }

        $data = Read-SseDataLine -Reader $reader -TimeoutMilliseconds $SseReadTimeoutMilliseconds
        $notification = $data | ConvertFrom-Json -ErrorAction Stop
        if ($notification.jsonrpc -ne "2.0") {
            throw "SSE notification has invalid jsonrpc version."
        }
        if ($notification.method -ne "notifications/message") {
            throw "Unexpected SSE notification method: $($notification.method)"
        }
        if ($null -ne $notification.id) {
            throw "SSE notification unexpectedly included an id."
        }

        $deleteResponse = Send-McpDelete -Client $postClient -Url $EndpointUrl -SessionId $sessionId
        if ($deleteResponse.StatusCode -ne [System.Net.HttpStatusCode]::NoContent) {
            throw "Session DELETE failed: HTTP $([int]$deleteResponse.StatusCode)"
        }
        $deletedSseRequest = New-McpRequest -Method "Get" -Url $EndpointUrl -SessionId $sessionId -Body $null -Accept "text/event-stream"
        $deletedSseResponse = $sseClient.SendAsync($deletedSseRequest, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if ($deletedSseResponse.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
            throw "Deleted session GET should return 404, got HTTP $([int]$deletedSseResponse.StatusCode)"
        }

        Write-Host "[PASSED] Received SSE notification: $($notification.method)" -ForegroundColor Green
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($sseResponse) { $sseResponse.Dispose() }
        if ($sseClient) { $sseClient.Dispose() }
        if ($postClient) { $postClient.Dispose() }
    }
}
catch {
    Write-Host "[FAILED] $($_.Exception.Message)" -ForegroundColor Red
    $ExitCode = 1
}
finally {
    if (-not $NoStop) {
        Write-Host "[INFO] Stopping server..." -ForegroundColor Cyan
        & $StopScriptPath
        if ([int]$LASTEXITCODE -ne 0) {
            Write-Host "[WARN] stop_server.ps1 exit code: $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
}

exit $ExitCode
