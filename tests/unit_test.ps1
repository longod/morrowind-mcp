param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$TestTargets,
    [switch]$NoForeground,
    [switch]$VerifyRuntimeAfterTests,
    [ValidateRange(1, 300)]
    [int]$CompletionTimeoutSeconds = 60,
    [ValidateRange(1, 60)]
    [int]$RuntimeReadyTimeoutSeconds = 20
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "mwmcp_test_context.ps1")

$ExitCode = 0
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
$RuntimeProbeStarted = $false
$CompletionOutputPath = $null
$CompletionResult = $null

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
    $TargetLines = @($TestTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($VerifyRuntimeAfterTests -and $TargetLines.Count -gt 0) {
        Write-Host "[ERROR] -VerifyRuntimeAfterTests requires the full unit test suite." -ForegroundColor Red
        exit 1
    }

    # start script is mandatory; stop script is optional fallback on timeout.
    if (-not (Test-Path -LiteralPath $StartScriptPath)) {
        Write-Host "[ERROR] $StartScriptPath was not found." -ForegroundColor Red
        exit 1
    }
    $HasStopScript = Test-Path -LiteralPath $StopScriptPath
    if (-not $HasStopScript) {
        Write-Host "[WARN] $StopScriptPath was not found. Forced stop will be skipped." -ForegroundColor Yellow
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $ConfigScriptPath = ".\mwmcp_config.ps1"
    if (-not (Test-Path -LiteralPath $ConfigScriptPath)) {
        throw "Config helper was not found: $ConfigScriptPath"
    }
    . $ConfigScriptPath
    $Config = Get-MwmcpConfig
    $MwseLogPath = Join-Path $Config.Paths.morrowindInstallDir "MWSE.log"
    $CompletionOutputPath = Join-Path $Config.Paths.modDataDir "tests\unit-results\$RunTimestamp.json"
    if (Test-Path -LiteralPath $CompletionOutputPath) {
        Remove-Item -LiteralPath $CompletionOutputPath -Force
    }

    $UnitTestMode = if ($VerifyRuntimeAfterTests) { "run" } else { "run-and-exit" }
    Set-MwmcpTestContext -UnitTestMode $UnitTestMode -UnitTestTargets $TargetLines -UnitTestRunId $RunTimestamp -AcceptDisclaimer $VerifyRuntimeAfterTests
    if ($TargetLines.Count -gt 0) {
        Write-Host "[INFO] Planned unit test targets: $($TargetLines -join ', ')" -ForegroundColor DarkCyan
    }
    else {
        Write-Host "[INFO] Planned unit test targets: all test files" -ForegroundColor DarkCyan
    }

    if ($VerifyRuntimeAfterTests) {
        Write-Host "[INFO] Running full unit tests and verifying the subsequent runtime startup." -ForegroundColor DarkCyan
        & $StartScriptPath -WaitForServer -ServerReadyTimeoutSeconds $RuntimeReadyTimeoutSeconds
        $RuntimeProbeStarted = $true
    }
    else {
        & $StartScriptPath
    }
    $StartExitCode = [int]$LASTEXITCODE
    if ($StartExitCode -ne 0) {
        Write-Host "[WARN] $StartScriptPath exited non-zero: start=$StartExitCode" -ForegroundColor Yellow
    }

    Write-Host "[INFO] Waiting up to $CompletionTimeoutSeconds seconds for unit test completion..." -ForegroundColor DarkCyan
    $deadline = (Get-Date).AddSeconds($CompletionTimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $CompletionOutputPath -PathType Leaf) {
            try {
                $candidate = Get-Content -LiteralPath $CompletionOutputPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($candidate.version -eq 1 -and $candidate.run_id -eq $RunTimestamp -and $candidate.status -in @("passed", "failed") -and
                    $candidate.tests_passed -is [int64] -and $candidate.tests_failed -is [int64]) {
                    $CompletionResult = $candidate
                    break
                }
                $MwseLogStatus = "Unit test completion result is invalid: $CompletionOutputPath"
                break
            }
            catch {
                $MwseLogStatus = "Failed to read unit test completion result: $($_.Exception.Message)"
                break
            }
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    if (-not $CompletionResult -and -not $MwseLogStatus) {
        $MwseLogStatus = "Unit test completion result timed out after $CompletionTimeoutSeconds seconds: $CompletionOutputPath"
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

    }
    elseif ($MwseLogPath) {
        $MwseLogStatus = "MWSE.log was not found: $MwseLogPath"
        Write-Host "[WARN] $MwseLogStatus" -ForegroundColor Yellow
    }

    if ($CompletionResult) {
        $resultWord = if ($CompletionResult.status -eq "passed") { "PASSED" } else { "FAILED" }
        $ExtractedLines = @(
            "[UnitWind] Completion: run_id=$($CompletionResult.run_id) tests_passed=$($CompletionResult.tests_passed) tests_failed=$($CompletionResult.tests_failed)",
            "[UnitWind] MORROWIND-MCP.UNIT_TEST $resultWord"
        )
        $FoundFailed = $CompletionResult.status -eq "failed"
        $ExtractedLines | ForEach-Object { Write-Host $_ }
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
        Write-Host "[WARN] FAILED result detected in completion JSON. Returning non-zero exit code." -ForegroundColor Yellow
        $ExitCode = 1
    }
}
finally {
    Remove-MwmcpTestContext

    if ($VerifyRuntimeAfterTests -and $RuntimeProbeStarted -and $HasStopScript) {
        Write-Host "[INFO] Stopping Morrowind after runtime verification." -ForegroundColor DarkCyan
        # Keep runner finalization isolated from the stop script.
        & powershell.exe -NoProfile -File $StopScriptPath
        if ([int]$LASTEXITCODE -ne 0) {
            Write-Host "[WARN] $StopScriptPath exited non-zero: stop=$LASTEXITCODE" -ForegroundColor Yellow
            $ExitCode = 1
        }
    }

    if (Test-Path -LiteralPath $ExtractOutputPath) {
        Write-Host "[INFO] Saved extracted results: $(Convert-ToFileUri -Path $ExtractOutputPath)" -ForegroundColor DarkCyan
    }

    if ($SavedMwseCopy) {
        Write-Host "[INFO] Saved MWSE.log copy: $(Convert-ToFileUri -Path $MwseCopyOutputPath)" -ForegroundColor DarkCyan
    }

    $null = Invoke-MwmcpTestRunSummary -TestType "unit_test" -RunTimestamp $RunTimestamp

    Pop-Location
}

exit $ExitCode
