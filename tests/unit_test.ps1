$MaxWaitSeconds = 10

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$ExitCode = 0
$CreatedSentinel = $false

Push-Location $ScriptDir
try {
    $StartScriptPath = ".\start_server_mo2.ps1"
    $StopScriptPath = ".\stop_server.ps1"
    # Sentinel file toggles exit-after-tests behavior in Lua.
    $SentinelPath = ".\..\MWSE\mods\morrowind-mcp\.exit-after-tests"

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
            Write-Host "[INFO] Sentinel file already exists. Reusing: $SentinelPath" -ForegroundColor DarkCyan
        }
        else {
            New-Item -ItemType File -Path $SentinelPath -Force | Out-Null
            $CreatedSentinel = $true
            Write-Host "[INFO] Created sentinel file: $SentinelPath" -ForegroundColor DarkCyan
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
}
finally {
    # Clean up only when this script created the sentinel file.
    if ($CreatedSentinel) {
        Remove-Item -LiteralPath $SentinelPath -ErrorAction SilentlyContinue
    }
    Pop-Location
}

exit $ExitCode
