param(
    [switch]$NoStart,
    [switch]$NoStop
)

$MaxTry = 10
$IntervalMilliseconds = 1000
$ProtocolVersion = "2025-11-25"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogsRoot = Join-Path $ScriptDir "logs\completion_test"
$RunTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$CompletionLogPath = Join-Path $LogsRoot "completion_$RunTimestamp.log"
$MwseLogCopyPath = Join-Path $LogsRoot "mwse_$RunTimestamp.log"
. (Join-Path $ScriptDir "mwmcp_config.ps1")
. (Join-Path $ScriptDir "mwmcp_test_context.ps1")

function Write-CompletionLog {
    param([Parameter(Mandatory = $true)][string]$Message, [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $ForegroundColor
    Add-Content -LiteralPath $CompletionLogPath -Value $Message
}

function New-McpRequest {
    param([Parameter(Mandatory = $true)][string]$Method, [Parameter(Mandatory = $true)][string]$Url, [string]$SessionId, [string]$Body)
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::$Method, $Url)
    $request.Headers.TryAddWithoutValidation("Accept", "application/json, text/event-stream") | Out-Null
    $request.Headers.TryAddWithoutValidation("MCP-Protocol-Version", $ProtocolVersion) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) { $request.Headers.TryAddWithoutValidation("MCP-Session-Id", $SessionId) | Out-Null }
    if ($null -ne $Body) { $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, "application/json") }
    return $request
}

function Send-McpRequest {
    param([Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client, [Parameter(Mandatory = $true)][string]$Url, [string]$SessionId, [Parameter(Mandatory = $true)][hashtable]$Message)
    $body = $Message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) { throw "$($Message.method) failed: HTTP $([int]$response.StatusCode)" }
        $document = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $document.error) { throw "$($Message.method) returned JSON-RPC error $($document.error.code): $($document.error.message)" }
        if ($null -eq $document.result) { throw "$($Message.method) returned no result." }
        return $document.result
    }
    finally { $response.Dispose() }
}

function Send-McpNotification {
    param([Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client, [Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][hashtable]$Message)
    $body = $Message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::Accepted) { throw "$($Message.method) failed: HTTP $([int]$response.StatusCode)" }
        if (-not [string]::IsNullOrEmpty($response.Content.ReadAsStringAsync().GetAwaiter().GetResult())) { throw "$($Message.method) returned a body." }
    }
    finally { $response.Dispose() }
}

function Send-McpInvalidRequest {
    param([Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client, [Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$SessionId, [Parameter(Mandatory = $true)][hashtable]$Message)
    $body = $Message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -SessionId $SessionId -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::BadRequest) { throw "$($Message.method) invalid request failed: HTTP $([int]$response.StatusCode)" }
        $document = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $document.error -or $document.error.code -ne -32602) { throw "$($Message.method) invalid request did not return JSON-RPC -32602." }
    }
    finally { $response.Dispose() }
}

function Start-McpSession {
    param([Parameter(Mandatory = $true)][System.Net.Http.HttpClient]$Client, [Parameter(Mandatory = $true)][string]$Url)
    $message = @{ jsonrpc = "2.0"; id = 1; method = "initialize"; params = @{ protocolVersion = $ProtocolVersion; capabilities = @{}; clientInfo = @{ name = "morrowind-mcp-completion-test"; version = "1.0.0" } } }
    $body = $message | ConvertTo-Json -Depth 16 -Compress
    $request = New-McpRequest -Method "Post" -Url $Url -Body $body
    $response = $Client.SendAsync($request).GetAwaiter().GetResult()
    try {
        if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) { throw "Initialize failed: HTTP $([int]$response.StatusCode)" }
        $document = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop
        $values = [string[]]@()
        if (-not $response.Headers.TryGetValues("MCP-Session-Id", [ref]$values) -or $values.Count -ne 1) { throw "Initialize did not return one MCP-Session-Id." }
        return [pscustomobject]@{ Result = $document.result; SessionId = $values[0] }
    }
    finally { $response.Dispose() }
}

