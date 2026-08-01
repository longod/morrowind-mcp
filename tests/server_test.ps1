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
        [pscustomobject]$Response
    )

    if ($Response.ExitCode -ne 0) {
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

function New-ServerTestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Arguments,
        [scriptblock]$When,
        [scriptblock]$Validate,
        [scriptblock]$Capture
    )

    return [pscustomobject]@{
        Name = $Name
        Arguments = $Arguments
        When = $When
        Validate = $Validate
        Capture = $Capture
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
        [scriptblock]$Capture
    )

    return New-ServerTestCase -Name $Name -Arguments (New-ToolCallArguments -ToolName $ToolName -ToolArguments $ToolArguments) -When $When -Validate $Validate -Capture $Capture
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
        Write-Host "[SKIPPED] $($TestCase.Name): unavailable in current server state." -ForegroundColor DarkCyan
        return 0
    }
    $arguments = if ($TestCase.Arguments -is [scriptblock]) { & $TestCase.Arguments $Context } else { $TestCase.Arguments }
    $response = Invoke-MCPInspector $arguments
    try {
        Assert-InspectorSuccess -Response $response
        if ($TestCase.Validate) {
            & $TestCase.Validate $response.Result $Context
        }
        if ($TestCase.Capture) {
            & $TestCase.Capture $response.Result $Context
        }
        Write-Host "[PASSED] $($TestCase.Name)" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[FAILED] $($TestCase.Name): $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
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
        (New-ServerTestCase -Name "initialize" -Arguments @("--method", "initialize") -Validate { param($result) if ([string]::IsNullOrWhiteSpace($result.protocolVersion) -or -not $result.serverInfo -or -not $result.capabilities) { throw "Initialize response is incomplete." } }),
        (New-ServerTestCase -Name "tools list" -Arguments @("--method", "tools/list") -Validate { param($result) $names = @($result.tools | ForEach-Object { $_.name }); foreach ($name in @("mw-menu-fetch", "mw-screenshot-save", "mw-debug-action")) { if ($names -notcontains $name) { throw "Missing tool: $name" } }; if (@($result.tools | Where-Object { $_.name -notmatch '^mw-' }).Count -gt 0) { throw "Tool name is missing the mw- prefix." } } -Capture { param($result, $context) $context.ToolNames = @($result.tools | ForEach-Object { $_.name }) }),
        (New-ServerTestCase -Name "resources list" -Arguments @("--method", "resources/list") -Validate { param($result) if (@($result.resources | Where-Object { $_.uri -eq "morrowind://memory/index.json" -and $_.mimeType -eq "application/json" }).Count -ne 1) { throw "Memory root resource is missing." } } -Capture { param($result, $context) $context.ResourceUris = @($result.resources | ForEach-Object { $_.uri }) }),
        (New-ServerTestCase -Name "prompts list" -Arguments @("--method", "prompts/list") -Validate { param($result) $names = @($result.prompts | ForEach-Object { $_.name }); foreach ($name in @("mw-loar", "mw-todo", "mw-translate", "mw-walkthrough")) { if ($names -notcontains $name) { throw "Missing prompt: $name" } } } -Capture { param($result, $context) $context.PromptNames = @($result.prompts | ForEach-Object { $_.name }) }),
        (New-ServerTestCase -Name "resource templates list" -Arguments @("--method", "resources/templates/list") -Validate { param($result) if ($null -eq $result.resourceTemplates) { throw "Missing resourceTemplates." } }),
        (New-ToolCallTestCase -Name "menu fetch" -ToolName "mw-menu-fetch" -Validate {
            param($result)
            Assert-ToolSuccess $result
            if ($null -eq $result.structuredContent) { throw "Missing structuredContent." }
        }),
        (New-ToolCallTestCase -Name "continue menu action" -ToolName "mw-menu-action" -ToolArguments @{
            menu_name = "Pete_ContinueButton"
            action = "mouseClick"
        } -When { param($context) $context.ToolNames -contains "mw-menu-action" } -Validate {
            param($result)
            Assert-ToolSuccess $result
        }),
        (New-ToolCallTestCase -Name "player fetch" -ToolName "mw-player-fetch" -When { param($context) $context.ToolNames -contains "mw-player-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "menu mode on" -ToolName "mw-player-action" -ToolArguments @{ action = "menuMode"; how = "tap" } -When { param($context) $context.ToolNames -contains "mw-player-action" } -Validate { param($result) Assert-ToolSuccess $result }),
        (New-ToolCallTestCase -Name "inventory fetch" -ToolName "mw-inventory-fetch" -When { param($context) $context.ToolNames -contains "mw-inventory-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "menu mode off" -ToolName "mw-player-action" -ToolArguments @{ action = "menuMode"; how = "tap" } -When { param($context) $context.ToolNames -contains "mw-player-action" } -Validate { param($result) Assert-ToolSuccess $result }),
        (New-ToolCallTestCase -Name "reference fetch" -ToolName "mw-reference-fetch" -When { param($context) $context.ToolNames -contains "mw-reference-fetch" } -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
        (New-ToolCallTestCase -Name "target fetch" -ToolName "mw-target-fetch" -Validate { param($result) Assert-ToolSuccess $result; if ($null -eq $result.structuredContent) { throw "Missing structuredContent." } }),
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
        (New-ServerTestCase -Name "resources list with screenshot" -Arguments @("--method", "resources/list") -When { param($context) -not [string]::IsNullOrWhiteSpace($context.ScreenshotUri) } -Validate { param($result, $context) if (@($result.resources | Where-Object { $_.uri -eq $context.ScreenshotUri -and $_.mimeType -eq $context.ScreenshotMimeType }).Count -ne 1) { throw "Generated screenshot resource is missing." } }),
        (New-ResourceReadTestCase -Name "memory root read" -Uri "morrowind://memory/index.json" -Validate { param($result) $content = @($result.contents | Where-Object { $_.uri -eq "morrowind://memory/index.json" } | Select-Object -First 1)[0]; if ($null -eq $content -or $content.mimeType -ne "application/json" -or [string]::IsNullOrWhiteSpace($content.text)) { throw "Memory root is not JSON text." }; $document = $content.text | ConvertFrom-Json -ErrorAction Stop; foreach ($field in @("schema_version", "type", "data_type", "title", "source", "data")) { if ($null -eq $document.PSObject.Properties[$field]) { throw "Memory root is missing $field." } } }),
        (New-ResourceReadTestCase -Name "memory player index read" -Uri "morrowind://memory/player/index.json" -When { param($context) $context.ResourceUris -contains "morrowind://memory/player/index.json" } -Validate { param($result) if (@($result.contents | Where-Object { $_.uri -eq "morrowind://memory/player/index.json" -and $_.mimeType -eq "application/json" -and $_.text }).Count -ne 1) { throw "Player memory index is not JSON text." } }),
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
        })
    )

    $TestResult = 0
    $TestContext = @{}
    foreach ($TestCase in $TestCases) {
        $TestResult = $TestResult -bor (Invoke-ServerTestCase -TestCase $TestCase -Context $TestContext)
    }

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
