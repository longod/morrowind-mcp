param(
    [switch]$NoForeground,
    [switch]$Unpretty
)

$MaxTry = 10
$IntervalSeconds = 3
$InspectorPackage = "@modelcontextprotocol/inspector"
$InspectorMinimumMajorVersion = 2
$InspectorConnectTimeoutMilliseconds = 15000

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
$InspectorVersion = "unknown"

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

function Invoke-ClientClickForMouseCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    if (-not ("MorrowindMcpUser32" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class MorrowindMcpUser32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
    }

    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if (-not $proc) {
        Write-Host "[WARN] Failed to find $ProcessName window for capture click." -ForegroundColor Yellow
        return $false
    }

    $clientRect = [MorrowindMcpUser32+RECT]::new()
    if (-not [MorrowindMcpUser32]::GetClientRect($proc.MainWindowHandle, [ref]$clientRect)) {
        Write-Host "[WARN] Failed to get $ProcessName client rectangle for capture click." -ForegroundColor Yellow
        return $false
    }

    $clientCenter = [MorrowindMcpUser32+POINT]::new()
    $clientCenter.X = [int](($clientRect.Right - $clientRect.Left) / 2)
    $clientCenter.Y = [int](($clientRect.Bottom - $clientRect.Top) / 2)
    if (-not [MorrowindMcpUser32]::ClientToScreen($proc.MainWindowHandle, [ref]$clientCenter)) {
        Write-Host "[WARN] Failed to resolve $ProcessName client coordinates for capture click." -ForegroundColor Yellow
        return $false
    }

    $originalCursor = [MorrowindMcpUser32+POINT]::new()
    $restoreCursor = [MorrowindMcpUser32]::GetCursorPos([ref]$originalCursor)
    if (-not [MorrowindMcpUser32]::SetCursorPos($clientCenter.X, $clientCenter.Y)) {
        Write-Host "[WARN] Failed to move cursor to $ProcessName client area for capture click." -ForegroundColor Yellow
        return $false
    }

    $leftDown = 0x0002
    $leftUp = 0x0004
    [MorrowindMcpUser32]::mouse_event($leftDown, 0, 0, 0, [UIntPtr]::Zero)
    [MorrowindMcpUser32]::mouse_event($leftUp, 0, 0, 0, [UIntPtr]::Zero)
    if ($restoreCursor) {
        [MorrowindMcpUser32]::SetCursorPos($originalCursor.X, $originalCursor.Y) | Out-Null
    }

    Write-Host "[INFO] Sent client click to $ProcessName to request mouse capture." -ForegroundColor Green
    return $true
}

