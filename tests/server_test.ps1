param(
    [switch]$NoForeground
)

$MaxTry = 10
$IntervalSeconds = 3
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

$LogsRoot = Join-Path $ScriptDir "logs\server_test"
$RunTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$InspectorLogPath = Join-Path $LogsRoot "inspector_$RunTimestamp.log"
$MwseLogSourcePath = Join-Path $Config.Paths.morrowindInstallDir "MWSE.log"
$MwseLogCopyPath = Join-Path $LogsRoot "mwse_$RunTimestamp.log"

function Convert-ToFileUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return ([System.Uri]::new($fullPath)).AbsoluteUri
    }
    catch {
        return $Path
    }
}

function Set-WindowForegroundBestEffort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        [int]$MaxTry = 20,
        [int]$IntervalMilliseconds = 500
    )

    for ($i = 0; $i -lt $MaxTry; $i++) {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Select-Object -First 1

        if ($proc) {
            try {
                $activated = (New-Object -ComObject WScript.Shell).AppActivate($proc.Id)
            }
            catch {
                $activated = $false
            }

            if ($activated) {
                Write-Host "[INFO] Activated $ProcessName window in foreground." -ForegroundColor Green
                return $true
            }
        }

        Start-Sleep -Milliseconds $IntervalMilliseconds
    }

    Write-Host "[WARN] Failed to activate $ProcessName window in foreground." -ForegroundColor Yellow
    return $false
}

function Test-RequiresForegroundActivation {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    return $Arguments -contains "mw-player-action"
}

try {
    $null = New-Item -Path $LogsRoot -ItemType Directory -Force
    Set-Content -Path $InspectorLogPath -Value @(
        "# Morrowind MCP server_test inspector log"
        "# StartedAt: $(Get-Date -Format o)"
        "# Endpoint: $($Config.Connection.url)"
        ""
    )
}
catch {
    Write-Host "[ERROR] Failed to initialize inspector log file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Workaround for Inspector issue/PR #1337:
# https://github.com/modelcontextprotocol/inspector/issues/1334
# https://github.com/modelcontextprotocol/inspector/pull/1337
# "Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)" が混在しても
# stdout が有効 JSON かつ実エラーが無ければ成功扱いにする。
function Invoke-MCPInspector {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandArguments = @(
        "--yes",
        "@modelcontextprotocol/inspector",
        "--cli",
        $Config.Connection.url,
        "--transport",
        "http"
    )
    if ($Arguments) { $commandArguments += $Arguments }

    Write-Host "[RUN] $($Arguments -join ' ')" -ForegroundColor Cyan
    # 判定のために標準出力(JSON本体)と標準エラー(エラーメッセージ)を分離して取得する。
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & npx.cmd @commandArguments 1> $stdoutFile 2> $stderrFile
        $result = [int]$LASTEXITCODE
        $runLabel = $Arguments -join ' '

        $stdoutText = if (Test-Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { "" }
        $stderrText = if (Test-Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { "" }

        Add-Content -Path $InspectorLogPath -Value @(
            "================================================================================"
            "[RUN] $runLabel"
            "[TIME] $(Get-Date -Format o)"
            "[EXIT] $result"
            "--- STDERR ---"
        )
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Add-Content -Path $InspectorLogPath -Value $stderrText
        }
        else {
            Add-Content -Path $InspectorLogPath -Value "<empty>"
        }

        Add-Content -Path $InspectorLogPath -Value @(
            "--- STDOUT ---"
        )
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            Add-Content -Path $InspectorLogPath -Value $stdoutText
        }
        else {
            Add-Content -Path $InspectorLogPath -Value "<empty>"
        }
        Add-Content -Path $InspectorLogPath -Value ""

        # Inspector の既知問題で出るノイズ行を定義する。
        $assertionPattern = "Assertion failed: !\(handle->flags & UV_HANDLE_CLOSING\)"
        $knownExitLinePattern = "^Failed with exit code:\s*3221226505\s*$"
        $hasKnownAssertion = $stderrText -match $assertionPattern

        # stdout が正しい JSON として読めるなら、MCP メソッド自体は成功しているとみなせる。
        $hasValidJson = $false
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            try {
                $null = $stdoutText | ConvertFrom-Json -ErrorAction Stop
                $hasValidJson = $true
            }
            catch {
                $hasValidJson = $false
            }
        }

        # 既知ノイズを除いた stderr が残る場合は、実際の失敗(例: Method not found)と判定する。
        $filteredStderrLines = @()
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            $filteredStderrLines = $stderrText -split "`r?`n" | Where-Object {
                $_ -and
                $_ -notmatch $assertionPattern -and
                $_ -notmatch $knownExitLinePattern
            }
        }
        $hasRealStderrError = $filteredStderrLines.Count -gt 0

        # TODO 成功は、jsonの精査も行いたい
        if ($result -eq 0) {
            Write-Host "[PASSED]" -ForegroundColor Green
            return 0
        }

        # Issue/PR #1337 のワークアラウンド:
        # exit code は 1 でも、stdout が有効 JSON かつ stderr が既知ノイズのみなら成功扱いにする。
        if ($result -eq 1 -and $hasKnownAssertion -and $hasValidJson -and -not $hasRealStderrError) {
            Write-Host "[PASSED] (Known UV handle assertion ignored)" -ForegroundColor Green
            return 0
        }

        Write-Host "[FAILED] $result" -ForegroundColor Red
        if ($hasRealStderrError) {
            $preview = $filteredStderrLines | Select-Object -First 5
            foreach ($line in $preview) {
                Write-Host "  $line" -ForegroundColor DarkYellow
            }
        }
        return $result
    }
    finally {
        Remove-Item -Path $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item -Path $stderrFile -ErrorAction SilentlyContinue
    }
}