$ExitCode = 0
$client = $null
$config = $null
$screenshotPaths = @()
try {
    $null = New-Item -ItemType Directory -Path $LogsRoot -Force
    Set-Content -LiteralPath $CompletionLogPath -Value "# Morrowind MCP completion test`n# StartedAt: $(Get-Date -Format o)`n"
    $config = Get-MwmcpConfig
    Set-MwmcpTestContext -UnitTestMode "skip" -AcceptDisclaimer $true
    if (-not $NoStart) { & (Join-Path $ScriptDir "start_server_mo2.ps1") }

    $connected = $false
    for ($attempt = 1; $attempt -le $MaxTry; $attempt++) {
        if ((Test-NetConnection -ComputerName $config.Connection.host -Port $config.Connection.port -WarningAction Ignore -InformationAction Ignore).TcpTestSucceeded) { $connected = $true; break }
        [System.Threading.Thread]::Sleep($IntervalMilliseconds)
    }
    if (-not $connected) { throw "Failed to connect to the MCP server." }

    $client = [System.Net.Http.HttpClient]::new()
    $session = Start-McpSession -Client $client -Url $config.Connection.url
    if ($null -eq $session.Result.capabilities.completions) { throw "Initialize does not advertise completions." }
    Send-McpNotification -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message @{ jsonrpc = "2.0"; method = "notifications/initialized" }

    $fileStem = "completion_$RunTimestamp"
    $links = @()
    foreach ($suffix in @("a", "b")) {
        $screenshot = Send-McpRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message @{ jsonrpc = "2.0"; id = 3; method = "tools/call"; params = @{ name = "mw-screenshot-save"; arguments = @{ file_name = "$fileStem-$suffix"; capture_with_ui = $false } } }
        $link = @($screenshot.content | Where-Object { $_.type -eq "resource_link" } | Select-Object -First 1)[0]
        if ($null -eq $link -or $link.uri -notmatch "^morrowind://screenshot/") { throw "Screenshot tool did not return a screenshot resource link." }
        $links += $link
        $screenshotPaths += Join-Path $config.Paths.modDataDir "temp\screenshot\$($link.name)"
    }

    $templates = Send-McpRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message @{ jsonrpc = "2.0"; id = 4; method = "resources/templates/list" }
    if (@($templates.resourceTemplates | Where-Object { $_.uriTemplate -eq "morrowind://screenshot/{file}" }).Count -ne 1) { throw "Screenshot resource template is missing." }

    $completionRequest = @{ jsonrpc = "2.0"; id = 5; method = "completion/complete"; params = @{ ref = @{ type = "ref/resource"; uri = "morrowind://screenshot/{file}" }; argument = @{ name = "file"; value = $fileStem } } }
    $first = Send-McpRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message $completionRequest
    $completionRequest.id = 6
    $second = Send-McpRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message $completionRequest
    $firstValues = @($first.completion.values)
    $secondValues = @($second.completion.values)
    if (($firstValues -join "`0") -ne ($secondValues -join "`0")) { throw "Repeated completion responses have different value order." }
    if ($firstValues.Count -gt 10 -or $first.completion.total -lt $firstValues.Count -or $first.completion.hasMore -ne ($first.completion.total -gt $firstValues.Count)) { throw "Completion result metadata is inconsistent." }
    $expectedNames = @($links | ForEach-Object { $_.name })
    if (($firstValues -join "`0") -ne ($expectedNames -join "`0")) { throw "Completion result order does not match the generated screenshot names." }

    Send-McpInvalidRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message @{ jsonrpc = "2.0"; id = 7; method = "completion/complete"; params = @{ ref = @{ type = "ref/resource"; uri = "morrowind://unknown/{value}" }; argument = @{ name = "value"; value = "" } } }
    Send-McpInvalidRequest -Client $client -Url $config.Connection.url -SessionId $session.SessionId -Message @{ jsonrpc = "2.0"; id = 8; method = "completion/complete"; params = @{ ref = @{ type = "ref/resource"; uri = "morrowind://memory/{collection}/{entity_id}/{document}.json" }; argument = @{ name = "document"; value = "" }; context = @{ arguments = @{ collection = "actors" } } } }

    $deleteRequest = New-McpRequest -Method "Delete" -Url $config.Connection.url -SessionId $session.SessionId -Body $null
    $deleteResponse = $client.SendAsync($deleteRequest).GetAwaiter().GetResult()
    if ($deleteResponse.StatusCode -ne [System.Net.HttpStatusCode]::NoContent) { throw "Session DELETE failed: HTTP $([int]$deleteResponse.StatusCode)" }
    $deleteResponse.Dispose()
    Write-CompletionLog "[PASSED] Completion responses are deterministic." Green
}
catch {
    Write-CompletionLog "[FAILED] $($_.Exception.Message)" Red
    $ExitCode = 1
}
finally {
    if ($client) { $client.Dispose() }
    Remove-MwmcpTestContext
    if (-not $NoStop) { & powershell.exe -NoProfile -File (Join-Path $ScriptDir "stop_server.ps1") }
    foreach ($screenshotPath in $screenshotPaths) {
        if (Test-Path -LiteralPath $screenshotPath) { Remove-Item -LiteralPath $screenshotPath -Force }
    }
    $mwseLogSourcePath = if ($config) { Join-Path $config.Paths.morrowindInstallDir "MWSE.log" }
    if ($mwseLogSourcePath -and (Test-Path -LiteralPath $mwseLogSourcePath)) { Copy-Item -LiteralPath $mwseLogSourcePath -Destination $MwseLogCopyPath -Force }
    Write-CompletionLog "[INFO] Completion test log: $CompletionLogPath" Cyan
    Invoke-MwmcpTestRunSummary -TestType "completion_test" -RunTimestamp $RunTimestamp
}

exit $ExitCode