try {
    $null = New-Item -Path $LogsRoot -ItemType Directory -Force
    $InspectorVersion = (& npm.cmd view $InspectorPackage version 2>&1 | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($InspectorVersion)) {
        $InspectorVersion = "unavailable"
    }
    if ($InspectorVersion -notmatch '^(\d+)\.\d+\.\d+') {
        throw "Unable to determine Inspector version: $InspectorVersion"
    }
    if ([int]$Matches[1] -lt $InspectorMinimumMajorVersion) {
        throw "Inspector version $InspectorVersion is unsupported; version $InspectorMinimumMajorVersion or later is required."
    }
    Write-Host "[INFO] Inspector: $InspectorPackage ($InspectorVersion)" -ForegroundColor Cyan
    Set-Content -Path $InspectorLogPath -Value @(
        "# Morrowind MCP server_test inspector log"
        "# StartedAt: $(Get-Date -Format o)"
        "# Endpoint: $($Config.Connection.url)"
        "# Inspector: $InspectorPackage ($InspectorVersion)"
        ""
    )
}
catch {
    Write-Host "[ERROR] Failed to initialize inspector log file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

function Invoke-MCPInspector {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $commandArguments = @(
        "--yes",
        $InspectorPackage,
        "--cli",
        $Config.Connection.url,
        "--transport",
        "http",
        "--connect-timeout",
        $InspectorConnectTimeoutMilliseconds,
        "--format",
        "json"
    )
    if ($Arguments) { $commandArguments += $Arguments }

    Write-Host "[RUN] $($Arguments -join ' ')" -ForegroundColor Cyan
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & npx.cmd @commandArguments 1> $stdoutFile 2> $stderrFile
        $result = [int]$LASTEXITCODE
        $runLabel = $Arguments -join ' '

        $stdoutText = if (Test-Path $stdoutFile) { Get-Content -Path $stdoutFile -Raw } else { "" }
        $stderrText = if (Test-Path $stderrFile) { Get-Content -Path $stderrFile -Raw } else { "" }

        $json = $null
        $parseError = $null
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            try {
                $json = $stdoutText | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $parseError = $_.Exception.Message
            }
        }

        $uvHandleClosingAssertionPattern = 'Assertion failed: !\(handle->flags & UV_HANDLE_CLOSING\)'
        $hasKnownUvHandleClosingAssertion = $stderrText -match $uvHandleClosingAssertionPattern
        $knownUvHandleClosingMessage = "[KNOWN] Inspector UV_HANDLE_CLOSING assertion; response JSON remains usable."
        $hasUnexpectedStderr = @(
            $stderrText -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch $uvHandleClosingAssertionPattern
            }
        ).Count -gt 0

        $logStdout = $stdoutText
        if ($json -and $json.result -and $json.result.contents) {
            $blobContent = @($json.result.contents | Where-Object { $_.blob } | Select-Object -First 1)
            if ($blobContent.Count -gt 0) {
                $logStdout = "<binary resource response omitted: uri=$($blobContent[0].uri) mimeType=$($blobContent[0].mimeType) blobLength=$($blobContent[0].blob.Length)>"
            }
        }
        if ($json -and -not $Unpretty -and $logStdout -eq $stdoutText) {
            $logStdout = $json | ConvertTo-Json -Depth 100
        }

        Add-Content -Path $InspectorLogPath -Value @(
            "================================================================================"
            "[RUN] $runLabel"
            "[TIME] $(Get-Date -Format o)"
            "[EXIT] $result"
            $(if ($hasKnownUvHandleClosingAssertion) { $knownUvHandleClosingMessage })
            "--- STDERR ---"
        )
        if ($hasKnownUvHandleClosingAssertion) {
            Write-Host $knownUvHandleClosingMessage -ForegroundColor Yellow
        }
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Add-Content -Path $InspectorLogPath -Value $stderrText
        }
        else {
            Add-Content -Path $InspectorLogPath -Value "<empty>"
        }

        Add-Content -Path $InspectorLogPath -Value @(
            "--- STDOUT ---"
        )
        if (-not [string]::IsNullOrWhiteSpace($logStdout)) {
            Add-Content -Path $InspectorLogPath -Value $logStdout
        }
        else {
            Add-Content -Path $InspectorLogPath -Value "<empty>"
        }
        Add-Content -Path $InspectorLogPath -Value ""

        if ($result -ne 0 -or $null -eq $json) {
            Write-Host "[FAILED] $result" -ForegroundColor Red
            if ($parseError) {
                Write-Host "  Invalid Inspector JSON: $parseError" -ForegroundColor DarkYellow
            }
            if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
                $preview = $stderrText -split "`r?`n" | Where-Object { $_ } | Select-Object -First 5
                foreach ($line in $preview) {
                    Write-Host "  $line" -ForegroundColor DarkYellow
                }
            }
        }

        return [pscustomobject]@{
            ExitCode = $result
            Result = if ($json) { $json.result } else { $null }
            Error = if ($json) { $json.error } else { $null }
            ParseError = $parseError
            HasKnownUvHandleClosingAssertion = $hasKnownUvHandleClosingAssertion
            HasUnexpectedStderr = $hasUnexpectedStderr
        }
    }
    finally {
        Remove-Item -Path $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item -Path $stderrFile -ErrorAction SilentlyContinue
    }
}

function Assert-InspectorSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Response,
        [bool]$AllowToolError = $false
    )

    $ignoreKnownUvHandleClosingAssertion = $Response.HasKnownUvHandleClosingAssertion -and
        $null -ne $Response.Result -and
        -not $Response.HasUnexpectedStderr
    if ($Response.ExitCode -ne 0 -and -not $AllowToolError -and -not $ignoreKnownUvHandleClosingAssertion) {
        throw "Inspector exited with code $($Response.ExitCode)."
    }
    if ($Response.ParseError) {
        throw "Inspector output was not JSON: $($Response.ParseError)"
    }
    if ($Response.Error) {
        throw "Inspector returned an error: $($Response.Error.message)"
    }
    if ($null -eq $Response.Result) {
        throw "Inspector JSON envelope is missing result."
    }
}

function Assert-ToolSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result
    )

    if ($Result.isError -eq $true) {
        throw "Tool returned isError=true."
    }
}

function Assert-ToolError {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result
    )

    if ($Result.isError -ne $true) {
        throw "Tool did not return isError=true."
    }
}

function Find-ActionableMenuPath {
    param(
        [Parameter(Mandatory = $true)][object]$Node,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Action
    )

    if ($Node.name -eq $Name -and @($Node.actionable) -contains $Action) {
        return $Node.path
    }
    foreach ($child in @($Node.children)) {
        if ($null -eq $child) {
            continue
        }
        $path = Find-ActionableMenuPath -Node $child -Name $Name -Action $Action
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            return $path
        }
    }
    return $null
}

function Measure-JsonPayloadSize {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $prettyJson = $Payload | ConvertTo-Json -Depth 100
    $unprettyJson = $Payload | ConvertTo-Json -Depth 100 -Compress
    return [pscustomobject]@{
        PrettyBytes = $encoding.GetByteCount($prettyJson)
        UnprettyBytes = $encoding.GetByteCount($unprettyJson)
    }
}