function New-McpRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$SessionId,
        [string]$Body
    )

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::$Method, $Url)
    $request.Headers.TryAddWithoutValidation("Accept", "application/json, text/event-stream") | Out-Null
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

function Invoke-MemoryTraversalTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EndpointUrl
    )

    Write-Host "[RUN] live memory traversal" -ForegroundColor Cyan
    $client = [System.Net.Http.HttpClient]::new()
    $sessionId = $null
    $requestId = 10000
    $issues = [System.Collections.Generic.List[string]]::new()
    $visited = @{}
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue("morrowind://memory/index.json")

    try {
        $initialize = @{
            jsonrpc = "2.0"
            id = $requestId++
            method = "initialize"
            params = @{
                protocolVersion = $ProtocolVersion
                capabilities = @{}
                clientInfo = @{
                    name = "morrowind-mcp-server-test"
                    version = "1.0.0"
                }
            }
        }
        $initializeResponse = Send-McpJson -Client $client -Url $EndpointUrl -Message $initialize
        if ($initializeResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
            throw "Initialize failed: HTTP $([int]$initializeResponse.StatusCode)"
        }
        $sessionId = Get-RequiredHeaderValue -Response $initializeResponse -Name "MCP-Session-Id"

        $initialized = @{
            jsonrpc = "2.0"
            method = "notifications/initialized"
        }
        $initializedResponse = Send-McpJson -Client $client -Url $EndpointUrl -SessionId $sessionId -Message $initialized
        if ($initializedResponse.StatusCode -ne [System.Net.HttpStatusCode]::Accepted) {
            throw "Initialized notification failed: HTTP $([int]$initializedResponse.StatusCode)"
        }

        while ($queue.Count -gt 0) {
            $uri = [string]$queue.Dequeue()
            if ($visited.ContainsKey($uri)) {
                continue
            }
            $visited[$uri] = $true

            $read = @{
                jsonrpc = "2.0"
                id = $requestId++
                method = "resources/read"
                params = @{
                    uri = $uri
                }
            }
            $readResponse = Send-McpJson -Client $client -Url $EndpointUrl -SessionId $sessionId -Message $read
            $readText = $readResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($readResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK) {
                $issues.Add("Read failed: uri=$uri http=$([int]$readResponse.StatusCode)")
                continue
            }

            try {
                $readBody = $readText | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $issues.Add("Read returned invalid JSON-RPC: uri=$uri error=$($_.Exception.Message)")
                continue
            }
            if ($readBody.error) {
                $issues.Add("Read returned JSON-RPC error: uri=$uri code=$($readBody.error.code) message=$($readBody.error.message)")
                continue
            }

            $content = @($readBody.result.contents | Where-Object { $_.uri -eq $uri } | Select-Object -First 1)
            if ($content.Count -eq 0) {
                $issues.Add("Read result missing requested content: uri=$uri")
                continue
            }
            if ($content[0].mimeType -ne "application/json" -or [string]::IsNullOrWhiteSpace($content[0].text)) {
                $issues.Add("Memory content is not JSON text: uri=$uri mimeType=$($content[0].mimeType)")
                continue
            }

            try {
                $document = $content[0].text | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $issues.Add("Memory document text is invalid JSON: uri=$uri error=$($_.Exception.Message)")
                continue
            }

            foreach ($field in @("schema_version", "type", "data_type", "title", "source", "data")) {
                if ($null -eq $document.PSObject.Properties[$field]) {
                    $issues.Add(("Missing {0}: uri={1}" -f $field, $uri))
                }
            }
            if ($document.type -match '^memory\.(index|collection)$' -and $null -ne $document.data.PSObject.Properties["links"]) {
                $issues.Add("Index/collection duplicates links inside data: uri=$uri")
            }

            foreach ($link in @($document.links)) {
                if ($null -eq $link) {
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($link.uri)) {
                    $issues.Add("Link is missing uri: parent=$uri")
                    continue
                }
                if ($link.uri -notlike "morrowind://memory/*") {
                    continue
                }
                if ($uri -eq "morrowind://memory/actors/index.json" -and $link.rel -eq "actor") {
                    $description = [string]$link.description
                    foreach ($token in @("data_type=", "base_id=", "reference_id=", "identity_kind=", "interaction_state=")) {
                        if (-not $description.Contains($token)) {
                            $issues.Add("Actor link description missing $token parent=$uri child=$($link.uri)")
                        }
                    }
                }
                if (-not $visited.ContainsKey($link.uri)) {
                    $queue.Enqueue($link.uri)
                }
            }
        }
    }
    catch {
        $issues.Add($_.Exception.Message)
    }
    finally {
        $client.Dispose()
    }

    if ($issues.Count -gt 0) {
        Write-Host "[FAILED] live memory traversal" -ForegroundColor Red
        foreach ($issue in ($issues | Select-Object -First 10)) {
            Write-Host "  $issue" -ForegroundColor DarkYellow
        }
        return 1
    }

    Write-Host "[PASSED] live memory traversal: documents=$($visited.Count)" -ForegroundColor Green
    return 0
}

