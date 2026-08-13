param(
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 60,
    [ValidateRange(1, 30)]
    [int]$PollIntervalSeconds = 1,
    [ValidateRange(1, 300)]
    [int]$ServerReadyTimeoutSeconds = 60,
    [switch]$UseRunningServer,
    [switch]$NoForeground
)

$InspectorPackage = "@modelcontextprotocol/inspector"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_config.ps1")
. (Join-Path $ScriptDir "mwmcp_test_context.ps1")

try {
    $Config = Get-MwmcpConfig
}
catch {
    Write-Host "[ERROR] Failed to resolve configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$LogsRoot = Join-Path $ScriptDir "logs\terrain_benchmark"
$RunTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$InspectorLogPath = Join-Path $LogsRoot "inspector_$RunTimestamp.log"
$ResultPath = Join-Path $LogsRoot "result_$RunTimestamp.json"
$MwseLogSourcePath = Join-Path $Config.Paths.morrowindInstallDir "MWSE.log"
$MwseLogCopyPath = Join-Path $LogsRoot "mwse_$RunTimestamp.log"
$StartScriptPath = Join-Path $ScriptDir "start_server_mo2.ps1"
$StopScriptPath = Join-Path $ScriptDir "stop_server.ps1"
$StartedServer = $false

function Test-ServerReachable {
    $connection = Test-NetConnection -ComputerName $Config.Connection.host -Port $Config.Connection.port -WarningAction Ignore -InformationAction Ignore
    return $connection.TcpTestSucceeded
}

function Test-MorrowindRunning {
    return $null -ne (Get-Process -Name "Morrowind" -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Set-WindowForegroundBestEffort {
    param([Parameter(Mandatory = $true)][string]$ProcessName)

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 } |
            Select-Object -First 1
        if ($process) {
            $activated = (New-Object -ComObject WScript.Shell).AppActivate($process.Id)
            if ($activated) {
                Write-Host "[INFO] Activated $ProcessName window in foreground." -ForegroundColor Green
                return $true
            }
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "[WARN] Failed to activate $ProcessName window in foreground." -ForegroundColor Yellow
    return $false
}

function Invoke-MCPInspector {
    param(
        [Parameter(Mandatory = $true)]
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
        "15000",
        "--format",
        "json"
    ) + $Arguments
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        & npx.cmd @commandArguments 1> $stdoutFile 2> $stderrFile
        $exitCode = [int]$LASTEXITCODE
        $stdout = if (Test-Path $stdoutFile) { Get-Content -LiteralPath $stdoutFile -Raw } else { "" }
        $stderr = if (Test-Path $stderrFile) { Get-Content -LiteralPath $stderrFile -Raw } else { "" }
        Add-Content -LiteralPath $InspectorLogPath -Value @(
            "================================================================================"
            "[RUN] $($Arguments -join ' ')"
            "[TIME] $(Get-Date -Format o)"
            "[EXIT] $exitCode"
            "--- STDERR ---"
            $(if ($stderr) { $stderr } else { "<empty>" })
            "--- STDOUT ---"
            $(if ($stdout) { $stdout } else { "<empty>" })
            ""
        )
        if ($exitCode -ne 0) {
            throw "Inspector exited with code ${exitCode}: $stderr"
        }
        return $stdout | ConvertFrom-Json -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    }
}

function Invoke-DebugAction {
    param([Parameter(Mandatory = $true)][string]$Action)

    $response = Invoke-MCPInspector -Arguments @(
        "--method", "tools/call", "--tool-name", "mw-debug-action", "--tool-arg", "action=$Action"
    )
    if ($response.error) {
        throw "Inspector returned an error: $($response.error.message)"
    }
    if ($null -eq $response.result -or $response.result.isError -eq $true) {
        throw "Debug action failed: $Action"
    }
    return $response.result.structuredContent
}

function Invoke-ToolAction {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [Parameter(Mandatory = $true)][hashtable]$Arguments
    )

    $toolArguments = @("--method", "tools/call", "--tool-name", $ToolName)
    foreach ($entry in $Arguments.GetEnumerator()) {
        $toolArguments += "--tool-arg", ("{0}={1}" -f $entry.Key, $entry.Value)
    }
    $response = Invoke-MCPInspector -Arguments $toolArguments
    if ($response.error -or $null -eq $response.result -or $response.result.isError -eq $true) {
        throw "Tool action failed: $ToolName"
    }
    return $response.result
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

function Invoke-MainMenuContinue {
    $tools = Invoke-MCPInspector -Arguments @("--method", "tools/list")
    if (@($tools.result.tools | Where-Object { $_.name -eq "mw-menu-action" }).Count -ne 1) {
        throw "mw-menu-action is not published while the main menu is active."
    }
    $menu = Invoke-ToolAction -ToolName "mw-menu-fetch" -Arguments @{}
    $path = Find-ActionableMenuPath -Node $menu.structuredContent.menu -Name "Pete_ContinueButton" -Action "mouseClick"
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Pete_ContinueButton was not found as an actionable main-menu element."
    }
    Invoke-ToolAction -ToolName "mw-menu-action" -Arguments @{ menu_path = $path; action = "mouseClick" } | Out-Null
    Write-Host "[INFO] Requested Continue from the Morrowind main menu." -ForegroundColor Green
}

function Wait-ForExteriorCell {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $probe = Invoke-DebugAction -Action "terrain:ProbeRuntimeAccess"
        if ($probe.is_exterior) {
            return $probe
        }
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ((Get-Date) -lt $deadline)
    throw "Terrain benchmarks require an active exterior cell. Move the player outdoors and run this script again."
}

try {
    $null = New-Item -Path $LogsRoot -ItemType Directory -Force
    Set-Content -LiteralPath $InspectorLogPath -Value @(
        "# Morrowind MCP terrain benchmark inspector log"
        "# StartedAt: $(Get-Date -Format o)"
        "# Endpoint: $($Config.Connection.url)"
        ""
    )

    if ($UseRunningServer) {
        if (-not (Test-ServerReachable)) {
            throw "No running server is reachable at $($Config.Connection.url)."
        }
        Write-Host "[INFO] Using the running server without starting, continuing, or stopping the game." -ForegroundColor DarkCyan
    }
    else {
        if (Test-ServerReachable) {
            throw "A server is already reachable at $($Config.Connection.url). Use -UseRunningServer to preserve it."
        }
        if (Test-MorrowindRunning) {
            throw "Morrowind is already running without a reachable server. Stop it or use -UseRunningServer after the server is available."
        }
        & $StartScriptPath -WaitForServer -ServerReadyTimeoutSeconds $ServerReadyTimeoutSeconds
        if (-not (Test-ServerReachable)) {
            throw "Server did not become reachable at $($Config.Connection.url)."
        }
        $StartedServer = $true
        if (-not $NoForeground) {
            Set-WindowForegroundBestEffort -ProcessName "Morrowind" | Out-Null
        }
        Invoke-MainMenuContinue
    }

    $tools = Invoke-MCPInspector -Arguments @("--method", "tools/list")
    if (@($tools.result.tools | Where-Object { $_.name -eq "mw-debug-action" }).Count -ne 1) {
        throw "mw-debug-action is not published by the connected server."
    }

    $probe = Wait-ForExteriorCell

    $started = Invoke-DebugAction -Action "terrain:StartQualityComparison"
    if ($started.state -ne "building") {
        throw "Terrain quality comparison did not start: $($started.state)"
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds $PollIntervalSeconds
        $status = Invoke-DebugAction -Action "terrain:GetQualityStatus"
        if ($status.state -eq "failed") {
            throw "Terrain quality comparison failed: $($status.error)"
        }
    } while ($status.state -ne "ready" -and (Get-Date) -lt $deadline)

    if ($status.state -ne "ready") {
        throw "Terrain quality comparison did not finish within $TimeoutSeconds seconds."
    }
    foreach ($resolution in @("64", "128", "256")) {
        $entry = $status.results.PSObject.Properties[$resolution].Value
        if ($null -eq $entry -or $entry.samples -lt 1 -or $null -eq $entry.height) {
            throw "Missing terrain quality result for resolution $resolution."
        }
    }
    $status | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    Write-Host "[PASSED] Terrain benchmark completed for cell $($status.cell_id)." -ForegroundColor Green
    Write-Host "[INFO] Result: $ResultPath" -ForegroundColor Cyan
    exit 0
}
catch {
    Write-Host "[FAILED] Terrain benchmark: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($StartedServer) {
        Write-Host "[INFO] Stopping the server started by this benchmark..." -ForegroundColor Cyan
        & $StopScriptPath
        if ([int]$LASTEXITCODE -ne 0) {
            Write-Host "[WARN] $StopScriptPath exit code: $LASTEXITCODE" -ForegroundColor Yellow
        }
    }
    if (Test-Path -LiteralPath $MwseLogSourcePath) {
        Copy-Item -LiteralPath $MwseLogSourcePath -Destination $MwseLogCopyPath -Force
        Write-Host "[INFO] MWSE log copy: $MwseLogCopyPath" -ForegroundColor Cyan
    }
    Write-Host "[INFO] Inspector log: $InspectorLogPath" -ForegroundColor Cyan
    Invoke-MwmcpTestRunSummary -TestType "terrain_benchmark" -RunTimestamp $RunTimestamp
}