function Write-ReferenceDetailSizeComparison {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Sizes
    )

    foreach ($format in @(
        [pscustomobject]@{ Name = "pretty"; Property = "PrettyBytes" },
        [pscustomobject]@{ Name = "unpretty"; Property = "UnprettyBytes" }
    )) {
        $minimalBytes = [int]$Sizes.minimal.($format.Property)
        $standardBytes = [int]$Sizes.standard.($format.Property)
        $fullBytes = [int]$Sizes.full.($format.Property)
        Write-Host ("[INFO] Reference detail size ({0}, UTF-8 bytes): minimal={1} (1.00x), standard={2} ({3:N2}x), full={4} ({5:N2}x)" -f $format.Name, $minimalBytes, $standardBytes, ($standardBytes / $minimalBytes), $fullBytes, ($fullBytes / $minimalBytes)) -ForegroundColor Cyan
    }
}

function New-ServerTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Arguments,
        [scriptblock]$When,
        [scriptblock]$Validate,
        [scriptblock]$Capture,
        [scriptblock]$RetryUntil,
        [int]$RetryAttempts = 1,
        [int]$RetryIntervalSeconds = 0,
        [bool]$AllowToolError = $false
    )

    return [pscustomobject]@{
        Name = $Name
        Arguments = $Arguments
        When = $When
        Validate = $Validate
        Capture = $Capture
        RetryUntil = $RetryUntil
        RetryAttempts = $RetryAttempts
        RetryIntervalSeconds = $RetryIntervalSeconds
        AllowToolError = $AllowToolError
    }
}

function New-ToolCallArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        [hashtable]$ToolArguments
    )

    $arguments = @("--method", "tools/call", "--tool-name", $ToolName)
    if ($ToolArguments) {
        foreach ($entry in $ToolArguments.GetEnumerator()) {
            $arguments += "--tool-arg", ("{0}={1}" -f $entry.Key, $entry.Value)
        }
    }
    return $arguments
}

function New-ToolCallTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ToolName,
        [hashtable]$ToolArguments,
        [scriptblock]$When,
        [scriptblock]$Validate,
        [scriptblock]$Capture,
        [bool]$AllowToolError = $false
    )

    return New-ServerTestCase -Name $Name -Arguments (New-ToolCallArguments -ToolName $ToolName -ToolArguments $ToolArguments) -When $When -Validate $Validate -Capture $Capture -AllowToolError $AllowToolError
}

function New-PromptGetTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$PromptName,
        [scriptblock]$When,
        [scriptblock]$Validate,
        [scriptblock]$Capture
    )

    return New-ServerTestCase -Name $Name -Arguments @("--method", "prompts/get", "--prompt-name", $PromptName) -When $When -Validate $Validate -Capture $Capture
}

function New-ResourceReadTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Uri,
        [scriptblock]$When,
        [scriptblock]$Validate,
        [scriptblock]$Capture
    )

    if ($Uri -is [scriptblock]) {
        $uriFactory = $Uri
        $arguments = {
            param($context)
            @("--method", "resources/read", "--uri", (& $uriFactory $context))
        }.GetNewClosure()
    }
    else {
        $arguments = @("--method", "resources/read", "--uri", $Uri)
    }

    return New-ServerTestCase -Name $Name -Arguments $arguments -When $When -Validate $Validate -Capture $Capture
}

function Invoke-ServerTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$TestCase,
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    Write-Host "[CASE] $($TestCase.Name)" -ForegroundColor Cyan
    if ($TestCase.When -and -not (& $TestCase.When $Context)) {
        $message = "[SKIPPED] $($TestCase.Name): unavailable in current server state."
        Write-Host $message -ForegroundColor DarkYellow
        Add-Content -LiteralPath $InspectorLogPath -Value $message
        return 0
    }
    try {
        for ($attempt = 1; $attempt -le $TestCase.RetryAttempts; $attempt++) {
            $arguments = if ($TestCase.Arguments -is [scriptblock]) { & $TestCase.Arguments $Context } else { $TestCase.Arguments }
            $response = Invoke-MCPInspector $arguments
            Assert-InspectorSuccess -Response $response -AllowToolError $TestCase.AllowToolError
            if ($TestCase.Validate) {
                & $TestCase.Validate $response.Result $Context
            }
            if ($TestCase.Capture) {
                & $TestCase.Capture $response.Result $Context
            }
            if (-not $TestCase.RetryUntil -or (& $TestCase.RetryUntil $response.Result $Context)) {
                $message = "[PASSED] $($TestCase.Name)"
                Write-Host $message -ForegroundColor Green
                Add-Content -LiteralPath $InspectorLogPath -Value $message
                return 0
            }
            if ($attempt -lt $TestCase.RetryAttempts) {
                Write-Host "[WAIT] $($TestCase.Name): server state is still loading ($attempt/$($TestCase.RetryAttempts))." -ForegroundColor DarkCyan
                Start-Sleep -Seconds $TestCase.RetryIntervalSeconds
            }
        }
        throw "Server state did not become ready after $($TestCase.RetryAttempts) attempts."
    }
    catch {
        $message = "[FAILED] $($TestCase.Name): $($_.Exception.Message)"
        Write-Host $message -ForegroundColor Red
        Add-Content -LiteralPath $InspectorLogPath -Value $message
        return 1
    }
}