$TargetIP = $Config.Connection.host
$TargetPort = [int]$Config.Connection.port
$StartScriptPath = ".\start_server_mo2.ps1"
$StopScriptPath = ".\stop_server.ps1"
$ServerTestSentinelPath = ".\..\MWSE\mods\morrowind-mcp\.server-test-running"

$ExitCode = 0
$CreatedServerTestSentinel = $false

Push-Location $ScriptDir
try {
    if (-not (Test-Path -LiteralPath $StartScriptPath)) {
        Write-Host "[ERROR] $StartScriptPath was not found." -ForegroundColor Red
        $ExitCode = 1
        return
    }

    if (-not (Test-Path -LiteralPath $StopScriptPath)) {
        Write-Host "[ERROR] $StopScriptPath was not found." -ForegroundColor Red
        $ExitCode = 1
        return
    }

    $ServerTestSentinelDir = Split-Path -Parent $ServerTestSentinelPath
    if (Test-Path -LiteralPath $ServerTestSentinelDir) {
        $ServerTestSentinelAlreadyExists = Test-Path -LiteralPath $ServerTestSentinelPath
        if ($ServerTestSentinelAlreadyExists) {
            Write-Host "[INFO] Server test sentinel already exists. Reusing: $ServerTestSentinelPath" -ForegroundColor DarkCyan
        }
        else {
            New-Item -ItemType File -Path $ServerTestSentinelPath -Force | Out-Null
            $CreatedServerTestSentinel = $true
            Write-Host "[INFO] Created server test sentinel file: $ServerTestSentinelPath" -ForegroundColor DarkCyan
        }
    }
    else {
        Write-Host "[WARN] Server test sentinel directory was not found. Continue without sentinel: $ServerTestSentinelDir" -ForegroundColor Yellow
    }

    & $StartScriptPath
    $StartExitCode = [int]$LASTEXITCODE
    if ($StartExitCode -ne 0) {
        Write-Host "[WARN] $StartScriptPath exited non-zero: start=$StartExitCode" -ForegroundColor Yellow
    }
    $ExitCode = $StartExitCode

    $ProgressPreference = 'SilentlyContinue' # Suppress progress from Test-NetConnection
    for ($TryCount = 1; $TryCount -le $MaxTry; $TryCount++) {
        # Test network connection and suppress warning/information logs
        $Result = Test-NetConnection -ComputerName $TargetIP -Port $TargetPort -WarningAction Ignore -InformationAction Ignore
        if ($Result.TcpTestSucceeded) {
            Write-Host "[INFO] Started server is responding on ${TargetIP}:${TargetPort}." -ForegroundColor Green
            break
        }
        if ($TryCount -lt $MaxTry) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    if (-not $Result.TcpTestSucceeded) {
        Write-Host "[ERROR] Failed to connect to the server at ${TargetIP}:${TargetPort}." -ForegroundColor Red
        $ExitCode = $ExitCode -bor 1
        return
    }

    if (-not $NoForeground) {
        Set-WindowForegroundBestEffort -ProcessName "Morrowind" | Out-Null
    }
    else {
        Write-Host "[INFO] Skipping foreground activation (-NoForeground)." -ForegroundColor DarkCyan
    }

    # TODO 成功を期待するテストのみなので、失敗を期待するテストも欲しい。無効な引数などで通信は成功するが、内容がエラーになることを確認する。
    # TODO luaからテストケースをある程度自動生成したい
    $TestCases = @(
        @("--method", "logging/setLevel", "--log-level", "trace"),
        @("--method", "tools/list"),
        @("--method", "resources/list"),
        @("--method", "prompts/list"),
        @("--method", "resources/templates/list"),
        @("--method", "tools/call", "--tool-name", "mw-menu-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-menu-action", "--tool-arg", "menu_name=Pete_ContinueButton", "--tool-arg", "action=mouseClick"), # using continue mod
        @("--method", "tools/list"), # expect in game.
        @("--method", "prompts/list"),
        @("--method", "tools/call", "--tool-name", "mw-activator-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-actor-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-player-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-static-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-target-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-world-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-player-action", "--tool-arg", "action=activate", "--tool-arg", "how=tap"),
        @("--method", "tools/call", "--tool-name", "mw-inventory-fetch"),
        @("--method", "tools/call", "--tool-name", "mw-screenshot-save", "--tool-arg", "file_name=$RunTimestamp"),
        @("--method", "tools/call", "--tool-name", "mw-menu-fetch"),
        @("--method", "resources/list"),
        @("--method", "resources/read", "--uri", "morrowind://memory/index.json"),
        @("--method", "resources/read", "--uri", "morrowind://memory/player/index.json"),
        @("--method", "resources/read", "--uri", "morrowind://memory/player/journal.json"),
        @("--method", "resources/read", "--uri", "morrowind://memory/player/quests.json"),
        @("--method", "resources/read", "--uri", "morrowind://memory/actors/index.json"),
        @("--method", "resources/read", "--uri", "morrowind://screenshot/$RunTimestamp.jpg"), # TODO listから取得したファイルを読む
        @("--method", "prompts/get", "--prompt-name", "mw-loar"),
        @("--method", "prompts/get", "--prompt-name", "mw-role"),
        @("--method", "prompts/get", "--prompt-name", "mw-todo"),
        @("--method", "prompts/get", "--prompt-name", "mw-loar"),
        @("--method", "prompts/get", "--prompt-name", "mw-translate"),
        @("--method", "prompts/get", "--prompt-name", "mw-walkthrough"),
        @("--method", "tools/call", "--tool-name", "mw-debug-action", "--tool-arg", "action=memory:SaveDebugDocuments")
    )

    $TestResult = 0
    foreach ($Test in $TestCases) {
        if (-not $NoForeground -and (Test-RequiresForegroundActivation -Arguments $Test)) {
            Set-WindowForegroundBestEffort -ProcessName "Morrowind" | Out-Null
        }
        $TestResult = $TestResult -bor (Invoke-MCPInspector $Test)
    }
    $TestResult = $TestResult -bor (Invoke-MemoryTraversalTest -EndpointUrl $Config.Connection.url)

    $ExitCode = $ExitCode -bor $TestResult

}
finally {
    Write-Host "[INFO] Stopping the server..." -ForegroundColor Cyan
    & $StopScriptPath
    if ([int]$LASTEXITCODE -ne 0) {
        Write-Host "[WARN] $StopScriptPath exit code: $LASTEXITCODE" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $MwseLogSourcePath) {
        try {
            Copy-Item -LiteralPath $MwseLogSourcePath -Destination $MwseLogCopyPath -Force
            Write-Host "[INFO] MWSE log copy: $(Convert-ToFileUri -Path $MwseLogCopyPath)" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[WARN] Failed to copy MWSE.log: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[WARN] MWSE.log not found: $MwseLogSourcePath" -ForegroundColor Yellow
    }

    Write-Host "[INFO] Inspector logs: $(Convert-ToFileUri -Path $InspectorLogPath)" -ForegroundColor Cyan

    if ($CreatedServerTestSentinel) {
        Remove-Item -LiteralPath $ServerTestSentinelPath -ErrorAction SilentlyContinue
    }

    Pop-Location
}

exit $ExitCode
