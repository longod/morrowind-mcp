# Provides one shared test context for every runner that launches Morrowind.
$script:TestContextDir = Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\tests"
$script:TestContextPath = Join-Path $script:TestContextDir "test-context.json"
$script:LegacySentinelPaths = @(
    (Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\.unit-test-targets"),
    (Join-Path $PSScriptRoot "..\MWSE\mods\morrowind-mcp\.server-test-running")
)

function Remove-MwmcpTestContext {
    # Cleanup is deliberately unconditional because test runners are serialized.
    if (Test-Path -LiteralPath $script:TestContextPath) {
        Remove-Item -LiteralPath $script:TestContextPath -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Removed test context: $script:TestContextPath" -ForegroundColor DarkCyan
    }
}

function Invoke-MwmcpTestRunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("unit_test", "server_test", "sse_test", "terrain_benchmark")]
        [string]$TestType,
        [Parameter(Mandatory = $true)]
        [string]$RunTimestamp
    )

    $summaryScriptPath = Join-Path $PSScriptRoot "summarize_test_runs.ps1"
    if (-not (Test-Path -LiteralPath $summaryScriptPath)) {
        Write-Host "[WARN] Test summary script was not found: $summaryScriptPath" -ForegroundColor Yellow
        return
    }

    try {
        & $summaryScriptPath -TestType $TestType -RunTimestamp $RunTimestamp
        if ([int]$LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Failed to generate $TestType summary: exit=$LASTEXITCODE" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[WARN] Failed to generate $TestType summary: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Set-MwmcpTestContext {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("run", "run-and-exit", "skip")]
        [string]$UnitTestMode,
        [string[]]$UnitTestTargets = @(),
        [bool]$SuppressAutoContinue = $true,
        [bool]$AcceptDisclaimer = $false
    )

    if (Test-Path -LiteralPath $script:TestContextPath) {
        $existing = Get-Content -LiteralPath $script:TestContextPath -Raw -ErrorAction SilentlyContinue
        $singleLineContent = ($existing -replace "\s+", " ").Trim()
        Write-Host "[WARN] Stale test context detected and replaced: $script:TestContextPath; content=$singleLineContent" -ForegroundColor Yellow
        Remove-Item -LiteralPath $script:TestContextPath -Force -ErrorAction SilentlyContinue
    }

    foreach ($legacyPath in $script:LegacySentinelPaths) {
        if (Test-Path -LiteralPath $legacyPath) {
            Write-Host "[WARN] Legacy test sentinel detected and removed: $legacyPath" -ForegroundColor Yellow
            Remove-Item -LiteralPath $legacyPath -Force -ErrorAction SilentlyContinue
        }
    }

    New-Item -ItemType Directory -Path $script:TestContextDir -Force | Out-Null
    $context = [ordered]@{
        version = 1
        suppress_auto_continue = $SuppressAutoContinue
        accept_disclaimer = $AcceptDisclaimer
        unit_test = [ordered]@{
            mode = $UnitTestMode
            targets = @($UnitTestTargets)
        }
    }
    $json = $context | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:TestContextPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[INFO] Created test context: $script:TestContextPath; unit_test.mode=$UnitTestMode" -ForegroundColor DarkCyan
}