$TargetIP = $Config.Connection.host
$TargetPort = [int]$Config.Connection.port
$StartScriptPath = ".\start_server_mo2.ps1"
$StopScriptPath = ".\stop_server.ps1"

$ExitCode = 0
. (Join-Path $ScriptDir "mwmcp_test_context.ps1")

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

    Set-MwmcpTestContext -UnitTestMode "skip" -AcceptDisclaimer $true

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
        Invoke-ClientClickForMouseCapture -ProcessName "Morrowind" | Out-Null
    }
    else {
        Write-Host "[INFO] Skipping foreground activation (-NoForeground)." -ForegroundColor DarkCyan
    }

    # TODO 成功を期待するテストのみなので、失敗を期待するテストも欲しい。無効な引数などで通信は成功するが、内容がエラーになることを確認する。

    # what is this:
    # npm warn ERESOLVE overriding peer dependency
    # npm warn deprecated lodash.isequal@4.5.0: This package is deprecated. Use require('node:util').isDeepStrictEqual instead.
    # npm warn deprecated @modelcontextprotocol/server-legacy@2.0.0-beta.5: This package is a frozen copy of v1's SSE transport and OAuth Authorization Server helpers for migration purposes only. Use StreamableHTTP from @modelcontextprotocol/server and a dedicated OAuth server in production. Will not receive new features.

    # Add cases with New-ServerTestCase for a raw Inspector method, or
    # New-ToolCallTestCase for tools/call. Validate receives ($result, $context).
    $TestCases = @(
        (New-ServerTestCase -Name "initialize" -Arguments @("--method", "initialize") -Validate { param($result) if ([string]::IsNullOrWhiteSpace($result.protocolVersion) -or -not $result.serverInfo -or -not $result.capabilities) { throw "Initialize response is incomplete." }; if ($null -eq $result.capabilities.completions) { throw "Initialize does not advertise completions." } }),
        (New-ServerTestCase -Name "tools list" -Arguments @("--method", "tools/list") -Validate { param($result) $names = @($result.tools | ForEach-Object { $_.name }); foreach ($name in @("mw-capabilities-fetch", "mw-menu-fetch", "mw-player-fetch", "mw-player-look", "mw-screenshot-save", "mw-debug-action")) { if ($names -notcontains $name) { throw "Missing tool: $name" } }; if (@($result.tools | Where-Object { $_.name -notmatch '^mw-' }).Count -gt 0) { throw "Tool name is missing the mw- prefix." }; foreach ($name in @("mw-reference-fetch", "mw-target-fetch")) { $tool = @($result.tools | Where-Object { $_.name -eq $name } | Select-Object -First 1)[0]; if ($null -eq $tool.outputSchema.properties.serialization) { throw "$name does not publish serialization output metadata." } } } -Capture { param($result, $context) $context.ToolNames = @($result.tools | ForEach-Object { $_.name }) }),
        (New-ToolCallTestCase -Name "capabilities fetch" -ToolName "mw-capabilities-fetch" -Validate { param($result) Assert-ToolSuccess $result; $reference = @($result.structuredContent.tools | Where-Object { $_.name -eq "mw-reference-fetch" }); if ($reference.Count -ne 1 -or [string]::IsNullOrWhiteSpace($reference[0].conditions)) { throw "Reference fetch conditions are missing." } }),
        (New-ServerTestCase -Name "resources list" -Arguments @("--method", "resources/list") -Validate { param($result) if (@($result.resources | Where-Object { $_.uri -eq "morrowind://memory/index.json" -and $_.mimeType -eq "application/json" }).Count -ne 1) { throw "Memory root resource is missing." } } -Capture { param($result, $context) $context.ResourceUris = @($result.resources | ForEach-Object { $_.uri }) }),
        (New-ServerTestCase -Name "prompts list" -Arguments @("--method", "prompts/list") -Validate { param($result) $names = @($result.prompts | ForEach-Object { $_.name }); foreach ($name in @("mw-loar", "mw-todo", "mw-translate", "mw-walkthrough")) { if ($names -notcontains $name) { throw "Missing prompt: $name" } } } -Capture { param($result, $context) $context.PromptNames = @($result.prompts | ForEach-Object { $_.name }) }),
        (New-ServerTestCase -Name "resource templates list" -Arguments @("--method", "resources/templates/list") -Validate { param($result) $templates = @($result.resourceTemplates); if ($templates.Count -ne 2) { throw "Expected two resource templates, got $($templates.Count)." }; $memory = @($templates | Where-Object { $_.uriTemplate -eq "morrowind://memory/{collection}/{entity_id}/{document}.json" }); $screenshot = @($templates | Where-Object { $_.uriTemplate -eq "morrowind://screenshot/{file}" }); if ($memory.Count -ne 1 -or $memory[0].name -ne "memory-entity" -or $memory[0].title -ne "Memory Entity" -or $memory[0].mimeType -ne "application/json" -or @($memory[0].annotations.audience).Count -ne 1 -or $memory[0].annotations.audience[0] -ne "assistant") { throw "Memory entity template is missing or invalid." }; if ($screenshot.Count -ne 1 -or $screenshot[0].name -ne "screenshot" -or $screenshot[0].title -ne "Screenshot" -or @($screenshot[0].annotations.audience).Count -ne 1 -or $screenshot[0].annotations.audience[0] -ne "assistant") { throw "Screenshot template is missing or invalid." } }),
        (New-ToolCallTestCase -Name "menu fetch" -ToolName "mw-menu-fetch" -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($null -eq $result.structuredContent) { throw "Missing structuredContent." }
        } -Capture {
            param($result, $context)
            $context.MainMenuContinuePath = Find-ActionableMenuPath -Node $result.structuredContent.menu -Name "Pete_ContinueButton" -Action "mouseClick"
        }),
        (New-ToolCallTestCase -Name "reject non-actionable menu path" -ToolName "mw-menu-action" -ToolArguments @{
            menu_path = "/children/0"
            action = "mouseClick"
        } -When { param($context) $context.ToolNames -contains "mw-menu-action" } -AllowToolError $true -Validate {
            param($result)
            Assert-ToolError $result
            $text = @($result.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1)[0].text
            if ($text -notmatch "does not support action mouseClick") { throw "Non-actionable path did not report an action mismatch." }
        }),
        (New-ServerTestCase -Name "continue menu action" -Arguments {
            param($context)
            if ([string]::IsNullOrWhiteSpace($context.MainMenuContinuePath)) {
                throw "Pete_ContinueButton was not found as an actionable main-menu element."
            }
            New-ToolCallArguments -ToolName "mw-menu-action" -ToolArguments @{
                menu_path = $context.MainMenuContinuePath
                action = "mouseClick"
            }
        } -When { param($context) $context.ToolNames -contains "mw-menu-action" } -Validate {
            param($result)
            Assert-ToolSuccess $result
        }),
        (New-ServerTestCase -Name "tools list after continue" -Arguments @("--method", "tools/list") -Validate { param($result) if ($null -eq $result.tools) { throw "Missing tools." } } -Capture { param($result, $context) $context.ToolNames = @($result.tools | ForEach-Object { $_.name }) } -RetryUntil { param($result, $context) $context.ToolNames -contains "mw-player-fetch" } -RetryAttempts $MaxTry -RetryIntervalSeconds $IntervalSeconds),
        (New-ServerTestCase -Name "prompts list after continue" -Arguments @("--method", "prompts/list") -Validate { param($result) if ($null -eq $result.prompts) { throw "Missing prompts." } } -Capture { param($result, $context) $context.PromptNames = @($result.prompts | ForEach-Object { $_.name }) }),
        (New-ToolCallTestCase -Name "player fetch" -ToolName "mw-player-fetch" -When { param($context) $context.ToolNames -contains "mw-player-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." }; if ($null -eq $result.structuredContent.player.position -or [string]::IsNullOrWhiteSpace($result.structuredContent.player.cell.id) -or $null -eq $result.structuredContent.mobilePlayer) { throw "Player reference or mobile state is missing." } } -Capture { param($result, $context) $context.PlayerNavigationPosition = $result.structuredContent.player.position; $context.PlayerNavigationCellId = $result.structuredContent.player.cell.id }),
        (New-ServerTestCase -Name "player navigate reachable location" -Arguments {
            param($context)
            New-ToolCallArguments -ToolName "mw-player-navigate" -ToolArguments @{
                action = "navigate"
                position_x = 456
                position_y = 484
                position_z = -256
                cell_id = $context.PlayerNavigationCellId
            }
        } -When { param($context) $context.ToolNames -contains "mw-player-navigate" -and -not [string]::IsNullOrWhiteSpace($context.PlayerNavigationCellId) } -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($result.structuredContent.route_node_count -lt 2) { throw "Navigation route did not contain multiple pathgrid nodes." }
            $text = @($result.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1)[0].text
            if ($text -ne "Player navigation started.") { throw "Navigation did not report a successful start." }
        }),
        (New-ToolCallTestCase -Name "player look cancels active navigation" -ToolName "mw-player-look" -ToolArguments @{ mode = "angles"; yaw = 90; pitch = 0 } -When { param($context) $context.ToolNames -contains "mw-player-look" } -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($result.structuredContent.navigation_cancelled -ne $true) { throw "Player look did not cancel active navigation." }
            if ($result.structuredContent.yaw -ne 90 -or $result.structuredContent.pitch -ne 0) { throw "Player look did not apply the requested absolute angles." }
            $text = @($result.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1)[0].text
            if ($text -ne "Player view updated.") { throw "Player look did not report success." }
        }),
        (New-ToolCallTestCase -Name "menu mode on" -ToolName "mw-player-action" -ToolArguments @{ action = "menuMode"; how = "tap" } -When { param($context) $context.ToolNames -contains "mw-player-action" } -Validate { param($result) Assert-ToolSuccess $result }),
        (New-ToolCallTestCase -Name "inventory fetch" -ToolName "mw-inventory-fetch" -When { param($context) $context.ToolNames -contains "mw-inventory-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "menu fetch in game" -ToolName "mw-menu-fetch" -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "menu mode off" -ToolName "mw-player-action" -ToolArguments @{ action = "menuMode"; how = "tap" } -When { param($context) $context.ToolNames -contains "mw-player-action" } -Validate { param($result) Assert-ToolSuccess $result }),
        (New-ToolCallTestCase -Name "reference fetch" -ToolName "mw-reference-fetch" -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." }; if ($result.structuredContent.serialization.detailLevel -ne "minimal") { throw "Reference list did not default to minimal detail." }; if (@($result.structuredContent.activators | Where-Object { $_.type -eq "leveledCreature" }).Count -ne 0) { throw "Reference fetch included a leveled creature activator." } } -Capture { param($result, $context) $activators = @($result.structuredContent.activators | Select-Object -First 1)[0]; if ($activators -and -not [string]::IsNullOrWhiteSpace($activators.id)) { $context.PlayerLookTargetId = $activators.id }; $context.NearbyReferenceCounts = @{ activators = @($result.structuredContent.activators).Count; actors = @($result.structuredContent.actors).Count; statics = @($result.structuredContent.statics).Count } }),
        (New-ToolCallTestCase -Name "reference fetch active cell scope" -ToolName "mw-reference-fetch" -ToolArguments @{ scope = "active" } -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result, $context) Assert-ToolSuccess $result; if ($result.structuredContent.serialization.detailLevel -ne "minimal") { throw "Reference fetch active scope did not retain minimal detail." }; foreach ($category in @("activators", "actors", "statics")) { if (@($result.structuredContent.$category).Count -lt $context.NearbyReferenceCounts[$category]) { throw "Reference fetch active scope omitted nearby $category." } } }),
        (New-ToolCallTestCase -Name "reference fetch all cells minimal detail" -ToolName "mw-reference-fetch" -ToolArguments @{ detail_level = "minimal" } -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($result.structuredContent.serialization.detailLevel -ne "minimal") { throw "Reference fetch did not honor minimal detail." } } -Capture { param($result, $context) $context.ReferenceDetailSizes.minimal = Measure-JsonPayloadSize -Payload $result.structuredContent }),
        (New-ToolCallTestCase -Name "reference fetch all cells standard detail" -ToolName "mw-reference-fetch" -ToolArguments @{ detail_level = "standard" } -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($result.structuredContent.serialization.detailLevel -ne "standard") { throw "Reference fetch did not honor standard detail." } } -Capture { param($result, $context) $context.ReferenceDetailSizes.standard = Measure-JsonPayloadSize -Payload $result.structuredContent }),
        (New-ToolCallTestCase -Name "reference fetch all cells full detail" -ToolName "mw-reference-fetch" -ToolArguments @{ detail_level = "full" } -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($result.structuredContent.serialization.detailLevel -ne "full") { throw "Reference fetch did not honor full detail." }; $references = @($result.structuredContent.activators) + @($result.structuredContent.actors) + @($result.structuredContent.statics); $locked = @($references | Where-Object { $null -ne $_.lockNode -and $_.lockNode.locked -eq $true }); if ($locked.Count -eq 0) { throw "Full reference fetch did not include a locked reference with lockNode." } } -Capture {
            param($result, $context)
            $context.ReferenceDetailSizes.full = Measure-JsonPayloadSize -Payload $result.structuredContent
            Write-ReferenceDetailSizeComparison -Sizes $context.ReferenceDetailSizes
        }),
        (New-ServerTestCase -Name "player look target active reference" -Arguments {
            param($context)
            New-ToolCallArguments -ToolName "mw-player-look" -ToolArguments @{ mode = "target"; target_id = $context.PlayerLookTargetId }
        } -When { param($context) $context.ToolNames -contains "mw-player-look" -and -not [string]::IsNullOrWhiteSpace($context.PlayerLookTargetId) } -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($result.structuredContent.navigation_cancelled -ne $false) { throw "Player look unexpectedly cancelled navigation." }
            if ([string]::IsNullOrWhiteSpace($result.structuredContent.target_point_kind)) { throw "Player look target mode did not report a target point kind." }
        }),
        (New-ToolCallTestCase -Name "target fetch" -ToolName "mw-target-fetch" -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." }; if ($result.structuredContent.serialization.detailLevel -ne "standard") { throw "Target fetch did not default to standard detail." } }),
        (New-ToolCallTestCase -Name "world fetch" -ToolName "mw-world-fetch" -When { param($context) $context.ToolNames -contains "mw-world-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "activate action" -ToolName "mw-player-action" -ToolArguments @{ action = "activate"; how = "tap" } -When { param($context) $context.ToolNames -contains "mw-player-action" } -Validate { param($result) Assert-ToolSuccess $result }),
        (New-ToolCallTestCase -Name "screenshot save" -ToolName "mw-screenshot-save" -ToolArguments @{ file_name = $RunTimestamp } -When {
            param($context)
            $context.ToolNames -contains "mw-screenshot-save"
        } -Validate {
            param($result)
            Assert-ToolSuccess $result
            if (@($result.content | Where-Object { $_.type -eq "resource_link" }).Count -ne 1) {
                throw "Screenshot result is missing a resource link."
            }
        } -Capture {
            param($result, $context)
            $link = @($result.content | Where-Object { $_.type -eq "resource_link" } | Select-Object -First 1)[0]
            $context.ScreenshotUri = $link.uri
            $context.ScreenshotMimeType = $link.mimeType
        }),
        (New-ServerTestCase -Name "resources list with screenshot" -Arguments @("--method", "resources/list") -When { param($context) -not [string]::IsNullOrWhiteSpace($context.ScreenshotUri) } -Validate { param($result, $context) if (@($result.resources | Where-Object { $_.uri -eq $context.ScreenshotUri -and $_.mimeType -eq $context.ScreenshotMimeType }).Count -ne 1) { throw "Generated screenshot resource is missing." } } -Capture { param($result, $context) $context.ResourceUris = @($result.resources | ForEach-Object { $_.uri }) }),
        (New-ResourceReadTestCase -Name "memory root read" -Uri "morrowind://memory/index.json" -Validate { param($result) $content = @($result.contents | Where-Object { $_.uri -eq "morrowind://memory/index.json" } | Select-Object -First 1)[0]; if ($null -eq $content -or $content.mimeType -ne "application/json" -or [string]::IsNullOrWhiteSpace($content.text)) { throw "Memory root is not JSON text." }; $document = $content.text | ConvertFrom-Json -ErrorAction Stop; foreach ($field in @("schema_version", "type", "data_type", "title", "source", "data")) { if ($null -eq $document.PSObject.Properties[$field]) { throw "Memory root is missing $field." } } }),
        (New-ResourceReadTestCase -Name "memory player index read" -Uri "morrowind://memory/player/index.json" -When { param($context) $context.ResourceUris -contains "morrowind://memory/player/index.json" } -Validate { param($result) $content = @($result.contents | Where-Object { $_.uri -eq "morrowind://memory/player/index.json" -and $_.mimeType -eq "application/json" -and $_.text } | Select-Object -First 1)[0]; if ($null -eq $content) { throw "Player memory index is not JSON text." }; $document = $content.text | ConvertFrom-Json -ErrorAction Stop; if (@($document.links | Where-Object { $_.rel -eq "equipment" -and $_.uri -eq "morrowind://memory/player/equipment.json" }).Count -ne 1) { throw "Player memory index is missing the equipment link." } }),
        (New-ResourceReadTestCase -Name "memory player equipment read" -Uri "morrowind://memory/player/equipment.json" -When { param($context) $context.ResourceUris -contains "morrowind://memory/player/equipment.json" } -Validate { param($result) $content = @($result.contents | Where-Object { $_.uri -eq "morrowind://memory/player/equipment.json" -and $_.mimeType -eq "application/json" -and $_.text } | Select-Object -First 1)[0]; if ($null -eq $content) { throw "Player equipment memory is not JSON text." }; $document = $content.text | ConvertFrom-Json -ErrorAction Stop; if ($document.type -ne "memory.collection" -or $document.data_type -ne "equipment_items") { throw "Player equipment memory has an invalid document type." }; if ($document.subject.id -ne "player") { throw "Player equipment memory is missing the player subject." }; foreach ($field in @("available", "item_count", "items")) { if ($null -eq $document.data.PSObject.Properties[$field]) { throw "Player equipment memory is missing data.$field." } }; if ($document.data.item_count -ne @($document.data.items).Count) { throw "Player equipment item_count does not match items." } }),
        (New-ResourceReadTestCase -Name "memory actor index read" -Uri "morrowind://memory/actors/index.json" -When { param($context) $context.ResourceUris -contains "morrowind://memory/actors/index.json" } -Validate { param($result) if (@($result.contents | Where-Object { $_.uri -eq "morrowind://memory/actors/index.json" -and $_.mimeType -eq "application/json" -and $_.text }).Count -ne 1) { throw "Actor memory index is not JSON text." } }),
        (New-ResourceReadTestCase -Name "screenshot resource read" -Uri { param($context) $context.ScreenshotUri } -When { param($context) -not [string]::IsNullOrWhiteSpace($context.ScreenshotUri) } -Validate { param($result, $context) $content = @($result.contents | Where-Object { $_.uri -eq $context.ScreenshotUri } | Select-Object -First 1)[0]; if ($null -eq $content -or $content.mimeType -ne $context.ScreenshotMimeType -or [string]::IsNullOrWhiteSpace($content.blob) -or $content.blob.Length -lt 4) { throw "Screenshot blob is missing or invalid." }; if ($content.mimeType -eq "image/jpeg" -and -not $content.blob.StartsWith("/9j/")) { throw "Screenshot is not a JPEG blob." } }),
        (New-PromptGetTestCase -Name "prompt loar" -PromptName "mw-loar" -Validate { param($result) if (@($result.messages | Where-Object { $_.content.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($_.content.text) }).Count -eq 0) { throw "Prompt returned no text message." } }),
        (New-PromptGetTestCase -Name "prompt role" -PromptName "mw-role" -When { param($context) $context.PromptNames -contains "mw-role" } -Validate { param($result) if (@($result.messages).Count -eq 0) { throw "Prompt returned no messages." } }),
        (New-PromptGetTestCase -Name "prompt todo" -PromptName "mw-todo" -Validate { param($result) if (@($result.messages).Count -eq 0) { throw "Prompt returned no messages." } }),
        (New-PromptGetTestCase -Name "prompt translate" -PromptName "mw-translate" -Validate { param($result) if (@($result.messages).Count -eq 0) { throw "Prompt returned no messages." } }),
        (New-PromptGetTestCase -Name "prompt walkthrough" -PromptName "mw-walkthrough" -Validate { param($result) if (@($result.messages).Count -eq 0) { throw "Prompt returned no messages." } }),
        (New-ToolCallTestCase -Name "memory debug dump" -ToolName "mw-debug-action" -ToolArguments @{ action = "memory:SaveDebugDocuments" } -When {
            param($context)
            $context.ToolNames -contains "mw-debug-action"
        } -Validate {
            param($result)
            Assert-ToolSuccess $result
        }),
        (New-ToolCallTestCase -Name "memory active-cell debug scan" -ToolName "mw-debug-action" -ToolArguments @{ action = "memory:ObserveActiveCells" } -When {
            param($context)
            $context.ToolNames -contains "mw-debug-action"
        } -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($null -eq $result.structuredContent.PSObject.Properties["observations"]) {
                throw "Active-cell debug scan is missing structuredContent.observations."
            }
            $observation = @($result.structuredContent.observations | Where-Object { $_.resource -eq "morrowind://memory/actors/index.json" } | Select-Object -First 1)[0]
            if ($null -eq $observation) {
                throw "Active-cell debug scan is missing the actor observation."
            }
            foreach ($field in @("cell_count", "scanned_actor_count", "changed_actor_count", "actor_count")) {
                if ($null -eq $observation.PSObject.Properties[$field]) {
                    throw "Active-cell debug scan is missing structuredContent.$field."
                }
            }
            if ($observation.cell_count -isnot [ValueType] -or $observation.scanned_actor_count -isnot [ValueType] -or $observation.cell_count -lt 0 -or $observation.scanned_actor_count -lt 0) {
                throw "Active-cell debug scan counts must be integers."
            }
            if ($observation.changed_actor_count -gt $observation.scanned_actor_count) {
                throw "Active-cell debug scan changed count exceeds scanned count."
            }
            if ($observation.actor_count -lt $observation.changed_actor_count) {
                throw "Active-cell debug scan actor count is less than changed count."
            }
            if ($null -eq $observation.PSObject.Properties["reason"] -or $observation.reason -ne "scanned") {
                throw "Active-cell debug scan did not report a completed scan."
            }
        })
    )

    $TestResult = 0
    $TestContext = @{
        ReferenceDetailSizes = @{}
    }
    foreach ($TestCase in $TestCases) {
        $TestResult = $TestResult -bor (Invoke-ServerTestCase -TestCase $TestCase -Context $TestContext)
    }

    $ExitCode = $ExitCode -bor $TestResult

}
finally {
    Remove-MwmcpTestContext

    Write-Host "[INFO] Stopping the server..." -ForegroundColor Cyan
    # Keep runner finalization isolated from the stop script.
    & powershell.exe -NoProfile -File $StopScriptPath
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

    Invoke-MwmcpTestRunSummary -TestType "server_test" -RunTimestamp $RunTimestamp

    Pop-Location
}

exit $ExitCode
