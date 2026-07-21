param(
    [Parameter(Position = 0)]
    [string[]]$TestTargets,
    [switch]$NoForeground
)

$MaxWaitSeconds = 10

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$ExitCode = 0
$CreatedSentinel = $false
$SentinelOriginalContent = $null
$RunTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputDir = Join-Path $ScriptDir "logs\unit_test"
$ExtractOutputPath = Join-Path $OutputDir "unitwind_$RunTimestamp.log"
$MwseCopyOutputPath = Join-Path $OutputDir "mwse_$RunTimestamp.log"
$ExtractPattern = '\[UnitWind\]|MORROWIND-MCP\..*(PASSED|FAILED)'
$ExtractedLines = @()
$FoundFailed = $false
$MwseLogPath = $null
$MwseLogStatus = ""
$SavedMwseCopy = $false

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

Push-Location $ScriptDir
try {
    $StartScriptPath = ".\start_server_mo2.ps1"
    $StopScriptPath = ".\stop_server.ps1"
    # Sentinel file lists target test files. Empty content means run the full suite.
    $SentinelPath = ".\..\MWSE\mods\morrowind-mcp\.unit-test-targets"
    $TargetLines = @($TestTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    # start script is mandatory; stop script is optional fallback on timeout.
    if (-not (Test-Path -LiteralPath $StartScriptPath)) {
        Write-Host "[ERROR] $StartScriptPath was not found." -ForegroundColor Red
        exit 1
    }
    $HasStopScript = Test-Path -LiteralPath $StopScriptPath
    if (-not $HasStopScript) {
        Write-Host "[WARN] $StopScriptPath was not found. Forced stop will be skipped." -ForegroundColor Yellow
    }

    $SentinelDir = Split-Path -Parent $SentinelPath
    if (Test-Path -LiteralPath $SentinelDir) {
        $SentinelAlreadyExists = Test-Path -LiteralPath $SentinelPath
        if ($SentinelAlreadyExists) {
            $SentinelOriginalContent = Get-Content -LiteralPath $SentinelPath -Raw
            Write-Host "[INFO] Sentinel file already exists. Reusing: $SentinelPath" -ForegroundColor DarkCyan
        }
        else {
            New-Item -ItemType File -Path $SentinelPath -Force | Out-Null
            $CreatedSentinel = $true
            Write-Host "[INFO] Created sentinel file: $SentinelPath" -ForegroundColor DarkCyan
        }

        if ($TargetLines.Count -gt 0) {
            Set-Content -LiteralPath $SentinelPath -Value $TargetLines -Encoding UTF8
            Write-Host "[INFO] Wrote $($TargetLines.Count) target(s) to sentinel file." -ForegroundColor DarkCyan
        }
        else {
            Clear-Content -LiteralPath $SentinelPath -ErrorAction SilentlyContinue
            Write-Host "[INFO] Cleared sentinel file for full test run." -ForegroundColor DarkCyan
        }

        if ($TargetLines.Count -gt 0) {
            Write-Host "[INFO] Planned unit test targets: $($TargetLines -join ', ')" -ForegroundColor DarkCyan
        }
        else {
            Write-Host "[INFO] Planned unit test targets: all test files" -ForegroundColor DarkCyan
        }
    }
    else {
        Write-Host "[WARN] Sentinel directory was not found. Continue without sentinel: $SentinelDir" -ForegroundColor Yellow
    }

    & $StartScriptPath
    $StartExitCode = [int]$LASTEXITCODE
    if ($StartExitCode -ne 0) {
        Write-Host "[WARN] $StartScriptPath exited non-zero: start=$StartExitCode" -ForegroundColor Yellow
    }
    $ExitCode = $StartExitCode

    # Wait briefly for process appearance because MO2 launch is asynchronous.
    $processName = "Morrowind"
    $morrowindStarted = $false
    for ($i = 0; $i -lt 30; $i++) {
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            $morrowindStarted = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if ($morrowindStarted) {
        Write-Host "[INFO] Waiting up to $MaxWaitSeconds seconds for Morrowind process to exit..." -ForegroundColor DarkCyan
        $stoppedInTime = $false
        for ($i = 0; $i -lt $MaxWaitSeconds; $i++) {
            if (-not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
                $stoppedInTime = $true
                break
            }
            Start-Sleep -Seconds 1
        }

        if (-not $stoppedInTime) {
            if ($HasStopScript) {
                # Prevent hanging forever when sentinel did not trigger exit.
                Write-Host "[WARN] Morrowind is still running after timeout. Running $StopScriptPath" -ForegroundColor Yellow
                & $StopScriptPath
                for ($i = 0; $i -lt 10; $i++) {
                    if (-not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
                        break
                    }
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
    else {
        Write-Host "[WARN] Morrowind process was not detected. Cleanup continues." -ForegroundColor Yellow
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $ConfigScriptPath = ".\mwmcp_config.ps1"
    if (Test-Path -LiteralPath $ConfigScriptPath) {
        . $ConfigScriptPath
        try {
            $Config = Get-MwmcpConfig
            $MwseLogPath = Join-Path $Config.Paths.morrowindInstallDir "MWSE.log"
        }
        catch {
            $MwseLogStatus = "Failed to resolve MWSE.log path: $($_.Exception.Message)"
            Write-Host "[WARN] $MwseLogStatus" -ForegroundColor Yellow
        }
    }
    else {
        $MwseLogStatus = "Config helper was not found: $ConfigScriptPath"
        Write-Host "[WARN] $MwseLogStatus" -ForegroundColor Yellow
    }

    if ($MwseLogPath -and (Test-Path -LiteralPath $MwseLogPath)) {
        Write-Host "[INFO] Extracting unit test results from $MwseLogPath" -ForegroundColor DarkCyan
        try {
            Copy-Item -LiteralPath $MwseLogPath -Destination $MwseCopyOutputPath -Force
            $SavedMwseCopy = $true
        }
        catch {
            Write-Host "[WARN] Failed to save MWSE.log copy: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        $ExtractedLines = Select-String -LiteralPath $MwseLogPath -Pattern $ExtractPattern | ForEach-Object { $_.Line }
        if ($ExtractedLines.Count -gt 0) {
            Write-Host "[INFO] Extracted $($ExtractedLines.Count) matching line(s)." -ForegroundColor DarkCyan
            $ExtractedLines | ForEach-Object { Write-Host $_ }
            $FoundFailed = ($ExtractedLines | Where-Object { $_ -match "FAILED" }).Count -gt 0
        }
        else {
            Write-Host "[WARN] No matching unit test lines were found in MWSE.log." -ForegroundColor Yellow
        }
    }
    elseif ($MwseLogPath) {
        $MwseLogStatus = "MWSE.log was not found: $MwseLogPath"
        Write-Host "[WARN] $MwseLogStatus" -ForegroundColor Yellow
    }

    $ExtractFileLines = @(
        "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "MWSELogPath: $MwseLogPath",
        "ExtractPattern: $ExtractPattern",
        ""
    )

    if ($MwseLogStatus) {
        $ExtractFileLines += "[WARN] $MwseLogStatus"
    }

    if ($ExtractedLines.Count -gt 0) {
        $ExtractFileLines += $ExtractedLines
    }
    else {
        $ExtractFileLines += "[INFO] No matching lines were extracted."
    }

    Set-Content -LiteralPath $ExtractOutputPath -Value $ExtractFileLines -Encoding UTF8

    if ($FoundFailed -and $ExitCode -eq 0) {
        Write-Host "[WARN] FAILED result detected in MWSE.log. Returning non-zero exit code." -ForegroundColor Yellow
        $ExitCode = 1
    }
}
finally {
    if (Test-Path -LiteralPath $ExtractOutputPath) {
        Write-Host "[INFO] Saved extracted results: $(Convert-ToFileUri -Path $ExtractOutputPath)" -ForegroundColor DarkCyan
    }

    if ($SavedMwseCopy) {
        Write-Host "[INFO] Saved MWSE.log copy: $(Convert-ToFileUri -Path $MwseCopyOutputPath)" -ForegroundColor DarkCyan
    }

    # Restore or clean up the sentinel after the run.
    if ($SentinelOriginalContent -ne $null) {
        Set-Content -LiteralPath $SentinelPath -Value $SentinelOriginalContent -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    elseif ($CreatedSentinel) {
        Remove-Item -LiteralPath $SentinelPath -ErrorAction SilentlyContinue
    }
    Pop-Location
}

exit $ExitCode
